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
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/reviewsservice/genproto"
)

func TestAverage(t *testing.T) {
	cases := []struct {
		name    string
		ratings []int32
		want    float32
	}{
		{"empty", nil, 0},
		{"single", []int32{4}, 4},
		{"exact", []int32{4, 5, 3}, 4},
		{"rounded", []int32{5, 4, 4, 4}, 4.3}, // 17/4 = 4.25 -> 4.3
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			reviews := make([]*pb.Review, len(tc.ratings))
			for i, r := range tc.ratings {
				reviews[i] = &pb.Review{Rating: r}
			}
			if got := average(reviews); got != tc.want {
				t.Errorf("average(%v) = %v, want %v", tc.ratings, got, tc.want)
			}
		})
	}
}

func TestStoreAddAndList(t *testing.T) {
	s := newReviewStore(nil)
	s.add("PROD1", "Alice", 5, "great")
	s.add("PROD1", "Bob", 3, "ok")
	s.add("PROD2", "Carol", 4, "nice")

	reviews, avg := s.list("PROD1")
	if len(reviews) != 2 {
		t.Fatalf("PROD1 review count = %d, want 2", len(reviews))
	}
	if avg != 4 {
		t.Errorf("PROD1 average = %v, want 4", avg)
	}

	if _, avg := s.list("UNKNOWN"); avg != 0 {
		t.Errorf("unknown product average = %v, want 0", avg)
	}
}

func TestStoreDefaultsAnonymous(t *testing.T) {
	s := newReviewStore(nil)
	r := s.add("PROD1", "", 4, "no name")
	if r.Author != "Anonymous" {
		t.Errorf("Author = %q, want Anonymous", r.Author)
	}
	if r.ReviewId == "" {
		t.Error("ReviewId should be generated")
	}
}

func TestAddReviewValidation(t *testing.T) {
	s := &server{store: newReviewStore(nil)}
	ctx := context.Background()

	cases := []struct {
		name string
		req  *pb.AddReviewRequest
		code codes.Code
	}{
		{"missing product", &pb.AddReviewRequest{Rating: 3}, codes.InvalidArgument},
		{"rating too low", &pb.AddReviewRequest{ProductId: "P", Rating: 0}, codes.InvalidArgument},
		{"rating too high", &pb.AddReviewRequest{ProductId: "P", Rating: 6}, codes.InvalidArgument},
		{"valid", &pb.AddReviewRequest{ProductId: "P", Rating: 5, Author: "A"}, codes.OK},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := s.AddReview(ctx, tc.req)
			if status.Code(err) != tc.code {
				t.Errorf("AddReview code = %v, want %v (err=%v)", status.Code(err), tc.code, err)
			}
		})
	}
}

func TestGetReviewsValidation(t *testing.T) {
	s := &server{store: newReviewStore(nil)}
	if _, err := s.GetReviews(context.Background(), &pb.GetReviewsRequest{}); status.Code(err) != codes.InvalidArgument {
		t.Errorf("GetReviews with empty product_id should be InvalidArgument, got %v", err)
	}
}
