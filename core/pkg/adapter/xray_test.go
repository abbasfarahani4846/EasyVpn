package adapter

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"

	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
)

func startXrayServer(t *testing.T, stream map[string]any, port int, decryption ...string) func() {
	dec := "none"
	if len(decryption) > 0 {
		dec = decryption[0]
	}
	cfg := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{map[string]any{
			"listen": "127.0.0.1", "port": port, "protocol": "vless",
			"settings":       map[string]any{"clients": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811"}}, "decryption": dec},
			"streamSettings": stream,
		}},
		"outbounds": []any{map[string]any{"protocol": "freedom"}},
	}
	b, _ := json.Marshal(cfg)
	pb, err := serial.LoadJSONConfig(bytes.NewReader(b))
	if err != nil {
		t.Fatalf("server config: %v", err)
	}
	inst, err := xcore.New(pb)
	if err != nil {
		t.Fatal(err)
	}
	if err := inst.Start(); err != nil {
		t.Fatal(err)
	}
	return func() { _ = inst.Close() }
}

// End to end: a real Xray server + our sidecar for the transports that
// sing-box mainline cannot run (TCP HTTP-header camouflage and XHTTP).
func TestXraySidecarTransports(t *testing.T) {
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()

	cases := []struct {
		name      string
		transport *protocol.TransportConfig
		stream    map[string]any
	}{
		{
			"tcp-http", &protocol.TransportConfig{Type: "tcp-http", Host: "cdn.example.com", Path: "/"},
			map[string]any{"network": "tcp", "tcpSettings": map[string]any{"header": map[string]any{"type": "http",
				"request": map[string]any{"path": []string{"/"}, "headers": map[string]any{"Host": []string{"cdn.example.com"}}}}}},
		},
		{
			"xhttp", &protocol.TransportConfig{Type: "xhttp", Path: "/xh", Mode: "auto"},
			map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{"path": "/xh", "mode": "auto"}},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			ln, _ := net.Listen("tcp", "127.0.0.1:0")
			port := ln.Addr().(*net.TCPAddr).Port
			ln.Close()
			stop := startXrayServer(t, c.stream, port)
			defer stop()
			time.Sleep(300 * time.Millisecond)

			node := &protocol.ProxyNode{
				Name: c.name, Type: protocol.ProtoVLESS, Server: "127.0.0.1", Port: port,
				UUID: "b831381d-6324-4d53-ad4f-8cda48b30811", Encryption: "none", Transport: c.transport,
			}
			node.EnsureID()
			if !NeedsXray(node) {
				t.Fatalf("%s must be routed to xray, requires=%v", c.name, node.Requires)
			}
			sc, err := StartXraySidecar(node)
			if err != nil {
				t.Fatal(err)
			}
			defer sc.Close()

			// Dial the echo server through the sidecar's SOCKS inbound using sing-box as the client.
			a := NewSingBoxAdapter()
			err = a.Start(context.Background(), &StartRequest{
				Node: sc.Node(), Routing: routerGlobal(), Mode: ModeProxyOnly, LocalPort: freePort(t),
			})
			if err != nil {
				t.Fatal(err)
			}
			defer a.Stop(context.Background())
			ms, err := a.UrlTest(context.Background(), sc.Node(), echoAddr+"/generate_204", 5000)
			if err != nil || ms <= 0 {
				t.Fatalf("traffic through xray %s failed: ms=%d err=%v", c.name, ms, err)
			}
		})
	}
}

func freePort(t *testing.T) int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}
