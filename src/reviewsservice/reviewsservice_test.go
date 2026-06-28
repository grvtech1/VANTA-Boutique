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
	"strings"
	"sync"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/reviewsservice/genproto"
)

// almostEqual compares float32 values with a small tolerance. Direct equality on
// floats is brittle (e.g. 4.3 is not exactly representable), so tests use this.
func almostEqual(a, b float32) bool {
	d := a - b
	if d < 0 {
		d = -d
	}
	return d < 0.001
}

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
			if got := average(reviews); !almostEqual(got, tc.want) {
				t.Errorf("average(%v) = %v, want %v", tc.ratings, got, tc.want)
			}
		})
	}
}

func TestStoreAddAndList(t *testing.T) {
	s := newReviewStore(nil, 0)
	s.Add("PROD1", "Alice", 5, "great")
	s.Add("PROD1", "Bob", 3, "ok")
	s.Add("PROD2", "Carol", 4, "nice")

	reviews, avg := s.List("PROD1")
	if len(reviews) != 2 {
		t.Fatalf("PROD1 review count = %d, want 2", len(reviews))
	}
	if !almostEqual(avg, 4) {
		t.Errorf("PROD1 average = %v, want 4", avg)
	}

	if _, avg := s.List("UNKNOWN"); !almostEqual(avg, 0) {
		t.Errorf("unknown product average = %v, want 0", avg)
	}
}

func TestStoreListNewestFirst(t *testing.T) {
	s := newReviewStore(nil, 0)
	first := s.Add("P", "A", 5, "first")
	// CreatedAtUnix has 1s resolution; force a deterministic ordering.
	first.CreatedAtUnix = 100
	second := s.Add("P", "B", 4, "second")
	second.CreatedAtUnix = 200

	reviews, _ := s.List("P")
	if len(reviews) != 2 || reviews[0].Comment != "second" {
		t.Fatalf("expected newest-first ordering, got %+v", reviews)
	}
}

func TestStoreDefaultsAnonymous(t *testing.T) {
	s := newReviewStore(nil, 0)
	r := s.Add("PROD1", "", 4, "no name")
	if r.Author != "Anonymous" {
		t.Errorf("Author = %q, want Anonymous", r.Author)
	}
	if r.ReviewId == "" {
		t.Error("ReviewId should be generated")
	}
}

func TestStoreBounded(t *testing.T) {
	const cap = 5
	s := newReviewStore(nil, cap)
	for i := 0; i < 20; i++ {
		s.Add("P", "A", 5, "c")
	}
	reviews, _ := s.List("P")
	if len(reviews) != cap {
		t.Errorf("store kept %d reviews, want cap %d", len(reviews), cap)
	}
}

// TestStoreConcurrent is intended to be run with -race to catch data races in
// the store under simultaneous readers and writers.
func TestStoreConcurrent(t *testing.T) {
	s := newReviewStore(nil, 1000)
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(2)
		go func() { defer wg.Done(); s.Add("P", "writer", 5, "c") }()
		go func() { defer wg.Done(); _, _ = s.List("P") }()
	}
	wg.Wait()
	if reviews, _ := s.List("P"); len(reviews) != 50 {
		t.Errorf("concurrent writes stored %d reviews, want 50", len(reviews))
	}
}

func testServer() *server {
	return &server{store: newReviewStore(nil, 500), cfg: defaultConfig()}
}

func TestAddReviewValidation(t *testing.T) {
	s := testServer()
	ctx := context.Background()

	cases := []struct {
		name string
		req  *pb.AddReviewRequest
		code codes.Code
	}{
		{"missing product", &pb.AddReviewRequest{Rating: 3}, codes.InvalidArgument},
		{"rating too low", &pb.AddReviewRequest{ProductId: "P", Rating: 0}, codes.InvalidArgument},
		{"rating too high", &pb.AddReviewRequest{ProductId: "P", Rating: 6}, codes.InvalidArgument},
		{"author too long", &pb.AddReviewRequest{ProductId: "P", Rating: 5, Author: strings.Repeat("x", 81)}, codes.InvalidArgument},
		{"comment too long", &pb.AddReviewRequest{ProductId: "P", Rating: 5, Comment: strings.Repeat("x", 1001)}, codes.InvalidArgument},
		{"whitespace product", &pb.AddReviewRequest{ProductId: "   ", Rating: 5}, codes.InvalidArgument},
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
	s := testServer()
	if _, err := s.GetReviews(context.Background(), &pb.GetReviewsRequest{}); status.Code(err) != codes.InvalidArgument {
		t.Errorf("GetReviews with empty product_id should be InvalidArgument, got %v", err)
	}
}
