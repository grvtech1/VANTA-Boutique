// Copyright 2024 Google LLC
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/google/uuid"

	pb "github.com/grvtech1/VANTA-Boutique/src/reviewsservice/genproto"
)

// mysqlStore shares persisted reviews across service replicas.
type mysqlStore struct {
	pool          *sql.DB
	maxPerProduct int
}

// Binary, NO PAD collation preserves case-sensitive product identifiers.
// The prefix index accelerates lookups; the full WHERE comparison remains exact.
const schemaDDL = `
CREATE TABLE IF NOT EXISTS reviews (
    review_id       CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    product_id      TEXT NOT NULL,
    author          TEXT NOT NULL,
    rating          INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT NOT NULL,
    created_at_unix BIGINT NOT NULL,
    INDEX idx_reviews_product (product_id(191), created_at_unix DESC, review_id DESC)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin;
`

// newMySQLStore verifies connectivity and creates the schema, as the previous
// store did. The account needs CREATE plus SELECT/INSERT on the reviews database.
func newMySQLStore(ctx context.Context, databaseURL string, maxPerProduct int) (*mysqlStore, error) {
	if strings.HasPrefix(databaseURL, "postgres://") || strings.HasPrefix(databaseURL, "postgresql://") || strings.HasPrefix(databaseURL, "mysql://") {
		return nil, errors.New("DATABASE_URL must be a MySQL driver DSN, not a URL-style connection string")
	}
	cfg, err := mysql.ParseDSN(databaseURL)
	if err != nil {
		return nil, errors.New("invalid MySQL DATABASE_URL DSN")
	}
	if cfg.DBName == "" {
		return nil, errors.New("MySQL DATABASE_URL must specify a database")
	}
	if cfg.Timeout == 0 {
		cfg.Timeout = 5 * time.Second
	}
	if cfg.ReadTimeout == 0 {
		cfg.ReadTimeout = 5 * time.Second
	}
	if cfg.WriteTimeout == 0 {
		cfg.WriteTimeout = 5 * time.Second
	}
	connector, err := mysql.NewConnector(cfg)
	if err != nil {
		return nil, err
	}
	pool := sql.OpenDB(connector)
	pool.SetMaxOpenConns(10)
	pool.SetMaxIdleConns(10)
	pool.SetConnMaxLifetime(3 * time.Minute)
	pool.SetConnMaxIdleTime(time.Minute)
	if maxPerProduct <= 0 {
		maxPerProduct = 500
	}
	s := &mysqlStore{pool: pool, maxPerProduct: maxPerProduct}
	if err := pool.PingContext(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	if _, err := pool.ExecContext(ctx, schemaDDL); err != nil {
		pool.Close()
		return nil, err
	}
	return s, nil
}

func (s *mysqlStore) List(ctx context.Context, productID string) ([]*pb.Review, float32, error) {
	rows, err := s.pool.QueryContext(ctx,
		`SELECT review_id, product_id, author, rating, comment, created_at_unix
		 FROM reviews WHERE product_id = ?
		 ORDER BY created_at_unix DESC, review_id DESC LIMIT ?`, productID, s.maxPerProduct)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var out []*pb.Review
	for rows.Next() {
		r := &pb.Review{}
		if err := rows.Scan(&r.ReviewId, &r.ProductId, &r.Author, &r.Rating, &r.Comment, &r.CreatedAtUnix); err != nil {
			return nil, 0, err
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return out, average(out), nil
}

func (s *mysqlStore) Add(ctx context.Context, productID, author string, rating int32, comment string) (*pb.Review, error) {
	if author == "" {
		author = "Anonymous"
	}
	r := &pb.Review{
		ReviewId: uuid.NewString(), ProductId: productID, Author: author,
		Rating: rating, Comment: comment, CreatedAtUnix: time.Now().Unix(),
	}
	_, err := s.pool.ExecContext(ctx,
		`INSERT INTO reviews (review_id, product_id, author, rating, comment, created_at_unix)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		r.ReviewId, r.ProductId, r.Author, r.Rating, r.Comment, r.CreatedAtUnix)
	if err != nil {
		return nil, err
	}
	return r, nil
}

func (s *mysqlStore) Ping(ctx context.Context) error { return s.pool.PingContext(ctx) }
func (s *mysqlStore) Close()                         { s.pool.Close() }
