package adapter

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"

	"easyvpn/core/pkg/protocol"
)

// xrayURLTest measures real latency for a node only Xray-core can run: a
// short-lived sidecar is started for it and the probe goes through its SOCKS
// inbound, so XHTTP / ML-KEM / TCP-header nodes get a real test instead of an
// "unsupported" error (or a misleading TCP-only ping).
func xrayURLTest(ctx context.Context, n *protocol.ProxyNode, target string, timeout time.Duration) (int64, error) {
	sc, err := StartXraySidecar(n)
	if err != nil {
		return -1, err
	}
	defer sc.Close()
	pu, _ := url.Parse(fmt.Sprintf("socks5h://127.0.0.1:%d", sc.port))
	tr := &http.Transport{Proxy: http.ProxyURL(pu), DisableKeepAlives: true}
	defer tr.CloseIdleConnections()
	cl := &http.Client{Transport: tr, Timeout: timeout}
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, target, nil)
	if err != nil {
		return -1, err
	}
	start := time.Now()
	resp, err := cl.Do(req)
	if err != nil {
		return -1, err
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode >= 500 {
		return -1, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	ms := time.Since(start).Milliseconds()
	if ms == 0 {
		ms = 1
	}
	return ms, nil
}

// xrayURLTestMany runs xrayURLTest for the given indexes with bounded
// parallelism (each probe holds a whole Xray instance).
func xrayURLTestMany(ctx context.Context, nodes []*protocol.ProxyNode, idx []int, res []URLTestResult, o URLTestOptions) {
	workers := 8
	if o.Workers < workers {
		workers = o.Workers
	}
	sem := make(chan struct{}, workers)
	var wg sync.WaitGroup
	for _, i := range idx {
		sem <- struct{}{}
		wg.Add(1)
		go func(i int) {
			defer func() { <-sem; wg.Done() }()
			pctx, cancel := context.WithTimeout(ctx, o.Timeout)
			defer cancel()
			ms, err := xrayURLTest(pctx, nodes[i], o.URL, o.Timeout)
			if err != nil {
				res[i].Error = err.Error()
				return
			}
			res[i].LatencyMs, res[i].Error = ms, ""
		}(i)
	}
	wg.Wait()
}
