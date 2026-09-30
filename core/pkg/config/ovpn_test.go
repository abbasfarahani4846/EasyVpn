package config

import (
	"encoding/base64"
	"os"
	"strings"
	"testing"
)

const sampleOVPN = `client
dev tun
proto udp
remote vpn.example.com 1194
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
keepalive 10 60
redirect-gateway def1
comp-lzo
route 10.8.0.0 255.255.255.0
<ca>
-----BEGIN CERTIFICATE-----
MIIB
-----END CERTIFICATE-----
</ca>
<tls-crypt>
-----BEGIN OpenVPN Static key V1-----
abcd
-----END OpenVPN Static key V1-----
</tls-crypt>
`

func TestParseOVPN(t *testing.T) {
	n, err := ParseOVPN(sampleOVPN, "office")
	if err != nil {
		t.Fatal(err)
	}
	c := n.OpenVPN
	if n.Server != "vpn.example.com" || n.Port != 1194 || c.Network != "udp" {
		t.Fatalf("bad remote: %+v", n)
	}
	if c.ControlWrapType != "tls_crypt" || !strings.Contains(c.CA, "BEGIN CERTIFICATE") {
		t.Fatalf("bad crypto: %+v", c)
	}
	if c.Cipher != "AES-256-GCM" || c.Auth != "SHA256" || !c.RedirectGateway || c.CompressionLZO != "adaptive" {
		t.Fatalf("bad fields: %+v", c)
	}
	if len(c.Routes) != 1 || c.Routes[0] != "10.8.0.0/24" || c.PingRestartSec != 60 {
		t.Fatalf("bad routes/keepalive: %+v", c)
	}
	// the generic parser must also detect it
	res, err := NewParser().ParseWithWarnings(sampleOVPN)
	if err != nil || len(res.Nodes) != 1 || res.Nodes[0].Type != "openvpn" {
		t.Fatalf("auto-detect failed: %v", err)
	}
}

func TestParseWGQuickWithAWG(t *testing.T) {
	conf := "[Interface]\nPrivateKey = priv\nAddress = 10.0.0.2/32, fd00::2/128\nMTU = 1280\nJc = 4\nS1 = 15\n\n[Peer]\nPublicKey = pub\nEndpoint = wg.example.com:51820\n"
	n, err := ParseWGQuick(conf, "")
	if err != nil {
		t.Fatal(err)
	}
	if n.Server != "wg.example.com" || n.Port != 51820 || len(n.WireGuard.LocalAddress) != 2 {
		t.Fatalf("%+v", n)
	}
	if len(n.Requires) != 1 || n.Requires[0] != "awg" {
		t.Fatalf("expected awg capability, got %v", n.Requires)
	}
}

func TestXHTTPAndMLKEMRequireCapabilities(t *testing.T) {
	uri := "vless://uuid@h.example.com:443?type=xhttp&mode=stream-up&path=%2Fx&security=tls&sni=h.example.com&encryption=mlkem768x25519plus.native.0rtt.abc"
	n, err := NewParser().ParseURI(uri)
	if err != nil {
		t.Fatal(err)
	}
	if n.Transport == nil || n.Transport.Type != "xhttp" || n.Transport.Mode != "stream-up" {
		t.Fatalf("xhttp lost: %+v", n.Transport)
	}
	if len(n.Requires) != 2 {
		t.Fatalf("want xhttp+mlkem, got %v", n.Requires)
	}
}

func TestAnyTLSAndSSH(t *testing.T) {
	p := NewParser()
	n, err := p.ParseURI("anytls://secret@a.example.com:443?sni=a.example.com#x")
	if err != nil || n.Type != "anytls" || n.Password != "secret" {
		t.Fatalf("%v %+v", err, n)
	}
	n, err = p.ParseURI("ssh://bob:pw@s.example.com:2222#s")
	if err != nil || n.Type != "ssh" || n.Port != 2222 {
		t.Fatalf("%v %+v", err, n)
	}
}

// The sanitized sample subscriptions from a real Iranian provider: every node
// must parse, and nodes using features mainline sing-box lacks must carry the
// matching capability so the engine reports them instead of mis-building them.
func TestRealWorldFixtures(t *testing.T) {
	read := func(name string) string {
		b, err := os.ReadFile("../../../test/fixtures/" + name)
		if err != nil {
			t.Fatal(err)
		}
		return string(b)
	}
	p := NewParser()

	b64, err := p.ParseWithWarnings(read("sub_dart.txt")) // base64 URI list
	if err != nil {
		t.Fatal(err)
	}
	plain, err := p.ParseWithWarnings(read("sub_dart_decoded.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if len(b64.Nodes) == 0 || len(b64.Nodes) != len(plain.Nodes) {
		t.Fatalf("base64=%d plain=%d", len(b64.Nodes), len(plain.Nodes))
	}
	caps := map[string]int{}
	for _, n := range plain.Nodes {
		for _, c := range n.Requires {
			caps[c]++
		}
	}
	if caps["xhttp"] == 0 || caps["mlkem"] == 0 || caps["tcphttp"] == 0 {
		t.Fatalf("expected xhttp+mlkem+tcphttp capabilities in fixtures, got %v", caps)
	}

	xr, err := p.ParseWithWarnings(read("sub_sample.json")) // Xray JSON subscription
	if err != nil || len(xr.Nodes) == 0 {
		t.Fatalf("xray json: %v", err)
	}
	sb, err := p.ParseWithWarnings(read("sub_singbox.json")) // sing-box config
	if err != nil || len(sb.Nodes) == 0 {
		t.Fatalf("sing-box json: %v", err)
	}
	t.Logf("uri=%d xray=%d singbox=%d caps=%v", len(plain.Nodes), len(xr.Nodes), len(sb.Nodes), caps)
}

func TestBase64WithSlashAndWrappedLines(t *testing.T) {
	// The comment line forces '/' and '+' into the base64 alphabet output.
	links := "#profile ???>>>???\ntrojan://pw@a.example.com:443?security=tls&sni=a.example.com#a\ntrojan://pw2@b.example.com:443?security=tls#b\n"
	enc := base64.StdEncoding.EncodeToString([]byte(links))
	if !strings.ContainsAny(enc, "/+") {
		t.Skip("sample has no '/' or '+'; adjust the payload")
	}
	var wrapped strings.Builder
	for i := 0; i < len(enc); i += 40 {
		end := i + 40
		if end > len(enc) {
			end = len(enc)
		}
		wrapped.WriteString(enc[i:end] + "\n")
	}
	res, err := NewParser().ParseWithWarnings(wrapped.String())
	if err != nil || len(res.Nodes) < 1 {
		t.Fatalf("wrapped base64 with '/' must parse: %v", err)
	}
}
