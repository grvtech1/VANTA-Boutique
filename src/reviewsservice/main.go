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

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/reviewsservice/genproto"
)

const defaultPort = "50051"

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
		// Bound a single request's size so an oversized payload can't be used to
		// exhaust memory before application-level validation runs.
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

	svc := &server{
		store: newReviewStore(seedReviews(), cfg.maxReviewsPerProduct),
		cfg:   cfg,
	}
	pb.RegisterReviewsServiceServer(srv, svc)

	healthSrv := health.NewServer()
	healthpb.RegisterHealthServer(srv, healthSrv)

	// Reflection lets grpcurl and other tools introspect the service.
	reflection.Register(srv)

	// Signal-aware context so SIGTERM (rolling updates) triggers a clean drain.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	serveErr := make(chan error, 1)
	go func() {
		log.Infof("Reviews Service listening on port %s", cfg.port)
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

	// Flip health to NOT_SERVING first so readiness probes / load balancers stop
	// routing new traffic before we stop accepting requests.
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

// server implements the ReviewsService gRPC API.
type server struct {
	pb.UnimplementedReviewsServiceServer
	store Store
	cfg   config
}

// GetReviews returns all reviews for a product plus its aggregate rating.
func (s *server) GetReviews(ctx context.Context, in *pb.GetReviewsRequest) (*pb.GetReviewsResponse, error) {
	productID := strings.TrimSpace(in.GetProductId())
	if productID == "" {
		return nil, status.Error(codes.InvalidArgument, "product_id is required")
	}

	reviews, avg := s.store.List(productID)
	log.WithFields(logrus.Fields{"product_id": productID, "count": len(reviews)}).Debug("GetReviews")
	return &pb.GetReviewsResponse{
		Reviews:       reviews,
		AverageRating: avg,
		Count:         int32(len(reviews)),
	}, nil
}

// AddReview validates and stores a new review for a product. All free-text
// input is trimmed and length-bounded to keep stored data sane and to prevent
// a single oversized field from bloating the store.
func (s *server) AddReview(ctx context.Context, in *pb.AddReviewRequest) (*pb.AddReviewResponse, error) {
	productID := strings.TrimSpace(in.GetProductId())
	author := strings.TrimSpace(in.GetAuthor())
	comment := strings.TrimSpace(in.GetComment())

	if productID == "" {
		return nil, status.Error(codes.InvalidArgument, "product_id is required")
	}
	if in.GetRating() < 1 || in.GetRating() > 5 {
		return nil, status.Errorf(codes.InvalidArgument, "rating must be between 1 and 5, got %d", in.GetRating())
	}
	if utf8.RuneCountInString(author) > s.cfg.maxAuthorLen {
		return nil, status.Errorf(codes.InvalidArgument, "author must be at most %d characters", s.cfg.maxAuthorLen)
	}
	if utf8.RuneCountInString(comment) > s.cfg.maxCommentLen {
		return nil, status.Errorf(codes.InvalidArgument, "comment must be at most %d characters", s.cfg.maxCommentLen)
	}

	review := s.store.Add(productID, author, in.GetRating(), comment)
	log.WithFields(logrus.Fields{"product_id": productID, "rating": in.GetRating()}).Info("AddReview")
	return &pb.AddReviewResponse{Review: review}, nil
}
