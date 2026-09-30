package export

import (
	"strings"
	"testing"

	"easyvpn/core/pkg/config"
	"easyvpn/core/pkg/protocol"
)

// Round-trip: every exported URI must parse back to an equivalent node.
func TestURIRoundTrip(t *testing.T) {
	p := config.NewParser()
	inputs := []string{
		"vless://b831381d-6324-4d53-ad4f-8cda48b30811@h.example.com:443?security=reality&sni=www.example.com&pbk=PUB&sid=ab&fp=chrome&flow=xtls-rprx-vision&encryption=none#reality",
		"vless://b831381d-6324-4d53-ad4f-8cda48b30811@h.example.com:443?security=tls&sni=h.example.com&type=ws&path=%2Fws&host=h.example.com&encryption=none#ws",
		"trojan://pw@t.example.com:443?security=tls&sni=t.example.com#trojan",
		"hysteria2://pw@hy.example.com:443?sni=hy.example.com&obfs=salamander&obfs-password=x#hy2",
		"anytls://pw@a.example.com:443?sni=a.example.com#anytls",
	}
	for _, in := range inputs {
		n, err := p.ParseURI(in)
		if err != nil {
			t.Fatalf("parse %q: %v", in, err)
		}
		out, err := URI(n)
		if err != nil {
			t.Fatalf("export %q: %v", in, err)
		}
		n2, err := p.ParseURI(out)
		if err != nil {
			t.Fatalf("reparse %q: %v", out, err)
		}
		if n.ComputeID() != n2.ComputeID() {
			t.Fatalf("round-trip changed identity:\n in: %s\nout: %s", in, out)
		}
	}
}

func TestClashYAMLContainsProxies(t *testing.T) {
	n, _ := config.NewParser().ParseURI("trojan://pw@t.example.com:443?security=tls&sni=t.example.com#t")
	y, err := ClashYAML([]*protocol.ProxyNode{n})
	if err != nil || !strings.Contains(y, "type: trojan") || !strings.Contains(y, "MATCH,PROXY") {
		t.Fatalf("%v\n%s", err, y)
	}
}
