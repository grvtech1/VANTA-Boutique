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
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/grvtech1/VANTA-Boutique/src/wishlistservice/genproto"
)

func ids(items []*pb.WishlistItem) []string {
	out := make([]string, len(items))
	for i, it := range items {
		out[i] = it.ProductId
	}
	return out
}

func TestStoreAddIsIdempotentAndNewestFirst(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(0, 0)
	tick := time.Unix(1000, 0)
	s.now = func() time.Time { tick = tick.Add(time.Second); return tick }

	s.Add(ctx, "u1", "A")
	s.Add(ctx, "u1", "B")
	s.Add(ctx, "u1", "A") // duplicate: no new entry, order unchanged

	items, err := s.Get(ctx, "u1")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got := strings.Join(ids(items), ","); got != "B,A" {
		t.Fatalf("items = %s, want B,A (newest first, no duplicate)", got)
	}
	if items[0].AddedAtUnix <= items[1].AddedAtUnix {
		t.Errorf("newest item should carry the later timestamp")
	}
}

func TestStoreRemove(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(0, 0)
	s.Add(ctx, "u1", "A")
	s.Add(ctx, "u1", "B")

	items, _ := s.Remove(ctx, "u1", "A")
	if got := strings.Join(ids(items), ","); got != "B" {
		t.Fatalf("after remove A: %s, want B", got)
	}
	// removing something absent is a no-op
	items, _ = s.Remove(ctx, "u1", "ZZZ")
	if got := strings.Join(ids(items), ","); got != "B" {
		t.Fatalf("remove of absent id changed list: %s", got)
	}
	// removing the last item drops the user's list entirely
	if items, _ = s.Remove(ctx, "u1", "B"); items != nil {
		t.Fatalf("expected empty list, got %v", ids(items))
	}
	if _, ok := s.byUser["u1"]; ok {
		t.Errorf("empty list should be released from the map")
	}
	// unknown user
	if items, _ = s.Remove(ctx, "nobody", "A"); items != nil {
		t.Errorf("remove for unknown user should return nil, got %v", ids(items))
	}
}

func TestStoreBoundsPerUser(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(3, 0)
	for _, id := range []string{"A", "B", "C", "D"} {
		s.Add(ctx, "u1", id)
	}
	items, _ := s.Get(ctx, "u1")
	if got := strings.Join(ids(items), ","); got != "D,C,B" {
		t.Fatalf("items = %s, want D,C,B (oldest evicted)", got)
	}
}

func TestStoreEvictsLeastRecentlyTouchedUser(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(0, 2)
	tick := time.Unix(1000, 0)
	s.now = func() time.Time { tick = tick.Add(time.Second); return tick }

	s.Add(ctx, "old", "A")
	s.Add(ctx, "mid", "A")
	s.Get(ctx, "old") // Get does not touch; "old" stays the oldest
	s.Add(ctx, "new", "A")

	if _, ok := s.byUser["old"]; ok {
		t.Errorf("least-recently-touched user should have been evicted")
	}
	if len(s.byUser) != 2 {
		t.Errorf("user count = %d, want 2", len(s.byUser))
	}
}

func TestStoreSnapshotIsACopy(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(0, 0)
	s.Add(ctx, "u1", "A")
	items, _ := s.Get(ctx, "u1")
	items[0].ProductId = "TAMPERED"
	again, _ := s.Get(ctx, "u1")
	if again[0].ProductId != "A" {
		t.Errorf("caller mutation leaked into the store")
	}
}

func TestStoreConcurrentAccess(t *testing.T) {
	ctx := context.Background()
	s := newMemStore(0, 0)
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			user := fmt.Sprintf("u%d", i%5)
			s.Add(ctx, user, fmt.Sprintf("P%d", i))
			s.Get(ctx, user)
			s.Remove(ctx, user, fmt.Sprintf("P%d", i-5))
		}(i)
	}
	wg.Wait()
}

func TestServerValidation(t *testing.T) {
	ctx := context.Background()
	cfg := defaultConfig()
	cfg.maxIDLen = 8
	srv := &server{store: newMemStore(0, 0), cfg: cfg}

	cases := []struct {
		name string
		call func() error
		want codes.Code
	}{
		{"get missing user", func() error { _, err := srv.GetWishlist(ctx, &pb.GetWishlistRequest{}); return err }, codes.InvalidArgument},
		{"add missing product", func() error { _, err := srv.AddItem(ctx, &pb.AddWishlistItemRequest{UserId: "u1"}); return err }, codes.InvalidArgument},
		{"add id too long", func() error {
			_, err := srv.AddItem(ctx, &pb.AddWishlistItemRequest{UserId: "u1", ProductId: "way-too-long-id"})
			return err
		}, codes.InvalidArgument},
		{"remove blank user", func() error {
			_, err := srv.RemoveItem(ctx, &pb.RemoveWishlistItemRequest{UserId: "   ", ProductId: "A"})
			return err
		}, codes.InvalidArgument},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.call()
			if status.Code(err) != tc.want {
				t.Fatalf("code = %v, want %v (err: %v)", status.Code(err), tc.want, err)
			}
		})
	}
}

func TestServerRoundTrip(t *testing.T) {
	ctx := context.Background()
	srv := &server{store: newMemStore(0, 0), cfg: defaultConfig()}

	wl, err := srv.AddItem(ctx, &pb.AddWishlistItemRequest{UserId: " u1 ", ProductId: "A"})
	if err != nil {
		t.Fatalf("AddItem: %v", err)
	}
	if wl.UserId != "u1" || len(wl.Items) != 1 {
		t.Fatalf("unexpected wishlist after add: %+v", wl)
	}
	wl, _ = srv.GetWishlist(ctx, &pb.GetWishlistRequest{UserId: "u1"})
	if len(wl.Items) != 1 || wl.Items[0].ProductId != "A" {
		t.Fatalf("GetWishlist = %v", ids(wl.Items))
	}
	wl, _ = srv.RemoveItem(ctx, &pb.RemoveWishlistItemRequest{UserId: "u1", ProductId: "A"})
	if len(wl.Items) != 0 {
		t.Fatalf("expected empty after remove, got %v", ids(wl.Items))
	}
}
