// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/reviewsservice/genproto"
)

// pgStore is a durable, shared PostgreSQL-backed Store. Because state lives in
// the database rather than the process, reviewsservice can run multiple replicas
// (and an HPA) without divergence — the horizontal-scaling story the in-memory
// store cannot provide.
type pgStore struct {
	pool          *pgxpool.Pool
	maxPerProduct int
}

const schemaDDL = `
CREATE TABLE IF NOT EXISTS reviews (
    review_id      UUID PRIMARY KEY,
    product_id     TEXT NOT NULL,
    author         TEXT NOT NULL,
    rating         INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment        TEXT NOT NULL DEFAULT '',
    created_at_unix BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_reviews_product
    ON reviews (product_id, created_at_unix DESC);
`

// newPgStore connects (with a bounded pool), verifies connectivity, and ensures
// the schema exists. It fails fast so a misconfigured DB surfaces at startup.
func newPgStore(ctx context.Context, databaseURL string, maxPerProduct int) (*pgStore, error) {
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 10
	cfg.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	s := &pgStore{pool: pool, maxPerProduct: maxPerProduct}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	if _, err := pool.Exec(ctx, schemaDDL); err != nil {
		pool.Close()
		return nil, err
	}
	return s, nil
}

func (s *pgStore) List(ctx context.Context, productID string) ([]*pb.Review, float32, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT review_id, product_id, author, rating, comment, created_at_unix
		   FROM reviews
		  WHERE product_id = $1
		  ORDER BY created_at_unix DESC
		  LIMIT $2`,
		productID, s.maxPerProduct)
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

func (s *pgStore) Add(ctx context.Context, productID, author string, rating int32, comment string) (*pb.Review, error) {
	if author == "" {
		author = "Anonymous"
	}
	r := &pb.Review{
		ReviewId:      uuid.NewString(),
		ProductId:     productID,
		Author:        author,
		Rating:        rating,
		Comment:       comment,
		CreatedAtUnix: time.Now().Unix(),
	}
	_, err := s.pool.Exec(ctx,
		`INSERT INTO reviews (review_id, product_id, author, rating, comment, created_at_unix)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		r.ReviewId, r.ProductId, r.Author, r.Rating, r.Comment, r.CreatedAtUnix)
	if err != nil {
		return nil, err
	}
	return r, nil
}

// Ping reports database connectivity; main.go uses it to drive the gRPC health
// status so readiness reflects whether the DB is actually reachable.
func (s *pgStore) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

// Close releases the connection pool.
func (s *pgStore) Close() {
	s.pool.Close()
}
