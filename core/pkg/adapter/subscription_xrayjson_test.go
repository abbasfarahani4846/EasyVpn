package adapter

import (
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"easyvpn/core/pkg/config"
	"easyvpn/core/pkg/protocol"
)

// These cases reproduce the user's real subscription (Xray-JSON format as
// served to v2rayN-style clients), with addresses/ids replaced: the node is
// imported through config.Parser exactly as the app does, then must carry
// traffic against an Xray server configured like the provider's.

func importXrayJSON(t *testing.T, outbound map[string]any) *protocol.ProxyNode {
	t.Helper()
	sub := []any{map[string]any{
		"remarks":   "sample",
		"outbounds": []any{outbound, map[string]any{"protocol": "freedom", "tag": "DIRECT"}},
	}}
	b, _ := json.Marshal(sub)
	nodes, err := config.NewParser().ParseContent(string(b))
	if err != nil || len(nodes) != 1 {
		t.Fatalf("import: %v (%d nodes)", err, len(nodes))
	}
	return nodes[0]
}

func runThroughNode(t *testing.T, node *protocol.ProxyNode) {
	t.Helper()
	for _, bypass := range []bool{false, true} {
		runThroughNodeOpt(t, node, bypass)
	}
}

// bypass=true is the TUN-mode wiring: the sidecar dials its server through
// sing-box's loopback bypass inbound -> interface-bound direct outbound.
func runThroughNodeOpt(t *testing.T, node *protocol.ProxyNode, bypass bool) {
	t.Helper()
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()
	runNode := node
	bp := 0
	if bypass {
		bp = freePort(t)
	}
	if NeedsXray(node) {
		sc, err := StartXraySidecarWith(node, SidecarOptions{BypassPort: bp})
		if err != nil {
			t.Fatal(err)
		}
		defer sc.Close()
		runNode = sc.Node()
	}
	local := freePort(t)
	a := NewSingBoxAdapter()
	if err := a.Start(context.Background(), &StartRequest{Node: runNode, Routing: routerGlobal(), Mode: ModeProxyOnly, LocalPort: local, CacheDir: t.TempDir(), XrayBypassPort: bp}); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer a.Stop(context.Background())
	u, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", local))
	cl := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(u)}}
	var last error
	for i := 0; i < 8; i++ {
		resp, err := cl.Get(echoAddr + "/generate_204")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusNoContent {
				return
			}
			err = fmt.Errorf("status %d", resp.StatusCode)
		}
		last = err
		time.Sleep(300 * time.Millisecond)
	}
	t.Fatalf("no traffic through imported node (bypass=%v): %v", bypass, last)
}

func TestSubscriptionXrayJSON_XHTTPStreamUpPaddingObfs(t *testing.T) {
	cert, key := selfSigned(t)
	xhttp := map[string]any{
		"mode": "stream-up", "path": "/", "host": "myket.ir",
		"extra": map[string]any{"xPaddingBytes": "100-1000", "xPaddingObfsMode": true},
	}
	port := freePort(t)
	stop := startXrayServer(t, map[string]any{
		"network": "xhttp", "security": "tls", "xhttpSettings": xhttp,
		"tlsSettings": map[string]any{"certificates": []any{map[string]any{"certificateFile": cert, "keyFile": key}}},
	}, port)
	defer stop()
	time.Sleep(300 * time.Millisecond)

	node := importXrayJSON(t, map[string]any{
		"protocol": "vless", "tag": "proxy",
		"settings": map[string]any{"vnext": []any{map[string]any{
			"address": "127.0.0.1", "port": port,
			"users": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811", "encryption": "none"}},
		}}},
		"streamSettings": map[string]any{
			"network": "xhttp", "security": "tls",
			"tlsSettings":   map[string]any{"serverName": "localhost", "allowInsecure": true},
			"xhttpSettings": xhttp,
		},
	})
	runThroughNode(t, node)
}

func TestSubscriptionXrayJSON_MLKEMTCPHTTPHeader(t *testing.T) {
	k, _ := ecdh.X25519().GenerateKey(rand.Reader)
	srv := base64.RawURLEncoding.EncodeToString(k.Bytes())
	cli := base64.RawURLEncoding.EncodeToString(k.PublicKey().Bytes())
	header := map[string]any{"type": "http",
		"request": map[string]any{"version": "1.1", "method": "GET", "path": []string{"/"},
			"headers": map[string]any{"Host": []string{"testspeed-foreign.example.ir"}, "Connection": []string{"keep-alive"}, "Pragma": "no-cache"}},
		"response": map[string]any{"version": "1.1", "status": "200", "reason": "OK",
			"headers": map[string]any{"Content-Type": []string{"application/octet-stream"}, "Connection": []string{"keep-alive"}}},
	}
	port := freePort(t)
	stop := startXrayServer(t, map[string]any{"network": "tcp", "tcpSettings": map[string]any{"header": header}}, port, "mlkem768x25519plus.native.600s."+srv)
	defer stop()
	time.Sleep(300 * time.Millisecond)
	node := importXrayJSON(t, map[string]any{
		"protocol": "vless", "tag": "proxy",
		"settings": map[string]any{"vnext": []any{map[string]any{
			"address": "127.0.0.1", "port": port,
			"users": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811", "encryption": "mlkem768x25519plus.native.0rtt." + cli}},
		}}},
		"streamSettings": map[string]any{"network": "tcp", "tcpSettings": map[string]any{"header": header}},
	})
	if !strings.HasPrefix(node.Encryption, "mlkem") {
		t.Errorf("import lost VLESS encryption: %q", node.Encryption)
	}
	runThroughNode(t, node)
}

// Nodes saved by older builds (encryption / xhttp extra lost, raw JSON kept)
// are repaired at use time, and the real URL test works for Xray-only nodes.
func TestLegacyImportRepairedAndURLTested(t *testing.T) {
	cert, key := selfSigned(t)
	xhttp := map[string]any{"mode": "stream-up", "path": "/", "host": "myket.ir",
		"extra": map[string]any{"xPaddingBytes": "100-1000", "xPaddingObfsMode": true}}
	port := freePort(t)
	stop := startXrayServer(t, map[string]any{"network": "xhttp", "security": "tls", "xhttpSettings": xhttp,
		"tlsSettings": map[string]any{"certificates": []any{map[string]any{"certificateFile": cert, "keyFile": key}}}}, port)
	defer stop()
	time.Sleep(300 * time.Millisecond)
	node := importXrayJSON(t, map[string]any{"protocol": "vless", "tag": "proxy",
		"settings": map[string]any{"vnext": []any{map[string]any{"address": "127.0.0.1", "port": port,
			"users": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811", "encryption": "none"}}}}},
		"streamSettings": map[string]any{"network": "xhttp", "security": "tls",
			"tlsSettings": map[string]any{"serverName": "localhost", "allowInsecure": true}, "xhttpSettings": xhttp}})
	// Simulate the old, lossy import as stored in the app database.
	legacy := *node
	tr := *node.Transport
	tr.Extra = ""
	legacy.Transport = &tr
	legacy.Requires = nil

	echo, closeEcho := startEchoServer(t)
	defer closeEcho()
	res := URLTestBatch(context.Background(), []*protocol.ProxyNode{&legacy}, URLTestOptions{URL: echo + "/generate_204", Timeout: 6 * time.Second})
	if len(res) != 1 || res[0].LatencyMs <= 0 {
		t.Fatalf("real URL test of xhttp node failed: %+v", res)
	}
	if legacy.Transport.Extra == "" {
		t.Fatalf("legacy node was not repaired from its raw JSON")
	}
}

// Iranian "custom" configs commonly route the proxy through a fragment/noise
// freedom outbound (sockopt.dialerProxy). That dependency must be kept and the
// node run verbatim in Xray (other clients silently drop it).
func TestSubscriptionXrayJSON_FragmentDialerChain(t *testing.T) {
	cert, key := selfSigned(t)
	port := freePort(t)
	stop := startXrayServer(t, map[string]any{
		"network": "tcp", "security": "tls",
		"tlsSettings": map[string]any{"certificates": []any{map[string]any{"certificateFile": cert, "keyFile": key}}},
	}, port)
	defer stop()
	time.Sleep(300 * time.Millisecond)

	sub := []any{map[string]any{
		"remarks": "🇩🇪 custom fragment",
		"outbounds": []any{
			map[string]any{"protocol": "vless", "tag": "proxy",
				"settings": map[string]any{"vnext": []any{map[string]any{"address": "127.0.0.1", "port": port,
					"users": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811", "encryption": "none"}}}}},
				"streamSettings": map[string]any{"network": "tcp", "security": "tls",
					"tlsSettings": map[string]any{"serverName": "localhost", "allowInsecure": true},
					"sockopt":     map[string]any{"dialerProxy": "fragment", "tcpNoDelay": true}}},
			map[string]any{"protocol": "freedom", "tag": "fragment",
				"settings": map[string]any{"fragment": map[string]any{"packets": "tlshello", "length": "10-20", "interval": "1-2"}}},
			map[string]any{"protocol": "freedom", "tag": "direct"},
		},
	}}
	b, _ := json.Marshal(sub)
	nodes, err := config.NewParser().ParseContent(string(b))
	if err != nil || len(nodes) != 1 {
		t.Fatalf("import: %v %d", err, len(nodes))
	}
	n := nodes[0]
	if n.Name != "🇩🇪 custom fragment" {
		t.Errorf("name = %q", n.Name)
	}
	if !NeedsXray(n) || !strings.Contains(n.RawConfig, `"_deps"`) {
		t.Fatalf("fragment chain must be kept and run in Xray: requires=%v", n.Requires)
	}
	cfg, _, err := buildXrayConfig(n, 1080, SidecarOptions{BypassPort: 1081})
	if err != nil {
		t.Fatal(err)
	}
	// Bypass attaches at the END of the chain (the fragment freedom), not the proxy.
	if !strings.Contains(string(cfg), `"tag":"fragment"`) || strings.Count(string(cfg), `"dialerProxy":"via-box"`) != 1 ||
		!strings.Contains(string(cfg), `"dialerProxy":"fragment"`) {
		t.Fatalf("bad chain wiring: %s", cfg)
	}
	runThroughNode(t, n)
}
