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

// inventoryservice reports stock levels so the storefront can show
// "in stock", "only N left" and "sold out". Quantities are seeded at startup
// (built-in table or INVENTORY_SEED_FILE) and served read-only over gRPC.
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

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/keepalive"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	pb "github.com/grvtech1/VANTA-Boutique/src/inventoryservice/genproto"
)

const defaultPort = "50053"

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

	seed, err := loadSeed(cfg.seedFile)
	if err != nil {
		log.Fatalf("failed to load inventory seed: %v", err)
	}
	store := newMemStore(seed, cfg.lowStockThreshold)
	log.WithFields(logrus.Fields{"products": len(seed), "low_stock_threshold": cfg.lowStockThreshold}).Info("inventory loaded")

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

	pb.RegisterInventoryServiceServer(srv, &server{store: store, cfg: cfg})

	healthSrv := health.NewServer()
	healthpb.RegisterHealthServer(srv, healthSrv)
	reflection.Register(srv)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	serveErr := make(chan error, 1)
	go func() {
		log.Infof("Inventory Service listening on port %s", cfg.port)
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

// server implements the InventoryService gRPC API.
type server struct {
	pb.UnimplementedInventoryServiceServer
	store Store
	cfg   config
}

func (s *server) GetStock(ctx context.Context, in *pb.GetStockRequest) (*pb.StockLevel, error) {
	productID := strings.TrimSpace(in.GetProductId())
	if productID == "" {
		return nil, status.Error(codes.InvalidArgument, "product_id is required")
	}
	level, ok := s.store.Get(ctx, productID)
	if !ok {
		return nil, status.Errorf(codes.NotFound, "no stock record for product %q", productID)
	}
	return level, nil
}

func (s *server) ListStock(ctx context.Context, in *pb.ListStockRequest) (*pb.ListStockResponse, error) {
	if len(in.GetProductIds()) > s.cfg.maxIDs {
		return nil, status.Errorf(codes.InvalidArgument, "at most %d product_ids per request", s.cfg.maxIDs)
	}
	ids := make([]string, 0, len(in.GetProductIds()))
	for _, id := range in.GetProductIds() {
		if id = strings.TrimSpace(id); id != "" {
			ids = append(ids, id)
		}
	}
	levels := s.store.List(ctx, ids)
	log.WithFields(logrus.Fields{"requested": len(ids), "returned": len(levels)}).Debug("ListStock")
	return &pb.ListStockResponse{Levels: levels}, nil
}
