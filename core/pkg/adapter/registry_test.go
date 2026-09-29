package adapter

import (
	"context"
	"testing"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
	"easyvpn/core/pkg/rulesync"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
)

// Every supported protocol must be creatable in a box. If a required build tag
// is missing from the Makefile TAGS, sing-box reports "unknown outbound/endpoint
// type" here — this test is the guard (run it with the same -tags as the build:
// `make test`).
func TestAllProtocolsRegisteredInBox(t *testing.T) {
	wg := &protocol.WireGuardConfig{
		PrivateKey:   "eCtX0T4W4+Z7JPVQvZkYtUvYB4m0mpXGpjD5jT4tkVk=",
		PublicKey:    "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
		LocalAddress: []string{"172.16.0.2/32"},
	}
	ovpn := &protocol.OpenVPNConfig{
		Mode: "tls", Network: "udp",
		Remotes: []protocol.OVPNRemote{{Host: "vpn.example.com", Port: 1194, Network: "udp"}},
		CA:      testCA,
	}
	for _, pt := range []protocol.ProtocolType{
		protocol.ProtoVLESS, protocol.ProtoVMess, protocol.ProtoTrojan, protocol.ProtoShadowsocks,
		protocol.ProtoSocks, protocol.ProtoHTTP, protocol.ProtoHysteria2, protocol.ProtoTUIC,
		protocol.ProtoAnyTLS, protocol.ProtoSSH, protocol.ProtoWireGuard, protocol.ProtoOpenVPN,
	} {
		n := sampleNode(pt)
		n.Server = "203.0.113.10"
		switch pt {
		case protocol.ProtoVMess:
			n.Security = "auto"
		case protocol.ProtoWireGuard:
			n.WireGuard = wg
		case protocol.ProtoOpenVPN:
			n.OpenVPN = ovpn
		case protocol.ProtoSSH:
			n.UUID, n.Password = "root", "pw"
		}
		opts, err := BuildOptions(&StartRequest{Node: n, Routing: router.Model{Mode: router.ModeGlobalProxy}, Mode: ModeProxyOnly, LocalPort: 0})
		if err != nil {
			t.Fatalf("%s: build: %v", pt, err)
		}
		ctx := include.Context(context.Background())
		b, err := box.New(box.Options{Context: ctx, Options: opts})
		if err != nil {
			t.Fatalf("%s: box.New: %v (missing build tag?)", pt, err)
		}
		_ = b.Close()
	}
}

// testCA is a syntactically valid self-signed certificate used only to satisfy
// endpoint option validation in tests.
const testCA = `-----BEGIN CERTIFICATE-----
MIIBtjCCAVugAwIBAgITBmyf1XSXNmY/Owua2eiedgPySjAKBggqhkjOPQQDAjA5
MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6b24g
Um9vdCBDQSAzMB4XDTE1MDUyNjAwMDAwMFoXDTQwMDUyNjAwMDAwMFowOTELMAkG
A1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJvb3Qg
Q0EgMzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCmXp8ZBf8ANm+gBG1bG8lKl
ui2yEujSLtf6ycXYqm0fc4E7O5hrOXwzpcVOho6AF2hiRVd9RFgdszflZwjrZt6j
QjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBSr
ttvXBp43rDCGB5Fwx5zEGbF4wDAKBggqhkjOPQQDAgNJADBGAiEA4IWSoxe3jfkr
BqWTrBqYaGFy+uGh0PsceGCmQ5nFuMQCIQCcAu/xlJyzlvnrxir4tiz+OpAUFteM
YyRIHN8wfdVoOw==
-----END CERTIFICATE-----`

// Every routing mode x country must yield a config that sing-box accepts,
// with and without downloaded rule-sets (regression for undeclared tags).
func TestAllModesAndCountriesCreateBox(t *testing.T) {
	rs, err := rulesync.New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	modes := []router.RoutingMode{router.ModeBypassLocalAndCountry, router.ModeBypassLANOnly, router.ModeGlobalProxy, router.ModeBypassProxy, router.ModeCustom}
	for _, country := range []string{"IR", "CN", "RU", "", "ZZ"} {
		for _, mode := range modes {
			for _, withSets := range []bool{true, false} {
				m := router.Default()
				m.Mode, m.Country, m.FakeIPEnabled = mode, country, true
				m.CustomRules = []router.Rule{{Kind: router.KindDomainSuffix, Values: []string{"example.com"}, Outbound: router.OutboundBlock}}
				if withSets {
					m.RuleSetDir = rs.Dir
				} else {
					m.RuleSetDir = t.TempDir()
				}
				n := sampleNode(protocol.ProtoTrojan)
				n.Server = "203.0.113.10"
				for _, cm := range []ConnMode{ModeProxyOnly, ModeBoth} {
					opts, err := BuildOptions(&StartRequest{Node: n, Routing: m, Mode: cm})
					if err != nil {
						t.Fatalf("%s/%s/sets=%v: %v", country, mode, withSets, err)
					}
					b, err := box.New(box.Options{Context: include.Context(context.Background()), Options: opts})
					if err != nil {
						t.Fatalf("%s/%s/%s/sets=%v: box.New: %v", country, mode, cm, withSets, err)
					}
					_ = b.Close()
				}
			}
		}
	}
}
