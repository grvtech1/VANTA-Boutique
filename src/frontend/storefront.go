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

// Wishlist + inventory glue for the storefront: the JSON endpoints catalog.js
// talks to, and the small view-model helpers the templates render.

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/gorilla/mux"
	"github.com/sirupsen/logrus"

	pb "github.com/grvtech1/VANTA-Boutique/src/frontend/genproto"
)

// stockView is what templates see for a product's stock. Stock is one of
// "in", "low", "out" (also used as data-stock=…); Label is the chip text.
type stockView struct {
	Stock string
	Qty   int32
	Label string
}

func stockViewOf(level *pb.StockLevel) stockView {
	if level == nil {
		return stockView{}
	}
	switch level.GetStatus() {
	case pb.StockStatus_OUT_OF_STOCK:
		return stockView{Stock: "out", Qty: 0, Label: "Sold out"}
	case pb.StockStatus_LOW_STOCK:
		q := level.GetQuantity()
		label := "Only 1 left"
		if q != 1 {
			label = "Only " + itoa(q) + " left"
		}
		return stockView{Stock: "low", Qty: q, Label: label}
	default:
		return stockView{Stock: "in", Qty: level.GetQuantity(), Label: "In stock"}
	}
}

func itoa(n int32) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [12]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

// stockFor fetches stock for the given products as a map. Inventory is a
// nice-to-have: any failure returns an empty map and the page renders without
// stock chips rather than failing.
func (fe *frontendServer) stockFor(ctx context.Context, log logrus.FieldLogger, ids []string) map[string]stockView {
	out := map[string]stockView{}
	if fe.inventorySvcConn == nil || len(ids) == 0 {
		return out
	}
	levels, err := fe.listStock(ctx, ids)
	if err != nil {
		log.WithField("error", err).Warn("failed to get stock levels")
		return out
	}
	for _, lvl := range levels {
		out[lvl.GetProductId()] = stockViewOf(lvl)
	}
	return out
}

// ratingBucket is one row of the reviews distribution (5★ … 1★).
type ratingBucket struct {
	Star  int
	Count int
	Pct   int
}

func ratingDistribution(reviews []*pb.Review) []ratingBucket {
	counts := [6]int{}
	for _, r := range reviews {
		if s := int(r.GetRating()); s >= 1 && s <= 5 {
			counts[s]++
		}
	}
	out := make([]ratingBucket, 0, 5)
	for star := 5; star >= 1; star-- {
		pct := 0
		if len(reviews) > 0 {
			pct = counts[star] * 100 / len(reviews)
		}
		out = append(out, ratingBucket{Star: star, Count: counts[star], Pct: pct})
	}
	return out
}

// initialOf returns the first letter of a name, upper-cased, for the avatar.
func initialOf(name string) string {
	for _, r := range name {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return string(unicode.ToUpper(r))
		}
	}
	if utf8.RuneCountInString(name) > 0 {
		r, _ := utf8.DecodeRuneInString(name)
		return string(r)
	}
	return "?"
}

// --- JSON endpoints used by catalog.js ------------------------------------

type wishlistJSON struct {
	Items []wishlistItemJSON `json:"items"`
	Count int                `json:"count"`
}

type wishlistItemJSON struct {
	ProductID   string `json:"product_id"`
	AddedAtUnix int64  `json:"added_at_unix"`
}

func toWishlistJSON(items []*pb.WishlistItem) wishlistJSON {
	out := wishlistJSON{Items: make([]wishlistItemJSON, 0, len(items)), Count: len(items)}
	for _, it := range items {
		out.Items = append(out.Items, wishlistItemJSON{ProductID: it.GetProductId(), AddedAtUnix: it.GetAddedAtUnix()})
	}
	return out
}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func (fe *frontendServer) wishlistUnavailable(w http.ResponseWriter) bool {
	if fe.wishlistSvcConn != nil {
		return false
	}
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "wishlist service is not configured"})
	return true
}

// GET /wishlist
func (fe *frontendServer) getWishlistHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if fe.wishlistUnavailable(w) {
		return
	}
	items, err := fe.getWishlist(r.Context(), sessionID(r))
	if err != nil {
		log.WithField("error", err).Warn("failed to get wishlist")
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "wishlist temporarily unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, toWishlistJSON(items))
}

// POST /wishlist/{id}  → save;  DELETE /wishlist/{id} → remove
func (fe *frontendServer) toggleWishlistHandler(w http.ResponseWriter, r *http.Request) {
	log := r.Context().Value(ctxKeyLog{}).(logrus.FieldLogger)
	if fe.wishlistUnavailable(w) {
		return
	}
	id := mux.Vars(r)["id"]
	if id == "" || len(id) > 64 {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "invalid product id"})
		return
	}

	var (
		items []*pb.WishlistItem
		err   error
	)
	if r.Method == http.MethodDelete {
		items, err = fe.removeWishlistItem(r.Context(), sessionID(r), id)
	} else {
		// only save products that exist in the catalog
		if _, perr := fe.getProduct(r.Context(), id); perr != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "unknown product"})
			return
		}
		items, err = fe.addWishlistItem(r.Context(), sessionID(r), id)
	}
	if err != nil {
		log.WithField("error", err).WithField("product", id).Warn("failed to update wishlist")
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "wishlist temporarily unavailable"})
		return
	}
	log.WithField("product", id).WithField("method", r.Method).Debug("wishlist updated")
	writeJSON(w, http.StatusOK, toWishlistJSON(items))
}

// --- gRPC clients ---------------------------------------------------------

func (fe *frontendServer) getWishlist(ctx context.Context, userID string) ([]*pb.WishlistItem, error) {
	ctx, cancel := context.WithTimeout(ctx, 500*time.Millisecond)
	defer cancel()
	resp, err := pb.NewWishlistServiceClient(fe.wishlistSvcConn).
		GetWishlist(ctx, &pb.GetWishlistRequest{UserId: userID})
	if err != nil {
		return nil, err
	}
	return resp.GetItems(), nil
}

func (fe *frontendServer) addWishlistItem(ctx context.Context, userID, productID string) ([]*pb.WishlistItem, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	resp, err := pb.NewWishlistServiceClient(fe.wishlistSvcConn).
		AddItem(ctx, &pb.AddWishlistItemRequest{UserId: userID, ProductId: productID})
	if err != nil {
		return nil, err
	}
	return resp.GetItems(), nil
}

func (fe *frontendServer) removeWishlistItem(ctx context.Context, userID, productID string) ([]*pb.WishlistItem, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	resp, err := pb.NewWishlistServiceClient(fe.wishlistSvcConn).
		RemoveItem(ctx, &pb.RemoveWishlistItemRequest{UserId: userID, ProductId: productID})
	if err != nil {
		return nil, err
	}
	return resp.GetItems(), nil
}

func (fe *frontendServer) listStock(ctx context.Context, ids []string) ([]*pb.StockLevel, error) {
	ctx, cancel := context.WithTimeout(ctx, 400*time.Millisecond)
	defer cancel()
	resp, err := pb.NewInventoryServiceClient(fe.inventorySvcConn).
		ListStock(ctx, &pb.ListStockRequest{ProductIds: ids})
	if err != nil {
		return nil, err
	}
	return resp.GetLevels(), nil
}
