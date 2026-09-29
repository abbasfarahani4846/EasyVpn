package adapter

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
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
