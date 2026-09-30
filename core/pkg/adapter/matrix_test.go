package adapter

import (
	"context"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"easyvpn/core/pkg/config"
	"easyvpn/core/pkg/export"
	"easyvpn/core/pkg/protocol"
)

// The protocol matrix: for every protocol/transport we can run a real in-process
// server (sing-box or Xray-core), build the client node, push it through the
// share-link exporter + parser (fidelity), start the real client core, and fetch
// an HTTP body from a local echo server THROUGH the tunnel. This is the closest
// we can get to "does this config type really connect" without private servers.

func selfSigned(t *testing.T) (certPath, keyPath string) {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: "localhost"},
		DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour),
		KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, _ := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	dir := t.TempDir()
	certPath, keyPath = filepath.Join(dir, "c.pem"), filepath.Join(dir, "k.pem")
	os.WriteFile(certPath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600)
	kb, _ := x509.MarshalECPrivateKey(key)
	os.WriteFile(keyPath, pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: kb}), 0o600)
	return
}

func realityKeys(t *testing.T) (priv, pub string) {
	k, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(k.Bytes()), base64.RawURLEncoding.EncodeToString(k.PublicKey().Bytes())
}

// startTLSDest runs a TLS 1.3 server used as the REALITY handshake destination.
func startTLSDest(t *testing.T) int {
	c, k := selfSigned(t)
	cert, _ := tls.LoadX509KeyPair(c, k)
	ln, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() { io.Copy(io.Discard, c); c.Close() }()
		}
	}()
	t.Cleanup(func() { ln.Close() })
	return ln.Addr().(*net.TCPAddr).Port
}

// startSingBoxServer runs a server box with one inbound and a direct outbound.
func startSingBoxServer(t *testing.T, inbound map[string]any) int {
	port := freePort(t)
	inbound["listen"], inbound["listen_port"], inbound["tag"] = "127.0.0.1", port, "in"
	cfg := map[string]any{
		"log":       map[string]any{"level": "error"},
		"dns":       map[string]any{"servers": []any{map[string]any{"type": "local", "tag": "l"}}},
		"inbounds":  []any{inbound},
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
		"route":     map[string]any{"final": "direct", "default_domain_resolver": "l"},
	}
	raw, _ := json.Marshal(cfg)
	b, err := newBoxFromJSON(raw)
	if err != nil {
		t.Fatalf("server box: %v", err)
	}
	if err := b.Start(); err != nil {
		t.Fatalf("server start: %v", err)
	}
	t.Cleanup(func() { b.Close() })
	return port
}

const testUUID = "b831381d-6324-4d53-ad4f-8cda48b30811"

type matrixCase struct {
	name string
	// build starts the server and returns the client node.
	build func(t *testing.T) *protocol.ProxyNode
}

func tlsServer(t *testing.T) map[string]any {
	c, k := selfSigned(t)
	return map[string]any{"enabled": true, "certificate_path": c, "key_path": k, "server_name": "localhost"}
}

func clientTLS() *protocol.TLSConfig {
	return &protocol.TLSConfig{Enabled: true, ServerName: "localhost", Insecure: true}
}

func matrixCases() []matrixCase {
	node := func(name string, typ protocol.ProtocolType, port int) *protocol.ProxyNode {
		return &protocol.ProxyNode{Name: name, Type: typ, Server: "127.0.0.1", Port: port}
	}
	return []matrixCase{
		{"socks", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "socks"})
			return node("socks", protocol.ProtoSocks, p)
		}},
		{"trojan-tls", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "trojan", "users": []any{map[string]any{"password": "pw"}}, "tls": tlsServer(t)})
			n := node("trojan", protocol.ProtoTrojan, p)
			n.Password, n.TLS = "pw", clientTLS()
			return n
		}},
		{"shadowsocks-aes", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "shadowsocks", "method": "aes-256-gcm", "password": "pw"})
			n := node("ss", protocol.ProtoShadowsocks, p)
			n.Security, n.Password = "aes-256-gcm", "pw"
			return n
		}},
		{"shadowsocks-2022", func(t *testing.T) *protocol.ProxyNode {
			key := base64.StdEncoding.EncodeToString([]byte("0123456789abcdef0123456789abcdef"))
			p := startSingBoxServer(t, map[string]any{"type": "shadowsocks", "method": "2022-blake3-aes-256-gcm", "password": key})
			n := node("ss2022", protocol.ProtoShadowsocks, p)
			n.Security, n.Password = "2022-blake3-aes-256-gcm", key
			return n
		}},
		{"vmess-ws", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "vmess", "users": []any{map[string]any{"uuid": testUUID}},
				"transport": map[string]any{"type": "ws", "path": "/w"}})
			n := node("vmess-ws", protocol.ProtoVMess, p)
			n.UUID, n.Security = testUUID, "auto"
			n.Transport = &protocol.TransportConfig{Type: "ws", Path: "/w", Host: "cdn.example.com"}
			return n
		}},
		{"vless-tcp", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "vless", "users": []any{map[string]any{"uuid": testUUID}}})
			n := node("vless-tcp", protocol.ProtoVLESS, p)
			n.UUID, n.Encryption = testUUID, "none"
			return n
		}},
		{"vless-ws-tls", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "vless", "users": []any{map[string]any{"uuid": testUUID}},
				"tls": tlsServer(t), "transport": map[string]any{"type": "ws", "path": "/v"}})
			n := node("vless-ws-tls", protocol.ProtoVLESS, p)
			n.UUID, n.Encryption, n.TLS = testUUID, "none", clientTLS()
			n.Transport = &protocol.TransportConfig{Type: "ws", Path: "/v"}
			return n
		}},
		{"vless-grpc-tls", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "vless", "users": []any{map[string]any{"uuid": testUUID}},
				"tls": tlsServer(t), "transport": map[string]any{"type": "grpc", "service_name": "svc"}})
			n := node("vless-grpc", protocol.ProtoVLESS, p)
			n.UUID, n.Encryption, n.TLS = testUUID, "none", clientTLS()
			n.Transport = &protocol.TransportConfig{Type: "grpc", ServiceName: "svc"}
			return n
		}},
		{"vless-reality-vision", func(t *testing.T) *protocol.ProxyNode {
			priv, pub := realityKeys(t)
			dest := startTLSDest(t)
			p := startSingBoxServer(t, map[string]any{"type": "vless", "users": []any{map[string]any{"uuid": testUUID, "flow": "xtls-rprx-vision"}},
				"tls": map[string]any{"enabled": true, "server_name": "localhost", "reality": map[string]any{
					"enabled": true, "private_key": priv, "short_id": []string{"abcd1234"},
					"handshake": map[string]any{"server": "127.0.0.1", "server_port": dest}}}})
			n := node("vless-reality", protocol.ProtoVLESS, p)
			n.UUID, n.Flow, n.Encryption = testUUID, "xtls-rprx-vision", "none"
			n.TLS = &protocol.TLSConfig{Enabled: true, ServerName: "localhost", UTLS: true, Fingerprint: "chrome",
				Reality: &protocol.Reality{Enabled: true, PublicKey: pub, ShortID: "abcd1234"}}
			return n
		}},
		{"hysteria2", func(t *testing.T) *protocol.ProxyNode {
			tl := tlsServer(t)
			tl["alpn"] = []string{"h3"}
			p := startSingBoxServer(t, map[string]any{"type": "hysteria2", "users": []any{map[string]any{"password": "pw"}}, "tls": tl})
			n := node("hy2", protocol.ProtoHysteria2, p)
			n.Password, n.TLS = "pw", clientTLS()
			return n
		}},
		{"tuic", func(t *testing.T) *protocol.ProxyNode {
			tl := tlsServer(t)
			tl["alpn"] = []string{"h3"}
			p := startSingBoxServer(t, map[string]any{"type": "tuic", "users": []any{map[string]any{"uuid": testUUID, "password": "pw"}}, "tls": tl})
			n := node("tuic", protocol.ProtoTUIC, p)
			n.UUID, n.Password, n.TLS = testUUID, "pw", clientTLS()
			n.TUIC = &protocol.TUICConfig{CongestionControl: "bbr", UDPRelayMode: "native"}
			return n
		}},
		{"anytls", func(t *testing.T) *protocol.ProxyNode {
			p := startSingBoxServer(t, map[string]any{"type": "anytls", "users": []any{map[string]any{"password": "pw"}}, "tls": tlsServer(t)})
			n := node("anytls", protocol.ProtoAnyTLS, p)
			n.Password, n.TLS = "pw", clientTLS()
			return n
		}},
		// Xray-only transports (served through the sidecar):
		{"xray-vless-tcp-http-header", func(t *testing.T) *protocol.ProxyNode {
			port := freePort(t)
			stop := startXrayServer(t, map[string]any{"network": "tcp", "tcpSettings": map[string]any{"header": map[string]any{"type": "http",
				"request": map[string]any{"path": []string{"/"}, "headers": map[string]any{"Host": []string{"cdn.example.com"}}}}}}, port)
			t.Cleanup(stop)
			time.Sleep(200 * time.Millisecond)
			n := node("tcphttp", protocol.ProtoVLESS, port)
			n.UUID, n.Encryption = testUUID, "none"
			n.Transport = &protocol.TransportConfig{Type: "tcp-http", Host: "cdn.example.com", Path: "/"}
			return n
		}},
		{"xray-vless-mlkem-tcp", func(t *testing.T) *protocol.ProxyNode {
			k, _ := ecdh.X25519().GenerateKey(rand.Reader)
			srv := base64.RawURLEncoding.EncodeToString(k.Bytes())
			cli := base64.RawURLEncoding.EncodeToString(k.PublicKey().Bytes())
			port := freePort(t)
			stop := startXrayServer(t, map[string]any{"network": "tcp"}, port, "mlkem768x25519plus.native.600s."+srv)
			t.Cleanup(stop)
			time.Sleep(200 * time.Millisecond)
			n := node("mlkem", protocol.ProtoVLESS, port)
			n.UUID, n.Encryption = testUUID, "mlkem768x25519plus.native.0rtt."+cli
			return n
		}},
		{"xray-vless-mlkem-tcp-http-header", func(t *testing.T) *protocol.ProxyNode {
			k, _ := ecdh.X25519().GenerateKey(rand.Reader)
			srv := base64.RawURLEncoding.EncodeToString(k.Bytes())
			cli := base64.RawURLEncoding.EncodeToString(k.PublicKey().Bytes())
			port := freePort(t)
			stop := startXrayServer(t, map[string]any{"network": "tcp", "tcpSettings": map[string]any{"header": map[string]any{"type": "http",
				"request": map[string]any{"path": []string{"/"}, "headers": map[string]any{"Host": []string{"testspeed.example.ir"}}}}}}, port, "mlkem768x25519plus.native.600s."+srv)
			t.Cleanup(stop)
			time.Sleep(200 * time.Millisecond)
			n := node("mlkem-http", protocol.ProtoVLESS, port)
			n.UUID, n.Encryption = testUUID, "mlkem768x25519plus.native.0rtt."+cli
			n.Transport = &protocol.TransportConfig{Type: "tcp-http", Host: "testspeed.example.ir", Path: "/"}
			return n
		}},
		{"xray-vless-xhttp", func(t *testing.T) *protocol.ProxyNode {
			port := freePort(t)
			stop := startXrayServer(t, map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{"path": "/xh", "mode": "auto"}}, port)
			t.Cleanup(stop)
			time.Sleep(200 * time.Millisecond)
			n := node("xhttp", protocol.ProtoVLESS, port)
			n.UUID, n.Encryption = testUUID, "none"
			n.Transport = &protocol.TransportConfig{Type: "xhttp", Path: "/xh", Mode: "auto"}
			return n
		}},
	}
}

func TestProtocolMatrix(t *testing.T) {
	echoAddr, closeEcho := startEchoServer(t)
	defer closeEcho()
	for _, c := range matrixCases() {
		c := c
		t.Run(c.name, func(t *testing.T) {
			node := c.build(t)
			node.EnsureID()

			// Fidelity: share link -> parse must keep the node functionally identical.
			if link, err := export.URI(node); err == nil && node.Type != protocol.ProtoSocks {
				back, err := config.NewParser().ParseURI(link)
				if err != nil {
					t.Fatalf("re-parse %q: %v", link, err)
				}
				if back.ComputeID() != node.ComputeID() {
					t.Fatalf("share-link round trip changed the node:\n link=%s", link)
				}
			}

			runNode := node
			if NeedsXray(node) {
				sc, err := StartXraySidecar(node)
				if err != nil {
					t.Fatal(err)
				}
				defer sc.Close()
				runNode = sc.Node()
			}
			local := freePort(t)
			a := NewSingBoxAdapter()
			if err := a.Start(context.Background(), &StartRequest{Node: runNode, Routing: routerGlobal(), Mode: ModeProxyOnly, LocalPort: local, CacheDir: t.TempDir()}); err != nil {
				t.Fatalf("start: %v", err)
			}
			defer a.Stop(context.Background())

			u, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", local))
			cl := &http.Client{Timeout: 8 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(u)}}
			deadline := time.Now().Add(6 * time.Second)
			var last error
			for time.Now().Before(deadline) {
				resp, err := cl.Get(echoAddr + "/generate_204")
				if err == nil {
					resp.Body.Close()
					if resp.StatusCode == http.StatusNoContent {
						time.Sleep(600 * time.Millisecond)
						if st := a.LatestStats(); st.TotalUpload+st.TotalDownload == 0 {
							t.Log("warning: no traffic counted")
						}
						return
					}
					last = fmt.Errorf("status %d", resp.StatusCode)
				} else {
					last = err
				}
				time.Sleep(300 * time.Millisecond)
			}
			t.Fatalf("no traffic through %s: %v", c.name, last)
		})
	}
}
