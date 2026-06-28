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
	"os"
	"testing"
)

// TestPgStore runs against a real PostgreSQL instance. It is skipped unless
// TEST_DATABASE_URL is set, so local `go test` stays dependency-free while CI
// can point it at a Postgres service container.
func TestPgStore(t *testing.T) {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping PostgreSQL integration test")
	}
	ctx := context.Background()
	s, err := newPgStore(ctx, url, 500)
	if err != nil {
		t.Fatalf("newPgStore: %v", err)
	}
	defer s.Close()

	if err := s.Ping(ctx); err != nil {
		t.Fatalf("Ping: %v", err)
	}

	// Use a unique product id so repeated runs don't interfere.
	pid := "TEST_" + t.Name()
	if _, err := s.Add(ctx, pid, "Tester", 5, "great"); err != nil {
		t.Fatalf("Add: %v", err)
	}
	if _, err := s.Add(ctx, pid, "", 3, "ok"); err != nil {
		t.Fatalf("Add (anon): %v", err)
	}

	reviews, avg, err := s.List(ctx, pid)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(reviews) < 2 {
		t.Fatalf("expected at least 2 reviews, got %d", len(reviews))
	}
	if avg <= 0 {
		t.Errorf("expected positive average, got %v", avg)
	}
	if reviews[0].Author == "" {
		t.Error("author should default to a non-empty value")
	}
}
