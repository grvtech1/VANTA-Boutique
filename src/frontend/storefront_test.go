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
	"testing"

	pb "github.com/grvtech1/VANTA-Boutique/src/frontend/genproto"
)

func TestStockViewOf(t *testing.T) {
	cases := []struct {
		name  string
		level *pb.StockLevel
		want  stockView
	}{
		{"nil", nil, stockView{}},
		{"in", &pb.StockLevel{Quantity: 12, Status: pb.StockStatus_IN_STOCK}, stockView{"in", 12, "In stock"}},
		{"low one", &pb.StockLevel{Quantity: 1, Status: pb.StockStatus_LOW_STOCK}, stockView{"low", 1, "Only 1 left"}},
		{"low many", &pb.StockLevel{Quantity: 4, Status: pb.StockStatus_LOW_STOCK}, stockView{"low", 4, "Only 4 left"}},
		{"out", &pb.StockLevel{Quantity: 0, Status: pb.StockStatus_OUT_OF_STOCK}, stockView{"out", 0, "Sold out"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := stockViewOf(tc.level); got != tc.want {
				t.Errorf("stockViewOf = %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestRatingDistribution(t *testing.T) {
	reviews := []*pb.Review{{Rating: 5}, {Rating: 5}, {Rating: 4}, {Rating: 1}, {Rating: 9}}
	dist := ratingDistribution(reviews)
	if len(dist) != 5 || dist[0].Star != 5 || dist[4].Star != 1 {
		t.Fatalf("distribution rows = %+v", dist)
	}
	// 5 reviews total (the out-of-range 9 still counts toward the total but no bucket)
	if dist[0].Count != 2 || dist[0].Pct != 40 {
		t.Errorf("5★ = %+v, want count 2 pct 40", dist[0])
	}
	if dist[1].Count != 1 || dist[1].Pct != 20 {
		t.Errorf("4★ = %+v", dist[1])
	}
	if dist[4].Count != 1 {
		t.Errorf("1★ = %+v", dist[4])
	}
	empty := ratingDistribution(nil)
	for _, b := range empty {
		if b.Count != 0 || b.Pct != 0 {
			t.Errorf("empty distribution row = %+v", b)
		}
	}
}

func TestInitialOf(t *testing.T) {
	cases := map[string]string{"priya": "P", "  Daniel": "D", "": "?", "42nd": "4", "Émile": "É", "-": "-"}
	for in, want := range cases {
		if got := initialOf(in); got != want {
			t.Errorf("initialOf(%q) = %q, want %q", in, got, want)
		}
	}
}
