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
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/reviewsservice/genproto"
)

// reviewStore is a concurrency-safe in-memory store of product reviews.
//
// This intentionally mirrors the demo's other stateless services: data is held
// in memory and seeded at startup. Swapping this for Postgres/DynamoDB would be
// a drop-in change behind the same list/add methods.
type reviewStore struct {
	mu       sync.RWMutex
	byProduct map[string][]*pb.Review
}

func newReviewStore(seed map[string][]*pb.Review) *reviewStore {
	if seed == nil {
		seed = map[string][]*pb.Review{}
	}
	return &reviewStore{byProduct: seed}
}

// list returns a product's reviews (newest first) and the mean rating.
func (s *reviewStore) list(productID string) ([]*pb.Review, float32) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	src := s.byProduct[productID]
	out := make([]*pb.Review, len(src))
	copy(out, src)
	sort.SliceStable(out, func(i, j int) bool {
		return out[i].CreatedAtUnix > out[j].CreatedAtUnix
	})
	return out, average(out)
}

// add stores a new review and returns it. Caller must validate rating range.
func (s *reviewStore) add(productID, author string, rating int32, comment string) *pb.Review {
	if author == "" {
		author = "Anonymous"
	}
	review := &pb.Review{
		ReviewId:      uuid.NewString(),
		ProductId:     productID,
		Author:        author,
		Rating:        rating,
		Comment:       comment,
		CreatedAtUnix: time.Now().Unix(),
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.byProduct[productID] = append(s.byProduct[productID], review)
	return review
}

// average computes the mean rating, rounded to one decimal place.
func average(reviews []*pb.Review) float32 {
	if len(reviews) == 0 {
		return 0
	}
	var total int32
	for _, r := range reviews {
		total += r.Rating
	}
	mean := float64(total) / float64(len(reviews))
	return float32(int(mean*10+0.5)) / 10
}

// seedReviews provides a small set of starter reviews keyed by the product IDs
// shipped in productcatalogservice/products.json, so the UI has data on day one.
func seedReviews() map[string][]*pb.Review {
	now := time.Now().Unix()
	mk := func(productID, author string, rating int32, comment string, ageDays int64) *pb.Review {
		return &pb.Review{
			ReviewId:      uuid.NewString(),
			ProductId:     productID,
			Author:        author,
			Rating:        rating,
			Comment:       comment,
			CreatedAtUnix: now - ageDays*86400,
		}
	}
	return map[string][]*pb.Review{
		// Sunglasses
		"OLJCESPC7Z": {
			mk("OLJCESPC7Z", "Priya", 5, "Crisp optics and they feel premium. Worth it.", 2),
			mk("OLJCESPC7Z", "Daniel", 4, "Great look, slightly tight fit for me.", 9),
		},
		// Tank Top
		"66VCHSJNUP": {
			mk("66VCHSJNUP", "Mei", 4, "Soft fabric, holds shape after washes.", 5),
		},
		// Watch
		"1YMWWN1N4O": {
			mk("1YMWWN1N4O", "Arjun", 5, "Elegant and the strap is genuine leather.", 1),
			mk("1YMWWN1N4O", "Sofia", 5, "Got compliments all week.", 12),
			mk("1YMWWN1N4O", "Ken", 3, "Beautiful, but battery drained quickly.", 20),
		},
		// Loafers
		"L9ECAV7KIM": {
			mk("L9ECAV7KIM", "Ravi", 4, "Comfortable out of the box.", 6),
		},
		// Hairdryer
		"2ZYFJ3GM2N": {
			mk("2ZYFJ3GM2N", "Lena", 5, "Powerful and surprisingly quiet.", 3),
		},
	}
}
