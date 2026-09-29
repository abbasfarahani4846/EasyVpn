package config

import (
	"encoding/base64"
	"testing"

	"easyvpn/core/pkg/protocol"
)

func TestParseVLESSReality(t *testing.T) {
	p := NewParser()
	uri := "vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc&sid=6ba85179&type=tcp&flow=xtls-rprx-vision#MyRealityNode"
	node, err := p.ParseURI(uri)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if node.Type != protocol.ProtoVLESS || node.Server != "example.com" || node.Port != 443 {
		t.Fatalf("bad base fields: %+v", node)
	}
	if node.UUID != "b831381d-6324-4d53-ad4f-8cda48b30811" || node.Flow != "xtls-rprx-vision" {
		t.Fatalf("bad uuid/flow: %+v", node)
	}
	if node.Name != "MyRealityNode" {
		t.Fatalf("bad name: %q", node.Name)
	}
	if node.TLS == nil || !node.TLS.Enabled || node.TLS.ServerName != "www.microsoft.com" {
		t.Fatalf("bad tls: %+v", node.TLS)
	}
	if node.TLS.Reality == nil || !node.TLS.Reality.Enabled || node.TLS.Reality.PublicKey != "SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc" {
		t.Fatalf("bad reality: %+v", node.TLS.Reality)
	}
	if node.TLS.Fingerprint != "chrome" || !node.TLS.UTLS {
		t.Fatalf("bad fingerprint: %+v", node.TLS)
	}
	if node.ID == "" {
		t.Fatalf("expected content-hash id")
	}
}

func TestParseVMessBase64(t *testing.T) {
	p := NewParser()
	body := base64.StdEncoding.EncodeToString([]byte(
		`{"v":"2","ps":"Test VMess","add":"vm.example.com","port":"8443","id":"a3482d88-1b1b-4d53-ad4f-8cda48b30811","aid":"0","scy":"auto","net":"ws","host":"cdn.example.com","path":"/wspath","tls":"tls","sni":"vm.example.com"}`))
	node, err := p.ParseURI("vmess://" + body)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if node.Type != protocol.ProtoVMess || node.Server != "vm.example.com" || node.Port != 8443 {
		t.Fatalf("bad fields: %+v", node)
	}
	if node.Name != "Test VMess" || node.Security != "auto" || node.AlterID != 0 {
		t.Fatalf("bad name/security/aid: %+v", node)
	}
	if node.Transport == nil || node.Transport.Type != "ws" || node.Transport.Path != "/wspath" || node.Transport.Host != "cdn.example.com" {
		t.Fatalf("bad transport: %+v", node.Transport)
	}
	if node.TLS == nil || node.TLS.ServerName != "vm.example.com" {
		t.Fatalf("bad tls: %+v", node.TLS)
	}
}

func TestParseTrojan(t *testing.T) {
	p := NewParser()
	uri := "trojan://passw0rd@trojan.example.com:443?sni=trojan.example.com&type=ws&path=%2Ftrojan#TrojanWS"
	node, err := p.ParseURI(uri)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if node.Type != protocol.ProtoTrojan || node.Password != "passw0rd" || node.Port != 443 {
		t.Fatalf("bad fields: %+v", node)
	}
	if node.TLS == nil || !node.TLS.Enabled || node.TLS.ServerName != "trojan.example.com" {
		t.Fatalf("bad tls: %+v", node.TLS)
	}
	if node.Transport == nil || node.Transport.Type != "ws" || node.Transport.Path != "/trojan" {
		t.Fatalf("bad transport: %+v", node.Transport)
	}
}

func TestParseShadowsocksSIP002(t *testing.T) {
	p := NewParser()
	uri := "ss://YWVzLTI1Ni1nY206c2VjcmV0cGFzcw==@ss.example.com:8388#SSNode"
	node, err := p.ParseURI(uri)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if node.Type != protocol.ProtoShadowsocks || node.Server != "ss.example.com" || node.Port != 8388 {
		t.Fatalf("bad fields: %+v", node)
	}
	// method:pass were base64-encoded together.
	if node.Security != "aes-256-gcm" || node.Password != "secretpass" {
		t.Fatalf("bad method/password: %q/%q", node.Security, node.Password)
	}
}

func TestParseHysteria2(t *testing.T) {
	p := NewParser()
	uri := "hysteria2://hypass@hy2.example.com:443?sni=hy2.example.com&obfs=salamander&obfs-password=obfspass&insecure=1#HY2"
	node, err := p.ParseURI(uri)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if node.Type != protocol.ProtoHysteria2 || node.Password != "hypass" {
		t.Fatalf("bad fields: %+v", node)
	}
	if node.Hysteria2 == nil || node.Hysteria2.ObfsType != "salamander" || node.Hysteria2.ObfsPassword != "obfspass" {
		t.Fatalf("bad obfs: %+v", node.Hysteria2)
	}
	if node.TLS == nil || !node.TLS.Insecure {
		t.Fatalf("bad tls: %+v", node.TLS)
	}
}

func TestParseTUIC(t *testing.T) {
	p := NewParser()
	uri := "tuic://uuid-here@tuic.example.com:443?congestion_control=bbr&udp_relay_mode=native&sni=tuic.example.com#TUIC"
	node, err := p.ParseURI(uri)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if node.Type != protocol.ProtoTUIC || node.UUID != "uuid-here" {
		t.Fatalf("bad fields: %+v", node)
	}
	if node.TUIC == nil || node.TUIC.CongestionControl != "bbr" || node.TUIC.UDPRelayMode != "native" {
		t.Fatalf("bad tuic opts: %+v", node.TUIC)
	}
}

func TestParseClashYAMLWithReality(t *testing.T) {
	yamlDoc := `
proxies:
  - name: "Reality Node"
    type: vless
    server: clash.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
    flow: xtls-rprx-vision
    tls: true
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc
      short-id: "6ba85179"
    network: tcp
  - name: "Plain SS"
    type: ss
    server: ss2.example.com
    port: 443
    cipher: chacha20-ietf-poly1305
    password: "pw2"
`
	nodes, warns, ok := parseClashYAML([]byte(yamlDoc))
	if !ok || len(nodes) != 2 {
		t.Fatalf("expected 2 nodes, got %d (warns=%v)", len(nodes), warns)
	}
	r := nodes[0]
	if r.TLS == nil || r.TLS.Reality == nil || r.TLS.Reality.PublicKey != "SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc" {
		t.Fatalf("bad reality from clash yaml: %+v", r.TLS)
	}
	if r.TLS.ServerName != "www.microsoft.com" || !r.TLS.UTLS || r.TLS.Fingerprint != "chrome" {
		t.Fatalf("bad tls from clash yaml: %+v", r.TLS)
	}
	if nodes[1].Security != "chacha20-ietf-poly1305" || nodes[1].Password != "pw2" {
		t.Fatalf("bad ss from clash yaml: %+v", nodes[1])
	}
}

func TestParseBase64Subscription(t *testing.T) {
	p := NewParser()
	links := "vless://b831381d-6324-4d53-ad4f-8cda48b30811@one.example.com:443?encryption=none&security=tls#Node1\ntrojan://pw@two.example.com:443#Node2\n"
	payload := base64.StdEncoding.EncodeToString([]byte(links))
	nodes, err := p.ParseContent(payload)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(nodes) != 2 {
		t.Fatalf("expected 2 nodes, got %d", len(nodes))
	}
	if nodes[0].Name != "Node1" || nodes[1].Name != "Node2" {
		t.Fatalf("bad names: %q %q", nodes[0].Name, nodes[1].Name)
	}
}

func TestNodeIDStableAcrossNameChanges(t *testing.T) {
	p := NewParser()
	u1 := "vless://b831381d-6324-4d53-ad4f-8cda48b30811@srv.example.com:443?encryption=none&security=tls#NameA"
	u2 := "vless://b831381d-6324-4d53-ad4f-8cda48b30811@srv.example.com:443?encryption=none&security=tls#RenamedNode"
	n1, _ := p.ParseURI(u1)
	n2, _ := p.ParseURI(u2)
	if n1.ID != n2.ID {
		t.Fatalf("content-hash ID changed when only the name changed: %s vs %s", n1.ID, n2.ID)
	}
}

func TestParseContentAutoDetect(t *testing.T) {
	p := NewParser()
	res, err := p.ParseWithWarnings("vless://b831381d-6324-4d53-ad4f-8cda48b30811@x.example.com:443?encryption=none#A\nnot-a-valid-line\n")
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(res.Nodes) != 1 {
		t.Fatalf("expected 1 node, got %d", len(res.Nodes))
	}
	if len(res.Warnings) == 0 {
		t.Fatalf("expected a skip warning for the invalid line")
	}
}
