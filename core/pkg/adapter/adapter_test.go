package adapter

import (
	"errors"
	"testing"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
	"easyvpn/core/pkg/rulesync"
)

func sampleNode(pt protocol.ProtocolType) *protocol.ProxyNode {
	return &protocol.ProxyNode{
		Name:     "test-" + string(pt),
		Type:     pt,
		Server:   "srv.example.com",
		Port:     443,
		UUID:     "b831381d-6324-4d53-ad4f-8cda48b30811",
		Password: "pw",
		Security: "aes-256-gcm",
		TLS: &protocol.TLSConfig{
			Enabled: true, ServerName: "srv.example.com", UTLS: true, Fingerprint: "chrome",
		},
	}
}

// BuildOptions must produce a valid mixed-in listener plus a protocol
// outbound for every supported node type — validating the option tree
// wiring before any box is created.
func TestBuildOptionsAllProtocols(t *testing.T) {
	for _, pt := range []protocol.ProtocolType{
		protocol.ProtoVLESS, protocol.ProtoVMess, protocol.ProtoTrojan,
		protocol.ProtoShadowsocks, protocol.ProtoSocks, protocol.ProtoHTTP,
		protocol.ProtoHysteria2, protocol.ProtoTUIC,
	} {
		req := &StartRequest{Node: sampleNode(pt), Routing: router.Default(), LocalPort: 2080}
		opts, err := BuildOptions(req)
		if err != nil {
			t.Fatalf("%s: BuildOptions: %v", pt, err)
		}
		if len(opts.Inbounds) != 1 || opts.Inbounds[0].Type != "mixed" {
			t.Fatalf("%s: expected single mixed inbound", pt)
		}
		if len(opts.Outbounds) != 3 || opts.Outbounds[1].Tag != "proxy" || opts.Outbounds[1].Type != "selector" {
			t.Fatalf("%s: expected node + selector + direct outbounds, got %d", pt, len(opts.Outbounds))
		}
		if opts.DNS == nil || len(opts.DNS.Servers) < 2 {
			t.Fatalf("%s: expected remote+local DNS servers", pt)
		}
		if len(opts.Route.Rules) == 0 {
			t.Fatalf("%s: expected compiled route rules", pt)
		}
	}
}

func TestBuildOptionsVLESSRealityFields(t *testing.T) {
	node := sampleNode(protocol.ProtoVLESS)
	node.Flow = "xtls-rprx-vision"
	node.TLS.Reality = &protocol.Reality{Enabled: true, PublicKey: "PK123", ShortID: "abcd"}
	opts, err := BuildOptions(&StartRequest{Node: node, Routing: router.Default()})
	if err != nil {
		t.Fatalf("BuildOptions: %v", err)
	}
	if opts.Outbounds[0].Type != "vless" {
		t.Fatalf("expected vless, got %s", opts.Outbounds[0].Type)
	}
	// Marshal to JSON to verify REALITY/tls fields survived the mapping.
	b, err := marshalJSON(&opts)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	for _, want := range []string{`"reality"`, `"public_key":"PK123"`, `"flow":"xtls-rprx-vision"`, `"utls"`, `"fingerprint":"chrome"`} {
		if !contains(string(b), want) {
			t.Fatalf("serialized outbound missing %s: %s", want, b)
		}
	}
}

func TestBuildOptionsWireGuard(t *testing.T) {
	node := sampleNode(protocol.ProtoWireGuard)
	node.UUID = ""
	node.WireGuard = &protocol.WireGuardConfig{
		PrivateKey:   "eCtX0T4W4+Z7JPVQvZkYtUvYB4m0mpXGpjD5jT4tkVk=",
		PublicKey:    "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
		LocalAddress: []string{"172.16.0.2/32"},
		Reserved:     []uint8{1, 2, 3},
	}
	opts, err := BuildOptions(&StartRequest{Node: node, Routing: router.Default()})
	if err != nil {
		t.Fatalf("BuildOptions: %v", err)
	}
	if len(opts.Endpoints) != 1 || opts.Endpoints[0].Type != "wireguard" {
		t.Fatalf("expected wireguard endpoint, got %+v", opts.Endpoints)
	}
	b, _ := marshalJSON(&opts)
	for _, want := range []string{"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "172.16.0.2/32"} {
		if !contains(string(b), want) {
			t.Fatalf("wireguard outbound missing %s: %s", want, b)
		}
	}
}

func TestBuildOptionsRejectsInvalid(t *testing.T) {
	node := sampleNode(protocol.ProtoVLESS)
	node.UUID = ""
	if _, err := BuildOptions(&StartRequest{Node: node, Routing: router.Default()}); err == nil {
		t.Fatalf("expected error for vless without uuid")
	}
	if _, err := BuildOptions(&StartRequest{Node: nil, Routing: router.Default()}); err == nil {
		t.Fatalf("expected error for nil node")
	}
}

func TestRoutingCompilationIranPreset(t *testing.T) {
	rs, err := rulesync.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	m := router.Default()
	m.RuleSetDir = rs.Dir
	rules := router.BuildRouteRules(m)
	// sniff + hijack-dns + block + LAN + service override + .ir suffix + IR sets = at least 7
	if len(rules) < 7 {
		t.Fatalf("expected >=5 rules for ir preset, got %d", len(rules))
	}
	sets := router.BuildRuleSets(m)
	tags := map[string]bool{}
	for _, s := range sets {
		tags[s.Tag[0]] = true
	}
	for _, want := range []string{"geosite-ir", "geoip-ir", "geosite-ads-all"} {
		if !tags[want] {
			t.Fatalf("missing rule-set %s in %v", want, tags)
		}
	}
	dns := router.BuildDNSOptions(m)
	if dns.Final != "dns-remote" {
		t.Fatalf("expected dns-remote final, got %s", dns.Final)
	}
	if len(dns.Rules) == 0 {
		t.Fatalf("expected domestic DNS rule for country preset")
	}
}

func contains(hay, needle string) bool {
	return len(hay) >= len(needle) && (func() bool {
		for i := 0; i+len(needle) <= len(hay); i++ {
			if hay[i:i+len(needle)] == needle {
				return true
			}
		}
		return false
	})()
}

func TestConnectionModesProduceInbounds(t *testing.T) {
	cases := map[ConnMode][]string{
		ModeTUN:         {"tun"},
		ModeSystemProxy: {"mixed"},
		ModeProxyOnly:   {"mixed"},
		ModeBoth:        {"mixed", "tun"},
	}
	for mode, want := range cases {
		opts, err := BuildOptions(&StartRequest{Node: sampleNode(protocol.ProtoTrojan), Routing: router.Default(), Mode: mode})
		if err != nil {
			t.Fatalf("%s: %v", mode, err)
		}
		if len(opts.Inbounds) != len(want) {
			t.Fatalf("%s: got %d inbounds, want %v", mode, len(opts.Inbounds), want)
		}
		for i, w := range want {
			if opts.Inbounds[i].Type != w {
				t.Fatalf("%s: inbound %d is %s, want %s", mode, i, opts.Inbounds[i].Type, w)
			}
		}
		if mode.NeedsTUN() && !opts.Route.AutoDetectInterface {
			t.Fatalf("%s: TUN needs auto_detect_interface", mode)
		}
	}
	if ParseConnMode("bogus") != ModeProxyOnly {
		t.Fatal("unknown mode must default to proxy_only")
	}
}

func TestSelectorMaterializesCandidatesAndCapabilityErrors(t *testing.T) {
	active := sampleNode(protocol.ProtoTrojan)
	other := sampleNode(protocol.ProtoVLESS)
	other.Server = "other.example.com"
	xh := sampleNode(protocol.ProtoVLESS)
	xh.Server = "xh.example.com"
	xh.Transport = &protocol.TransportConfig{Type: "xhttp"}
	req := &StartRequest{Node: active, Candidates: []*protocol.ProxyNode{other, xh}, Routing: router.Default()}
	opts, tags, err := buildOptionsWithTags(req)
	if err != nil {
		t.Fatal(err)
	}
	if len(tags) != 2 { // active + other; xhttp candidate skipped, not fatal
		t.Fatalf("expected 2 materialized nodes, got %d", len(tags))
	}
	// urltest "auto" group appears with >1 node
	found := false
	for _, o := range opts.Outbounds {
		if o.Tag == "auto" && o.Type == "urltest" {
			found = true
		}
	}
	if !found {
		t.Fatal("missing urltest group")
	}
	// An unsupported ACTIVE node is a typed error.
	_, err = BuildOptions(&StartRequest{Node: xh, Routing: router.Default()})
	var ue *UnsupportedError
	if !errors.As(err, &ue) || ue.Capability != "xhttp" {
		t.Fatalf("want UnsupportedError(xhttp), got %v", err)
	}
}
