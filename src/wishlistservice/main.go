// Copyright 2026 VANTA Boutique contributors
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

// wishlistservice keeps each shopper's saved items server-side, keyed by the
// session ID the frontend already issues. It is deliberately small: three RPCs,
// an in-memory store behind an interface, gRPC health, graceful drain on
// SIGTERM, and request bounds so a bad client cannot grow memory unbounded.
package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/keepalive"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	pb "github.com/grvtech1/VANTA-Boutique/src/wishlistservice/genproto"
)

const defaultPort = "50052"

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.Formatter = &logrus.JSONFormatter{
		FieldMap: logrus.FieldMap{
			logrus.FieldKeyTime:  "timestamp",
			logrus.FieldKeyLevel: "severity",
			logrus.FieldKeyMsg:   "message",
		},
		TimestampFormat: time.RFC3339Nano,
	}
	log.Out = os.Stdout
}

func main() {
	cfg := loadConfig()
	log.SetLevel(cfg.logLevel)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", cfg.port))
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	srv := grpc.NewServer(
		grpc.MaxRecvMsgSize(cfg.maxRecvMsgBytes),
		grpc.MaxConcurrentStreams(1000),
		grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
			MinTime:             15 * time.Second,
			PermitWithoutStream: true,
		}),
		grpc.KeepaliveParams(keepalive.ServerParameters{
			MaxConnectionIdle: 5 * time.Minute,
			Time:              2 * time.Hour,
			Timeout:           20 * time.Second,
		}),
	)

	log.Warn("using in-memory store (single replica only; data is not durable)")
	svc := &server{store: newMemStore(cfg.maxItemsPerUser, cfg.maxUsers), cfg: cfg}
	pb.RegisterWishlistServiceServer(srv, svc)

	healthSrv := health.NewServer()
	healthpb.RegisterHealthServer(srv, healthSrv)
	reflection.Register(srv)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	serveErr := make(chan error, 1)
	go func() {
		log.Infof("Wishlist Service listening on port %s", cfg.port)
		healthSrv.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
		if err := srv.Serve(lis); err != nil && !errors.Is(err, grpc.ErrServerStopped) {
			serveErr <- err
		}
	}()

	select {
	case err := <-serveErr:
		log.Fatalf("failed to serve: %v", err)
	case <-ctx.Done():
		log.Info("shutdown signal received, draining connections")
	}

	// Readiness flips first so no new traffic is routed while we drain.
	healthSrv.SetServingStatus("", healthpb.HealthCheckResponse_NOT_SERVING)
	healthSrv.Shutdown()

	stopped := make(chan struct{})
	go func() {
		srv.GracefulStop()
		close(stopped)
	}()
	select {
	case <-stopped:
		log.Info("graceful shutdown complete")
	case <-time.After(cfg.shutdownGrace):
		log.Warn("graceful shutdown timed out; forcing stop")
		srv.Stop()
	}
}

// server implements the WishlistService gRPC API.
type server struct {
	pb.UnimplementedWishlistServiceServer
	store Store
	cfg   config
}

func (s *server) GetWishlist(ctx context.Context, in *pb.GetWishlistRequest) (*pb.Wishlist, error) {
	userID, err := s.id(in.GetUserId(), "user_id")
	if err != nil {
		return nil, err
	}
	items, err := s.store.Get(ctx, userID)
	if err != nil {
		log.WithFields(logrus.Fields{"user_id": userID, "error": err}).Error("store get failed")
		return nil, status.Error(codes.Internal, "failed to load wishlist")
	}
	return &pb.Wishlist{UserId: userID, Items: items}, nil
}

func (s *server) AddItem(ctx context.Context, in *pb.AddWishlistItemRequest) (*pb.Wishlist, error) {
	userID, err := s.id(in.GetUserId(), "user_id")
	if err != nil {
		return nil, err
	}
	productID, err := s.id(in.GetProductId(), "product_id")
	if err != nil {
		return nil, err
	}
	items, err := s.store.Add(ctx, userID, productID)
	if err != nil {
		log.WithFields(logrus.Fields{"user_id": userID, "product_id": productID, "error": err}).Error("store add failed")
		return nil, status.Error(codes.Internal, "failed to save item")
	}
	log.WithFields(logrus.Fields{"user_id": userID, "product_id": productID, "count": len(items)}).Info("AddItem")
	return &pb.Wishlist{UserId: userID, Items: items}, nil
}

func (s *server) RemoveItem(ctx context.Context, in *pb.RemoveWishlistItemRequest) (*pb.Wishlist, error) {
	userID, err := s.id(in.GetUserId(), "user_id")
	if err != nil {
		return nil, err
	}
	productID, err := s.id(in.GetProductId(), "product_id")
	if err != nil {
		return nil, err
	}
	items, err := s.store.Remove(ctx, userID, productID)
	if err != nil {
		log.WithFields(logrus.Fields{"user_id": userID, "product_id": productID, "error": err}).Error("store remove failed")
		return nil, status.Error(codes.Internal, "failed to remove item")
	}
	log.WithFields(logrus.Fields{"user_id": userID, "product_id": productID, "count": len(items)}).Info("RemoveItem")
	return &pb.Wishlist{UserId: userID, Items: items}, nil
}

// id trims and bounds an identifier field. IDs are opaque strings from the
// frontend (session UUIDs, catalog product IDs); the cap keeps a hostile client
// from padding the store with kilobyte-long keys.
func (s *server) id(v, field string) (string, error) {
	v = strings.TrimSpace(v)
	if v == "" {
		return "", status.Errorf(codes.InvalidArgument, "%s is required", field)
	}
	if utf8.RuneCountInString(v) > s.cfg.maxIDLen {
		return "", status.Errorf(codes.InvalidArgument, "%s must be at most %d characters", field, s.cfg.maxIDLen)
	}
	return v, nil
}
