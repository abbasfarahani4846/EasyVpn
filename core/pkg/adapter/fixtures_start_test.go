package adapter

import (
	"bytes"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"os"
	"testing"

	"easyvpn/core/pkg/config"

	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
)

// Every node of the (sanitized) real subscriptions must compile for the engine
// that will run it: Xray config builds and instantiates, or sing-box options
// build. A node that fails here would fail at "Connect" on the user's device.
func TestFixtureNodesCompileForTheirEngine(t *testing.T) {
	for _, f := range []string{"sub_sample.json", "sub_singbox.json", "sub_dart_decoded.txt"} {
		b, err := os.ReadFile("../../../test/fixtures/" + f)
		if err != nil {
			t.Fatal(err)
		}
		// Fixtures carry a placeholder in place of the provider's ML-KEM key.
		k, _ := ecdh.X25519().GenerateKey(rand.Reader)
		b = bytes.ReplaceAll(b, []byte("SANITIZED_KEY_0123456789ABCDEFGHIJKLMNOPQRSTUV"),
			[]byte(base64.RawURLEncoding.EncodeToString(k.PublicKey().Bytes())))
		nodes, err := config.NewParser().ParseContent(string(b))
		if err != nil || len(nodes) == 0 {
			t.Fatalf("%s: %v (%d nodes)", f, err, len(nodes))
		}
		for _, n := range nodes {
			NormalizeNode(n)
			if NeedsXray(n) {
				cfg, insecure, err := buildXrayConfig(n, 10808, SidecarOptions{BypassPort: 10900})
				if err != nil {
					t.Errorf("%s/%s: xray build: %v", f, n.Name, err)
					continue
				}
				pb, err := serial.LoadJSONConfig(bytes.NewReader(cfg))
				if err != nil {
					t.Errorf("%s/%s: xray load: %v", f, n.Name, err)
					continue
				}
				if insecure {
					if err := forceInsecureTLS(pb); err != nil {
						t.Errorf("%s/%s: %v", f, n.Name, err)
					}
				}
				inst, err := xcore.New(pb)
				if err != nil {
					t.Errorf("%s/%s: xray init: %v", f, n.Name, err)
					continue
				}
				inst.Close()
				t.Logf("%-10s xray     %s requires=%v", f, n.Name, n.Requires)
			} else {
				if _, err := buildNode(n, "x"); err != nil {
					t.Errorf("%s/%s: sing-box build: %v", f, n.Name, err)
					continue
				}
				t.Logf("%-10s sing-box %s", f, n.Name)
			}
		}
	}
}
