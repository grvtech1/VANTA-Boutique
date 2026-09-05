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

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"sync"

	pb "github.com/grvtech1/VANTA-Boutique/src/inventoryservice/genproto"
)

// Store answers stock questions. Read-mostly: the storefront only reads, so the
// in-memory map is protected by an RWMutex and reads never block each other.
type Store interface {
	Get(ctx context.Context, productID string) (*pb.StockLevel, bool)
	List(ctx context.Context, productIDs []string) []*pb.StockLevel
}

type memStore struct {
	mu        sync.RWMutex
	qty       map[string]int32
	threshold int32
}

func newMemStore(seed map[string]int32, threshold int32) *memStore {
	if threshold < 0 {
		threshold = 0
	}
	qty := make(map[string]int32, len(seed))
	for id, q := range seed {
		if q < 0 {
			q = 0
		}
		qty[id] = q
	}
	return &memStore{qty: qty, threshold: threshold}
}

func (s *memStore) Get(_ context.Context, productID string) (*pb.StockLevel, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	q, ok := s.qty[productID]
	if !ok {
		return nil, false
	}
	return s.level(productID, q), true
}

// List returns levels for the requested IDs (unknown IDs are skipped) or, when
// no IDs are given, every product the store knows about, sorted by ID so the
// output is stable.
func (s *memStore) List(_ context.Context, productIDs []string) []*pb.StockLevel {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if len(productIDs) == 0 {
		productIDs = make([]string, 0, len(s.qty))
		for id := range s.qty {
			productIDs = append(productIDs, id)
		}
		sort.Strings(productIDs)
	}
	out := make([]*pb.StockLevel, 0, len(productIDs))
	for _, id := range productIDs {
		if q, ok := s.qty[id]; ok {
			out = append(out, s.level(id, q))
		}
	}
	return out
}

func (s *memStore) level(productID string, q int32) *pb.StockLevel {
	return &pb.StockLevel{
		ProductId:         productID,
		Quantity:          q,
		LowStockThreshold: s.threshold,
		Status:            statusFor(q, s.threshold),
	}
}

// statusFor derives the customer-facing status: zero is sold out, at or below
// the threshold is low, anything else is plainly in stock.
func statusFor(q, threshold int32) pb.StockStatus {
	switch {
	case q <= 0:
		return pb.StockStatus_OUT_OF_STOCK
	case q <= threshold:
		return pb.StockStatus_LOW_STOCK
	default:
		return pb.StockStatus_IN_STOCK
	}
}

// loadSeed returns the starting quantities: a JSON object of product ID to
// quantity from INVENTORY_SEED_FILE when set (a ConfigMap in Kubernetes),
// otherwise the built-in catalog numbers below.
func loadSeed(path string) (map[string]int32, error) {
	if path == "" {
		return defaultSeed(), nil
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read seed file: %w", err)
	}
	seed := map[string]int32{}
	if err := json.Unmarshal(raw, &seed); err != nil {
		return nil, fmt.Errorf("parse seed file %s: %w", path, err)
	}
	if len(seed) == 0 {
		return nil, fmt.Errorf("seed file %s has no products", path)
	}
	return seed, nil
}

// defaultSeed mirrors productcatalogservice/products.json. A few items are
// deliberately low or sold out so every stock state is visible on day one.
func defaultSeed() map[string]int32 {
	return map[string]int32{
		"OLJCESPC7Z": 24, // Aviator Sunglasses
		"66VCHSJNUP": 40, // Cropped Tank Top
		"1YMWWN1N4O": 3,  // Gold-Tone Watch — low
		"L9ECAV7KIM": 18,
		"2ZYFJ3GM2N": 12,
		"0PUK6V6EV0": 5, // low (at threshold)
		"LS4PSXUNUM": 0, // sold out
		"9SIQT8TOJO": 31,
		"6E92ZMYYFZ": 9,
		"VNTBELT001": 27,
		"VNTSCRF002": 0, // sold out
		"VNTBKPK003": 14,
		"VNTSHRT004": 36,
		"VNTJCKT005": 11,
		"VNTSWTR006": 22,
		"VNTSNKR007": 16,
		"VNTBOOT008": 2, // low
		"VNTVASE009": 19,
		"VNTBORD010": 8,
		"VNTROLL011": 45,
		"VNTCNDL012": 60,
		"VNTVRHD013": 4, // low
		"VNTERBD014": 33,
		"VNTSPKR015": 13,
		"VNTLAMP016": 21,
	}
}
