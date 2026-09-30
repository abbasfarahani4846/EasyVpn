package adapter

import (
	"context"
	"os"
	"strings"
	"testing"

	"easyvpn/core/pkg/config"
)

// A provider profile (Windscribe style): TLS mode with tls-auth +
// key-direction, a legacy `cipher` line, ncp-ciphers and auth-user-pass.
// sing-box rejects key_direction/cipher outside static-key mode, so the
// builder must move them; missing credentials yield a stable error code.
func TestOpenVPNProviderProfileBuilds(t *testing.T) {
	b, err := os.ReadFile("../../../test/fixtures/windscribe_like.ovpn")
	if err != nil {
		t.Fatal(err)
	}
	nodes, err := config.NewParser().ParseContent(string(b))
	if err != nil || len(nodes) != 1 {
		t.Fatalf("parse: %v %d", err, len(nodes))
	}
	n := nodes[0]
	if !n.OpenVPN.AuthUserPass || n.OpenVPN.ControlWrapType != "tls_auth" || n.OpenVPN.ControlWrapDir != "client" {
		t.Fatalf("parse: %+v", n.OpenVPN)
	}
	start := func() error {
		a := NewSingBoxAdapter()
		err := a.Start(context.Background(), &StartRequest{Node: n, Routing: routerGlobal(), Mode: ModeProxyOnly, LocalPort: freePort(t), CacheDir: t.TempDir()})
		if err == nil {
			_ = a.Stop(context.Background())
		}
		return err
	}
	if err := start(); err == nil || !strings.Contains(err.Error(), "openvpn_needs_credentials") {
		t.Fatalf("want openvpn_needs_credentials, got %v", err)
	}
	n.OpenVPN.Username, n.OpenVPN.Password = "user", "pass"
	if err := start(); err != nil {
		t.Fatalf("provider profile must build: %v", err)
	}
}
