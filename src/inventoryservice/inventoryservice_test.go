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
	"os"
	"path/filepath"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/grvtech1/VANTA-Boutique/src/inventoryservice/genproto"
)

func TestStatusFor(t *testing.T) {
	cases := []struct {
		qty, threshold int32
		want           pb.StockStatus
	}{
		{0, 5, pb.StockStatus_OUT_OF_STOCK},
		{-3, 5, pb.StockStatus_OUT_OF_STOCK},
		{1, 5, pb.StockStatus_LOW_STOCK},
		{5, 5, pb.StockStatus_LOW_STOCK}, // at the threshold counts as low
		{6, 5, pb.StockStatus_IN_STOCK},
		{100, 0, pb.StockStatus_IN_STOCK},
	}
	for _, tc := range cases {
		if got := statusFor(tc.qty, tc.threshold); got != tc.want {
			t.Errorf("statusFor(%d, %d) = %v, want %v", tc.qty, tc.threshold, got, tc.want)
		}
	}
}

func TestStoreGetAndList(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(map[string]int32{"A": 10, "B": 2, "C": 0, "D": -1}, 3)

	lvl, ok := s.Get(ctx, "B")
	if !ok || lvl.Quantity != 2 || lvl.Status != pb.StockStatus_LOW_STOCK || lvl.LowStockThreshold != 3 {
		t.Fatalf("Get(B) = %+v, ok=%v", lvl, ok)
	}
	if lvl, ok := s.Get(ctx, "D"); !ok || lvl.Quantity != 0 || lvl.Status != pb.StockStatus_OUT_OF_STOCK {
		t.Errorf("negative seed should clamp to 0 / sold out, got %+v", lvl)
	}
	if _, ok := s.Get(ctx, "nope"); ok {
		t.Errorf("unknown product should not be found")
	}

	// explicit IDs: unknown ones are skipped, order preserved
	got := s.List(ctx, []string{"C", "zzz", "A"})
	if len(got) != 2 || got[0].ProductId != "C" || got[1].ProductId != "A" {
		t.Fatalf("List(C,zzz,A) = %v", got)
	}
	// no IDs: everything, sorted
	all := s.List(ctx, nil)
	if len(all) != 4 || all[0].ProductId != "A" || all[3].ProductId != "D" {
		t.Fatalf("List(all) = %v", all)
	}
}

func TestDefaultSeedCoversEveryStatus(t *testing.T) {
	s := newMemStore(defaultSeed(), defaultConfig().lowStockThreshold)
	seen := map[pb.StockStatus]bool{}
	for _, lvl := range s.List(context.Background(), nil) {
		seen[lvl.Status] = true
	}
	for _, st := range []pb.StockStatus{pb.StockStatus_IN_STOCK, pb.StockStatus_LOW_STOCK, pb.StockStatus_OUT_OF_STOCK} {
		if !seen[st] {
			t.Errorf("default seed never produces %v", st)
		}
	}
}

func TestLoadSeedFile(t *testing.T) {
	dir := t.TempDir()
	good := filepath.Join(dir, "seed.json")
	os.WriteFile(good, []byte(`{"X": 7, "Y": 0}`), 0o600)
	seed, err := loadSeed(good)
	if err != nil || seed["X"] != 7 || seed["Y"] != 0 {
		t.Fatalf("loadSeed(good) = %v, %v", seed, err)
	}

	bad := filepath.Join(dir, "bad.json")
	os.WriteFile(bad, []byte(`not json`), 0o600)
	if _, err := loadSeed(bad); err == nil {
		t.Errorf("malformed seed file should fail")
	}
	empty := filepath.Join(dir, "empty.json")
	os.WriteFile(empty, []byte(`{}`), 0o600)
	if _, err := loadSeed(empty); err == nil {
		t.Errorf("empty seed file should fail")
	}
	if _, err := loadSeed(filepath.Join(dir, "missing.json")); err == nil {
		t.Errorf("missing seed file should fail")
	}
	if seed, err := loadSeed(""); err != nil || len(seed) == 0 {
		t.Errorf("no path should fall back to the built-in seed")
	}
}

func TestServer(t *testing.T) {
	ctx := context.Background()
	cfg := defaultConfig()
	cfg.maxIDs = 2
	srv := &server{store: newMemStore(map[string]int32{"A": 10, "B": 0}, 5), cfg: cfg}

	if _, err := srv.GetStock(ctx, &pb.GetStockRequest{}); status.Code(err) != codes.InvalidArgument {
		t.Errorf("blank product_id: code = %v", status.Code(err))
	}
	if _, err := srv.GetStock(ctx, &pb.GetStockRequest{ProductId: "nope"}); status.Code(err) != codes.NotFound {
		t.Errorf("unknown product: code = %v", status.Code(err))
	}
	lvl, err := srv.GetStock(ctx, &pb.GetStockRequest{ProductId: " B "})
	if err != nil || lvl.Status != pb.StockStatus_OUT_OF_STOCK {
		t.Errorf("GetStock(B) = %+v, %v", lvl, err)
	}

	if _, err := srv.ListStock(ctx, &pb.ListStockRequest{ProductIds: []string{"A", "B", "C"}}); status.Code(err) != codes.InvalidArgument {
		t.Errorf("over maxIDs: code = %v", status.Code(err))
	}
	resp, err := srv.ListStock(ctx, &pb.ListStockRequest{ProductIds: []string{"A", " "}})
	if err != nil || len(resp.Levels) != 1 || resp.Levels[0].ProductId != "A" {
		t.Errorf("ListStock(A, blank) = %v, %v", resp, err)
	}
	resp, _ = srv.ListStock(ctx, &pb.ListStockRequest{})
	if len(resp.Levels) != 2 {
		t.Errorf("ListStock(all) = %d levels, want 2", len(resp.Levels))
	}
}
