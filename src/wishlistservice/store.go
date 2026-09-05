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
	"sync"
	"time"

	pb "github.com/grvtech1/VANTA-Boutique/src/wishlistservice/genproto"
)

// Store is the persistence seam. The in-memory implementation below is the
// zero-dependency default; a shared store (Redis, Postgres) can sit behind the
// same interface when the service needs to run more than one replica.
type Store interface {
	Get(ctx context.Context, userID string) ([]*pb.WishlistItem, error)
	Add(ctx context.Context, userID, productID string) ([]*pb.WishlistItem, error)
	Remove(ctx context.Context, userID, productID string) ([]*pb.WishlistItem, error)
}

type userList struct {
	items       []*pb.WishlistItem // newest first
	lastTouched time.Time
}

// memStore is a concurrency-safe, bounded, in-memory Store.
//
// Bounds: at most maxPerUser items per user (oldest evicted) and at most
// maxUsers lists in total (least-recently-touched evicted). State is
// per-process and NOT shared across replicas — run a single replica with it.
type memStore struct {
	mu         sync.RWMutex
	byUser     map[string]*userList
	maxPerUser int
	maxUsers   int
	now        func() time.Time
}

func newMemStore(maxPerUser, maxUsers int) *memStore {
	if maxPerUser <= 0 {
		maxPerUser = 200
	}
	if maxUsers <= 0 {
		maxUsers = 20000
	}
	return &memStore{
		byUser:     map[string]*userList{},
		maxPerUser: maxPerUser,
		maxUsers:   maxUsers,
		now:        time.Now,
	}
}

// Get returns a defensive copy of the user's list, newest first.
func (s *memStore) Get(_ context.Context, userID string) ([]*pb.WishlistItem, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.snapshot(userID), nil
}

// Add saves a product for the user. Adding a product that is already saved is a
// no-op (idempotent), so a double-tap or a retried request never duplicates.
func (s *memStore) Add(_ context.Context, userID, productID string) ([]*pb.WishlistItem, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	ul := s.byUser[userID]
	if ul == nil {
		s.evictIfFull()
		ul = &userList{}
		s.byUser[userID] = ul
	}
	ul.lastTouched = s.now()

	for _, it := range ul.items {
		if it.ProductId == productID {
			return s.snapshot(userID), nil
		}
	}
	item := &pb.WishlistItem{ProductId: productID, AddedAtUnix: s.now().Unix()}
	ul.items = append([]*pb.WishlistItem{item}, ul.items...)
	if len(ul.items) > s.maxPerUser {
		ul.items = ul.items[:s.maxPerUser]
	}
	return s.snapshot(userID), nil
}

// Remove drops a product from the user's list. Removing something that is not
// there is a no-op, so the call is safe to retry.
func (s *memStore) Remove(_ context.Context, userID, productID string) ([]*pb.WishlistItem, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	ul := s.byUser[userID]
	if ul == nil {
		return nil, nil
	}
	ul.lastTouched = s.now()
	kept := ul.items[:0]
	for _, it := range ul.items {
		if it.ProductId != productID {
			kept = append(kept, it)
		}
	}
	ul.items = kept
	if len(ul.items) == 0 {
		delete(s.byUser, userID)
		return nil, nil
	}
	return s.snapshot(userID), nil
}

// snapshot copies a user's items so callers never hold references into the
// map. Caller must hold at least a read lock.
func (s *memStore) snapshot(userID string) []*pb.WishlistItem {
	ul := s.byUser[userID]
	if ul == nil || len(ul.items) == 0 {
		return nil
	}
	out := make([]*pb.WishlistItem, len(ul.items))
	for i, it := range ul.items {
		out[i] = &pb.WishlistItem{ProductId: it.ProductId, AddedAtUnix: it.AddedAtUnix}
	}
	return out
}

// evictIfFull drops the least-recently-touched list when the user cap is hit.
// Caller must hold the write lock. Linear scan is fine at these sizes.
func (s *memStore) evictIfFull() {
	if len(s.byUser) < s.maxUsers {
		return
	}
	var (
		victim string
		oldest time.Time
		first  = true
	)
	for id, ul := range s.byUser {
		if first || ul.lastTouched.Before(oldest) {
			victim, oldest, first = id, ul.lastTouched, false
		}
	}
	delete(s.byUser, victim)
}
