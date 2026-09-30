package adapter

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"sync/atomic"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"
)

// countingForwarder accepts TCP and pipes every connection to target,
// counting connections: a transparent "front" server, so we can prove the
// chain hop is actually on the path.
func countingForwarder(t *testing.T, target string) (addr string, count *atomic.Int64) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	count = &atomic.Int64{}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			count.Add(1)
			go func(c net.Conn) {
				defer c.Close()
				up, err := net.Dial("tcp", target)
				if err != nil {
					return
				}
				defer up.Close()
				go func() { _, _ = io.Copy(up, c) }()
				_, _ = io.Copy(c, up)
			}(c)
		}
	}()
	return ln.Addr().String(), count
}

// TestChainProxyInProxy: app -> hop (SOCKS, via a counting forwarder) ->
// exit (SOCKS server box) -> echo. The hop must see the traffic.
func TestChainProxyInProxy(t *testing.T) {
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()
	exitAddr, stopExit := startSOCKSServerBox(t)
	defer stopExit()
	hopSOCKS := startAnySOCKS(t, exitAddr) // hop: a SOCKS server that forwards everything to the exit
	front, count := countingForwarder(t, hopSOCKS)

	fh, fp := splitHostPort(t, front)
	eh, ep := splitHostPort(t, exitAddr)
	hop := &protocol.ProxyNode{Name: "hop", Type: protocol.ProtoSocks, Server: fh, Port: fp}
	exit := &protocol.ProxyNode{Name: "exit", Type: protocol.ProtoSocks, Server: eh, Port: ep}

	local := freePort(t)
	a := NewSingBoxAdapter()
	if err := a.Start(context.Background(), &StartRequest{
		Node: exit, Chain: []*protocol.ProxyNode{hop}, Routing: routerGlobal(),
		Mode: ModeProxyOnly, LocalPort: local, CacheDir: t.TempDir(),
	}); err != nil {
		t.Fatal(err)
	}
	defer a.Stop(context.Background())

	u, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", local))
	cl := &http.Client{Timeout: 6 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(u)}}
	resp, err := cl.Get(echoAddr + "/generate_204")
	if err != nil {
		t.Fatalf("request through chain: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if count.Load() == 0 {
		t.Fatal("chain hop was bypassed: the exit node did not dial through it")
	}
}

func TestSetDetourOnAllNodeTypes(t *testing.T) {
	nodes := []*protocol.ProxyNode{
		{Type: protocol.ProtoSocks, Server: "1.1.1.1", Port: 1},
		{Type: protocol.ProtoVLESS, Server: "1.1.1.1", Port: 1, UUID: "b831381d-6324-4d53-ad4f-8cda48b30811"},
		{Type: protocol.ProtoShadowsocks, Server: "1.1.1.1", Port: 1, Security: "aes-128-gcm", Password: "x"},
		{Type: protocol.ProtoSSH, Server: "1.1.1.1", Port: 22, UUID: "u", Password: "p"},
		{Type: protocol.ProtoWireGuard, Server: "1.1.1.1", Port: 2408, WireGuard: &protocol.WireGuardConfig{
			PrivateKey: "aGVsbG9oZWxsb2hlbGxvaGVsbG9oZWxsb2hlbGxvMDA=", PublicKey: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
			LocalAddress: []string{"172.16.0.2/32"}}},
	}
	for _, n := range nodes {
		b, err := buildNode(n, "x")
		if err != nil {
			t.Fatalf("%s: %v", n.Type, err)
		}
		var ok bool
		if b.Outbound != nil {
			ok = setDetour(b.Outbound.Options, "chain-0")
		} else {
			ok = setDetour(b.Endpoint.Options, "chain-0")
		}
		if !ok {
			t.Errorf("%s: could not set detour", n.Type)
		}
	}
}
