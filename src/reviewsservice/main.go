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
	"fmt"
	"net"
	"os"
	"time"

	"github.com/sirupsen/logrus"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/reviewsservice/genproto"
)

const defaultPort = "50051"

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.Level = logrus.DebugLevel
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
	port := defaultPort
	if value, ok := os.LookupEnv("PORT"); ok {
		port = value
	}

	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", port))
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	srv := grpc.NewServer()

	svc := &server{store: newReviewStore(seedReviews())}
	pb.RegisterReviewsServiceServer(srv, svc)

	healthcheck := health.NewServer()
	healthpb.RegisterHealthServer(srv, healthcheck)

	// Reflection lets grpcurl and other tools introspect the service.
	reflection.Register(srv)

	log.Infof("Reviews Service listening on port %s", port)
	if err := srv.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}

// server implements the ReviewsService gRPC API.
type server struct {
	pb.UnimplementedReviewsServiceServer
	store *reviewStore
}

// GetReviews returns all reviews for a product plus its aggregate rating.
func (s *server) GetReviews(ctx context.Context, in *pb.GetReviewsRequest) (*pb.GetReviewsResponse, error) {
	if in.GetProductId() == "" {
		return nil, status.Error(codes.InvalidArgument, "product_id is required")
	}
	log.Infof("[GetReviews] product_id=%q", in.GetProductId())

	reviews, avg := s.store.list(in.GetProductId())
	return &pb.GetReviewsResponse{
		Reviews:       reviews,
		AverageRating: avg,
		Count:         int32(len(reviews)),
	}, nil
}

// AddReview validates and stores a new review for a product.
func (s *server) AddReview(ctx context.Context, in *pb.AddReviewRequest) (*pb.AddReviewResponse, error) {
	if in.GetProductId() == "" {
		return nil, status.Error(codes.InvalidArgument, "product_id is required")
	}
	if in.GetRating() < 1 || in.GetRating() > 5 {
		return nil, status.Errorf(codes.InvalidArgument, "rating must be between 1 and 5, got %d", in.GetRating())
	}
	log.Infof("[AddReview] product_id=%q rating=%d", in.GetProductId(), in.GetRating())

	review := s.store.add(in.GetProductId(), in.GetAuthor(), in.GetRating(), in.GetComment())
	return &pb.AddReviewResponse{Review: review}, nil
}
