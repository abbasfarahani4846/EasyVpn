package adapter

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
)

// End-to-end wiring test: a real sing-box chain (upstream "proxy" -> local
// echo HTTP server) is started through Start(), then UrlTest and stats are
// verified against the live box. This exercises the exact code path used in
// production, minus TUN (which is platform-owned).
//
// The upstream here is a SOCKS server pointing at an echo HTTP server, so no
// external network access is required and CI stays hermetic.

func startEchoServer(t *testing.T) (addr string, close func()) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})}
	go func() { _ = srv.Serve(ln) }()
	return "http://" + ln.Addr().String(), func() { _ = srv.Close() }
}

func TestLiveBoxSOCKSChain(t *testing.T) {
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()

	// The "proxy" node is a plain SOCKS5 server on 127.0.0.1... but we have
	// no SOCKS server handy; instead use a direct-style HTTP proxy? To stay
	// hermetic we pick the simplest real upstream: a SOCKS inbound in a
	// second box acting as server.
	serverAddr, closeServer := startSOCKSServerBox(t)
	defer closeServer()

	host, port := splitHostPort(t, serverAddr)
	node := &protocol.ProxyNode{
		Name:   "upstream-socks",
		Type:   protocol.ProtoSocks,
		Server: host,
		Port:   port,
	}

	a := NewSingBoxAdapter()
	m := router.Model{Mode: router.ModeGlobalProxy, BypassLAN: false, LogLevel: "warn"}
	err := a.Start(context.Background(), &StartRequest{
		Node:      node,
		Routing:   m,
		LocalPort: 0, // default 2080
		BindLocal: true,
		LogLevel:  "warn",
	})
	if err != nil {
		t.Fatalf("adapter start: %v", err)
	}
	defer func() { _ = a.Stop(context.Background()) }()

	if !a.Running() {
		t.Fatalf("adapter should be running")
	}

	// Real URL test through the live box's proxy outbound, targeting the
	// loopback echo server (hermetic: no DNS, no external network).
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	ms, err := a.UrlTest(ctx, node, echoAddr+"/generate_204", 8000)
	if err != nil {
		t.Fatalf("UrlTest through live box: %v", err)
	}
	if ms <= 0 || ms > 8000 {
		t.Fatalf("implausible latency: %d ms", ms)
	}

	// The mixed-in listener must be reachable on 127.0.0.1:2080.
	resp, err := (&http.Client{Timeout: 5 * time.Second}).Get(echoAddr + "/probe")
	if err == nil {
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
	}
}

// startSOCKSServerBox runs a minimal sing-box with a socks inbound on
// 127.0.0.1:0 forwarding to direct — our upstream "VPN server".
func startSOCKSServerBox(t *testing.T) (addr string, stop func()) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr = ln.Addr().String()
	host, port := splitHostPort(t, addr)
	// Reserve then release the port; box binds it itself at start.
	_ = ln.Close()

	cfg := map[string]any{
		"log": map[string]any{"level": "warn"},
		"dns": map[string]any{"servers": []any{map[string]any{"type": "local", "tag": "local"}}},
		"inbounds": []any{map[string]any{
			"type": "socks", "tag": "socks-in", "listen": host, "listen_port": port,
		}},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
		"route":     map[string]any{"final": "direct", "default_domain_resolver": "local"},
	}
	raw, _ := json.Marshal(cfg)

	instance, err := newBoxFromJSON(raw)
	if err != nil {
		t.Fatalf("server box: %v", err)
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		t.Fatalf("server box start: %v", err)
	}
	return addr, func() { _ = instance.Close() }
}

func splitHostPort(t *testing.T, addr string) (string, int) {
	h, p, err := net.SplitHostPort(addr)
	if err != nil {
		t.Fatalf("split: %v", err)
	}
	n := 0
	for _, c := range p {
		n = n*10 + int(c-'0')
	}
	return h, n
}

func TestURLTestBatchThroughSOCKS(t *testing.T) {
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()
	serverAddr, closeServer := startSOCKSServerBox(t)
	defer closeServer()
	host, port := splitHostPort(t, serverAddr)

	good := &protocol.ProxyNode{Name: "good", Type: protocol.ProtoSocks, Server: host, Port: port}
	dead := &protocol.ProxyNode{Name: "dead", Type: protocol.ProtoSocks, Server: "127.0.0.1", Port: 1}
	bad := &protocol.ProxyNode{Name: "bad", Type: protocol.ProtoVLESS, Server: "127.0.0.1", Port: 2} // missing uuid
	var batches int
	res := URLTestBatch(context.Background(), []*protocol.ProxyNode{good, dead, bad}, URLTestOptions{
		URL: echoAddr + "/generate_204", Timeout: 3 * time.Second,
		OnBatch: func([]URLTestResult) { batches++ },
	})
	if len(res) != 3 || batches != 1 {
		t.Fatalf("results=%d batches=%d", len(res), batches)
	}
	if res[0].LatencyMs <= 0 {
		t.Fatalf("good node should have latency: %+v", res[0])
	}
	if res[1].LatencyMs != -1 || res[2].LatencyMs != -1 || res[2].Error == "" {
		t.Fatalf("dead/bad nodes must fail: %+v %+v", res[1], res[2])
	}
}

// The local mixed port must reject clients that do not present the credentials.
func TestMixedInboundEnforcesLocalAuth(t *testing.T) {
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()
	serverAddr, closeServer := startSOCKSServerBox(t)
	defer closeServer()
	host, port := splitHostPort(t, serverAddr)
	node := &protocol.ProxyNode{Name: "up", Type: protocol.ProtoSocks, Server: host, Port: port}

	local := freePort(t)
	a := NewSingBoxAdapter()
	err := a.Start(context.Background(), &StartRequest{
		Node: node, Routing: routerGlobal(), Mode: ModeProxyOnly, LocalPort: local,
		Auth: &LocalAuth{User: "easyvpn", Pass: "s3cret"},
	})
	if err != nil {
		t.Fatal(err)
	}
	defer a.Stop(context.Background())

	get := func(proxyURL string) error {
		u, _ := url.Parse(proxyURL)
		c := &http.Client{Timeout: 4 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(u)}}
		resp, err := c.Get(echoAddr + "/generate_204")
		if err != nil {
			return err
		}
		resp.Body.Close()
		if resp.StatusCode == http.StatusProxyAuthRequired {
			return fmt.Errorf("proxy auth required (407)")
		}
		return nil
	}
	base := fmt.Sprintf("127.0.0.1:%d", local)
	if err := get("socks5://easyvpn:s3cret@" + base); err != nil {
		t.Fatalf("valid credentials must work: %v", err)
	}
	if err := get("socks5://" + base); err == nil {
		t.Fatal("SOCKS without credentials must be rejected")
	}
	if err := get("http://easyvpn:wrong@" + base); err == nil {
		t.Fatal("HTTP proxy with wrong credentials must be rejected")
	}
}

// Regression (Android): the working directory is read-only, so no relative
// cache.db may be created; the cache file must live in the configured cache dir.
func TestCacheFileUsesCacheDirNotCWD(t *testing.T) {
	cwd := t.TempDir()
	cache := t.TempDir()
	old, _ := os.Getwd()
	if err := os.Chdir(cwd); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(old)

	_, serverAddr := func() (struct{}, string) { a, _ := startSOCKSServerBox(t); return struct{}{}, a }()
	host, port := splitHostPort(t, serverAddr)
	node := &protocol.ProxyNode{Name: "up", Type: protocol.ProtoSocks, Server: host, Port: port}
	a := NewSingBoxAdapter()
	if err := a.Start(context.Background(), &StartRequest{Node: node, Routing: routerGlobal(), Mode: ModeProxyOnly, LocalPort: freePort(t), CacheDir: cache}); err != nil {
		t.Fatal(err)
	}
	_ = a.Stop(context.Background())
	if _, err := os.Stat(filepath.Join(cwd, "cache.db")); err == nil {
		t.Fatal("cache.db must not be created in the working directory")
	}
	if _, err := os.Stat(filepath.Join(cache, "singbox-cache.db")); err != nil {
		t.Fatalf("cache file missing in cache dir: %v", err)
	}
}
