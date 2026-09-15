package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"

	pb "github.com/grvtech1/VANTA-Boutique/src/reviewsservice/genproto"
)

func TestMySQLInvalidDSN(t *testing.T) {
	for _, dsn := range []string{"postgres://user:secret@host/reviews", "mysql://user:secret@host/reviews", "user:secret@tcp(localhost:3306)/"} {
		_, err := newMySQLStore(context.Background(), dsn, 500)
		if err == nil {
			t.Fatal("invalid or legacy DSN accepted")
		}
		if strings.Contains(err.Error(), "secret") {
			t.Fatal("DSN password leaked in error")
		}
	}
}

func integrationStore(t *testing.T, limit int) *mysqlStore {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		if os.Getenv("REQUIRE_MYSQL_TESTS") == "1" {
			t.Fatal("TEST_DATABASE_URL is required")
		}
		t.Skip("TEST_DATABASE_URL not set; skipping MySQL integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	s, err := newMySQLStore(ctx, dsn, limit)
	if err != nil {
		t.Fatalf("newMySQLStore: %v", err)
	}
	t.Cleanup(s.Close)
	return s
}

func productID(t *testing.T, s *mysqlStore) string {
	t.Helper()
	id := "TEST_" + uuid.NewString()
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if _, err := s.pool.ExecContext(ctx, "DELETE FROM reviews WHERE product_id = ?", id); err != nil {
			t.Errorf("cleanup: %v", err)
		}
	})
	return id
}

func TestMySQLStore(t *testing.T) {
	s := integrationStore(t, 500)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	id := productID(t, s)
	if err := s.Ping(ctx); err != nil {
		t.Fatal(err)
	}
	empty, avg, err := s.List(ctx, id)
	if err != nil || len(empty) != 0 || avg != 0 {
		t.Fatalf("empty list: %v %v %v", empty, avg, err)
	}
	comment := "O'Reilly; DROP TABLE reviews; -- \U0001f31f \u0928\u092e\u0938\u094d\u0924\u0947"
	first, err := s.Add(ctx, id, "Tester", 5, comment)
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.Add(ctx, id, "", 3, "ok")
	if err != nil {
		t.Fatal(err)
	}
	// A separate pool models another replica and proves data isn't process-local.
	other := integrationStore(t, 500)
	got, avg, err := other.List(ctx, id)
	if err != nil || len(got) != 2 || avg != 4 {
		t.Fatalf("shared list: count=%d average=%v error=%v", len(got), avg, err)
	}
	byID := map[string]string{}
	for _, r := range got {
		byID[r.ReviewId] = r.Comment
		if r.ReviewId == second.ReviewId && r.Author != "Anonymous" {
			t.Errorf("unexpected anonymous author %q", r.Author)
		}
	}
	if byID[first.ReviewId] != comment {
		t.Fatal("Unicode or quoted comment did not round-trip")
	}
	for _, distinct := range []string{strings.ToLower(id), id + " "} {
		rows, _, err := s.List(ctx, distinct)
		if err != nil || len(rows) != 0 {
			t.Fatalf("product identifiers must compare exactly: %q, %v", distinct, err)
		}
	}
	if _, err := s.Add(ctx, id, "invalid", 6, "bad rating"); err == nil {
		t.Fatal("database rating constraint was not enforced")
	}
	ended, stop := context.WithCancel(ctx)
	stop()
	if _, _, err := s.List(ended, id); err == nil {
		t.Fatal("cancelled query succeeded")
	}
}

func TestMySQLLimitAndOrder(t *testing.T) {
	s := integrationStore(t, 2)
	id := productID(t, s)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	for i := 1; i <= 3; i++ {
		r, err := s.Add(ctx, id, "tester", int32(i), fmt.Sprint(i))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := s.pool.ExecContext(ctx, "UPDATE reviews SET created_at_unix = ? WHERE review_id = ?", i, r.ReviewId); err != nil {
			t.Fatal(err)
		}
	}
	rows, avg, err := s.List(ctx, id)
	if err != nil || len(rows) != 2 || avg != 2.5 || rows[0].Rating != 3 || rows[1].Rating != 2 {
		t.Fatalf("newest limited window: rows=%v average=%v error=%v", rows, avg, err)
	}
}

func TestMySQLConcurrentReplicas(t *testing.T) {
	s := integrationStore(t, 500)
	other := integrationStore(t, 500)
	id := productID(t, s)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			writer := s
			if i%2 == 0 {
				writer = other
			}
			if _, err := writer.Add(ctx, id, "writer", 4, fmt.Sprint(i)); err != nil {
				t.Errorf("concurrent write: %v", err)
			}
		}(i)
	}
	wg.Wait()
	rows, avg, err := s.List(ctx, id)
	if err != nil || len(rows) != 20 || avg != 4 {
		t.Fatalf("lost concurrent writes: count=%d average=%v error=%v", len(rows), avg, err)
	}
}

func TestMySQLRPC(t *testing.T) {
	s := integrationStore(t, 500)
	id := productID(t, s)
	listener := bufconn.Listen(1 << 20)
	rpc := grpc.NewServer()
	pb.RegisterReviewsServiceServer(rpc, &server{store: s, cfg: defaultConfig()})
	go func() { _ = rpc.Serve(listener) }()
	t.Cleanup(func() { rpc.Stop(); listener.Close() })
	conn, err := grpc.NewClient("passthrough:///reviews-test",
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return listener.Dial() }))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	client := pb.NewReviewsServiceClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	added, err := client.AddReview(ctx, &pb.AddReviewRequest{ProductId: id, Rating: 5, Comment: "persist through gRPC"})
	if err != nil {
		t.Fatal(err)
	}
	got, err := client.GetReviews(ctx, &pb.GetReviewsRequest{ProductId: id})
	if err != nil || got.GetCount() != 1 || got.GetAverageRating() != 5 || got.GetReviews()[0].ReviewId != added.GetReview().ReviewId {
		t.Fatalf("gRPC round-trip: response=%v error=%v", got, err)
	}
	_, err = client.AddReview(ctx, &pb.AddReviewRequest{ProductId: id, Rating: 0})
	if status.Code(err) != codes.InvalidArgument {
		t.Fatalf("invalid rating: %v", err)
	}
}
