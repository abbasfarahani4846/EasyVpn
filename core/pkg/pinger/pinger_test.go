package pinger

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"
)

func TestTCPBatchHappyPath(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			_ = c.Close()
		}
	}()
	port := ln.Addr().(*net.TCPAddr).Port

	nodes := []*protocol.ProxyNode{
		{ID: "a", Server: "127.0.0.1", Port: port},
		{ID: "b", Server: "127.0.0.1", Port: port},
		{ID: "c", Server: "127.0.0.1", Port: 1}, // closed port -> fail
	}
	p := NewPinger()
	var batches int64
	results := p.TestBatch(context.Background(), nodes, Options{
		Workers: 8,
		Timeout: 2 * time.Second,
		Mode:    ModeTCP,
		OnBatch: func(rs []Result) { atomic.AddInt64(&batches, 1) },
	})
	if len(results) != 3 {
		t.Fatalf("expected 3 results, got %d", len(results))
	}
	if results[0].LatencyMs < 0 || results[1].LatencyMs < 0 {
		t.Fatalf("expected success for open ports: %+v", results)
	}
	if results[2].LatencyMs >= 0 {
		t.Fatalf("expected failure for closed port: %+v", results[2])
	}
	if atomic.LoadInt64(&batches) == 0 {
		t.Fatalf("expected at least one progress batch callback")
	}
}

func TestURLTestThroughDialer(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	p := NewPinger()
	node := &protocol.ProxyNode{ID: "x", Server: "127.0.0.1", Port: 80}
	// "Dialer" that connects directly to the test server regardless of node.
	res := p.testNode(context.Background(), node, &Options{
		Mode:    ModeURL,
		URL:     srv.URL,
		Timeout: 3 * time.Second,
		Dialer:  directDialer{},
	})
	if res.LatencyMs < 0 {
		t.Fatalf("url test through dialer failed: %+v", res)
	}
}

func TestContextCancellationStopsEarly(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	nodes := []*protocol.ProxyNode{{ID: "a", Server: "10.255.255.1", Port: 80}}
	p := NewPinger()
	results := p.TestBatch(ctx, nodes, Options{Workers: 1, Timeout: 5 * time.Second, Mode: ModeTCP})
	// With a canceled context results may be zero-valued; must not hang.
	_ = results
}

type directDialer struct{}

func (directDialer) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	var d net.Dialer
	return d.DialContext(ctx, "tcp", hostOnly(addr))
}

// hostOnly strips the port so the fake dialer reaches the httptest server.
func hostOnly(addr string) string {
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			host := addr[:i]
			if p := portOf(addr[i+1:]); p != 0 {
				return net.JoinHostPort(host, strconv.Itoa(p))
			}
		}
	}
	return addr
}

func portOf(s string) int {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
	}
	return n
}
