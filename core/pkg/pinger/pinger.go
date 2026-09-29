// Package pinger measures node latency with a bounded goroutine worker pool.
// Two modes: raw TCP handshake RTT (fast, no TLS) and URL test through an
// optional dialer (real proxy round-trip). Results stream back in batches so
// the Dart side never receives one callback per node.
package pinger

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"

	"easyvpn/core/pkg/protocol"
)

// Mode selects the test type.
type Mode string

const (
	ModeTCP Mode = "tcp"
	ModeURL Mode = "url"
)

// Result is a single node latency measurement (LatencyMs -1 = failed).
type Result struct {
	NodeID    string `json:"node_id"`
	LatencyMs int64  `json:"latency_ms"`
	Error     string `json:"error,omitempty"`
}

// Dialer allows URL tests to be routed through a live proxy adapter.
type Dialer interface {
	DialContext(ctx context.Context, network, addr string) (net.Conn, error)
}

// Options configures a batch run.
type Options struct {
	Workers    int           // default 50, hard cap 128
	Timeout    time.Duration // per node, default 3s
	Mode       Mode
	URL        string // URL test target, default gstatic generate_204
	Dialer     Dialer // optional; enables real through-proxy tests
	BatchEvery int    // results buffered per callback batch, default 25
	OnBatch    func([]Result)
}

type Pinger struct{}

func NewPinger() *Pinger { return &Pinger{} }

// TestBatch runs concurrent latency tests and returns all results. It never
// spawns more than min(Workers, len(nodes)) goroutines and honors ctx.
func (p *Pinger) TestBatch(ctx context.Context, nodes []*protocol.ProxyNode, opts Options) []Result {
	if len(nodes) == 0 {
		return nil
	}
	if opts.Workers <= 0 {
		opts.Workers = 50
	}
	if opts.Workers > 128 {
		opts.Workers = 128
	}
	if opts.Timeout <= 0 {
		opts.Timeout = 3 * time.Second
	}
	if opts.BatchEvery <= 0 {
		opts.BatchEvery = 25
	}
	if opts.URL == "" {
		opts.URL = "http://cp.cloudflare.com/generate_204"
	}

	results := make([]Result, len(nodes))
	tasks := make(chan int)
	go func() {
		defer close(tasks)
		for i := range nodes {
			tasks <- i
		}
	}()

	var wg sync.WaitGroup
	var mu sync.Mutex
	batch := make([]Result, 0, opts.BatchEvery)

	flush := func(force bool) {
		if len(batch) == 0 {
			return
		}
		if opts.OnBatch != nil && (force || len(batch) >= opts.BatchEvery) {
			opts.OnBatch(append([]Result(nil), batch...))
		}
		batch = batch[:0]
	}

	for w := 0; w < opts.Workers && w < len(nodes); w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for idx := range tasks {
				select {
				case <-ctx.Done():
					return
				default:
				}
				res := p.testNode(ctx, nodes[idx], &opts)
				results[idx] = res
				mu.Lock()
				batch = append(batch, res)
				if len(batch) >= opts.BatchEvery {
					flush(false)
				}
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	mu.Lock()
	flush(true)
	mu.Unlock()
	return results
}

func (p *Pinger) testNode(ctx context.Context, node *protocol.ProxyNode, opts *Options) Result {
	if node == nil || node.Server == "" || node.Port <= 0 {
		return Result{NodeID: nodeID(node), LatencyMs: -1, Error: "invalid server address"}
	}
	switch opts.Mode {
	case ModeURL:
		return p.urlTest(ctx, node, opts)
	default:
		return p.tcpTest(ctx, node, opts)
	}
}

func (p *Pinger) tcpTest(ctx context.Context, node *protocol.ProxyNode, opts *Options) Result {
	addr := net.JoinHostPort(node.Server, fmt.Sprintf("%d", node.Port))
	d := net.Dialer{Timeout: opts.Timeout}
	start := time.Now()
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return Result{NodeID: node.ID, LatencyMs: -1, Error: err.Error()}
	}
	_ = conn.Close()
	ms := time.Since(start).Milliseconds()
	if ms <= 0 {
		ms = 1
	}
	return Result{NodeID: node.ID, LatencyMs: ms}
}

func (p *Pinger) urlTest(ctx context.Context, node *protocol.ProxyNode, opts *Options) Result {
	if opts.Dialer == nil {
		// No live proxy: fall back to TCP handshake to stay useful.
		return p.tcpTest(ctx, node, opts)
	}
	ctx, cancel := context.WithTimeout(ctx, opts.Timeout)
	defer cancel()

	transport := &http.Transport{
		DialContext:           opts.Dialer.DialContext,
		TLSHandshakeTimeout:   opts.Timeout,
		ResponseHeaderTimeout: opts.Timeout,
		DisableKeepAlives:     true,
	}
	client := &http.Client{
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	start := time.Now()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, opts.URL, nil)
	if err != nil {
		return Result{NodeID: node.ID, LatencyMs: -1, Error: err.Error()}
	}
	resp, err := client.Do(req)
	if err != nil {
		return Result{NodeID: node.ID, LatencyMs: -1, Error: err.Error()}
	}
	_ = resp.Body.Close()
	ms := time.Since(start).Milliseconds()
	if ms <= 0 {
		ms = 1
	}
	return Result{NodeID: node.ID, LatencyMs: ms}
}

func nodeID(n *protocol.ProxyNode) string {
	if n == nil {
		return ""
	}
	return n.ID
}
