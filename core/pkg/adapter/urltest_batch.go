package adapter

import (
	"context"
	"fmt"
	"sync"
	"time"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/common/urltest"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
)

// URLTestResult is the outcome for one node (LatencyMs -1 = failed).
type URLTestResult struct {
	NodeID    string `json:"node_id"`
	LatencyMs int64  `json:"latency_ms"`
	Error     string `json:"error,omitempty"`
}

// URLTestOptions tunes URLTestBatch.
type URLTestOptions struct {
	URL       string
	Timeout   time.Duration // per node (default 5 s)
	DNS       string        // resolver for server names ("udp://ip"); empty = system
	Workers   int           // concurrent probes per chunk (default 20, cap 128)
	ChunkSize int           // nodes compiled into one throw-away box (default 100)
	OnBatch   func([]URLTestResult)
}

// URLTestBatch measures real through-proxy latency for many nodes. Nodes are
// compiled in chunks into an inbound-less throw-away box (no sockets opened,
// nothing routed), probed with a bounded worker pool, and closed again, so
// memory stays flat even for 5,000 nodes and the running tunnel is untouched.
func URLTestBatch(ctx context.Context, nodes []*protocol.ProxyNode, o URLTestOptions) []URLTestResult {
	if o.Timeout <= 0 {
		o.Timeout = 5 * time.Second
	}
	if o.Workers <= 0 {
		// Fewer parallel probes than before: 50 at once saturate a phone's radio
		// and inflate every latency.
		o.Workers = 20
	}
	if o.Workers > 128 {
		o.Workers = 128
	}
	if o.ChunkSize <= 0 {
		o.ChunkSize = 100
	}
	results := make([]URLTestResult, 0, len(nodes))
	for start := 0; start < len(nodes); start += o.ChunkSize {
		if ctx.Err() != nil {
			break
		}
		end := start + o.ChunkSize
		if end > len(nodes) {
			end = len(nodes)
		}
		chunk := testChunk(ctx, nodes[start:end], o)
		results = append(results, chunk...)
		if o.OnBatch != nil {
			o.OnBatch(chunk)
		}
	}
	return results
}

func testChunk(ctx context.Context, nodes []*protocol.ProxyNode, o URLTestOptions) []URLTestResult {
	res := make([]URLTestResult, len(nodes))
	var opts option.Options
	tags := make([]string, len(nodes))
	var xrayIdx []int
	for i, n := range nodes {
		n.EnsureID()
		NormalizeNode(n)
		res[i] = URLTestResult{NodeID: n.ID, LatencyMs: -1}
		if NeedsXray(n) {
			xrayIdx = append(xrayIdx, i)
			continue
		}
		tag := fmt.Sprintf("t%d", i)
		built, err := buildNode(n, tag)
		if err != nil {
			res[i].Error = err.Error()
			continue
		}
		tags[i] = tag
		if built.Outbound != nil {
			opts.Outbounds = append(opts.Outbounds, *built.Outbound)
		} else {
			opts.Endpoints = append(opts.Endpoints, *built.Endpoint)
		}
	}
	if len(xrayIdx) > 0 {
		defer xrayURLTestMany(ctx, nodes, xrayIdx, res, o)
	}
	if len(opts.Outbounds)+len(opts.Endpoints) == 0 {
		return res
	}
	opts.Log = &option.LogOptions{Disabled: true}
	opts.DNS = defaultTestDNS(o.DNS)
	opts.Route = &option.RouteOptions{DefaultDomainResolver: &option.DomainResolveOptions{Server: "dns-local"}}

	bctx := include.Context(ctx)
	b, err := box.New(box.Options{Context: bctx, Options: opts})
	if err != nil {
		for i := range res {
			if res[i].Error == "" {
				res[i].Error = err.Error()
			}
		}
		return res
	}
	defer b.Close()
	if err := b.Start(); err != nil {
		for i := range res {
			if res[i].Error == "" {
				res[i].Error = err.Error()
			}
		}
		return res
	}

	sem := make(chan struct{}, o.Workers)
	var wg sync.WaitGroup
	for i := range nodes {
		if tags[i] == "" {
			continue
		}
		out, ok := b.Outbound().Outbound(tags[i])
		if !ok {
			res[i].Error = "outbound not registered"
			continue
		}
		sem <- struct{}{}
		wg.Add(1)
		go func(i int) {
			defer func() { <-sem; wg.Done() }()
			pctx, cancel := context.WithTimeout(ctx, o.Timeout)
			defer cancel()
			ms, err := urltest.URLTest(pctx, o.URL, out)
			if err != nil {
				res[i].Error = err.Error()
				return
			}
			if ms == 0 {
				ms = 1
			}
			res[i].LatencyMs, res[i].Error = int64(ms), ""
		}(i)
	}
	wg.Wait()
	return res
}

func defaultTestDNS(addr string) *option.DNSOptions {
	d := &option.DNSOptions{}
	d.Servers = []option.DNSServerOptions{router.ParseDNSServer("dns-local", addr, "")}
	return d
}
