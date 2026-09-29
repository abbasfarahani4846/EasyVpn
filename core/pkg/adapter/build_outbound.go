// build_outbound.go maps the internal protocol.ProxyNode model onto
// sing-box outbound options (all schema fields verified against sing-box
// v1.14.2 option structs).
package adapter

import (
	"fmt"
	"net/netip"
	"strings"

	"easyvpn/core/pkg/protocol"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
)

// UnsupportedError reports that the active core cannot honor a node feature.
// The engine surfaces it as "unsupported_by_core:<capability>" so the UI can
// offer another core instead of silently mis-building the node.
type UnsupportedError struct {
	Capability string
	Detail     string
}

func (e *UnsupportedError) Error() string {
	return "unsupported_by_core:" + e.Capability + " (" + e.Detail + ")"
}

// singboxCapabilities lists optional node capabilities sing-box 1.14 mainline
// can honor. xhttp/mlkem/awg are deliberately absent (see docs/MASTER_PROMPT.md §2.1).
var singboxCapabilities = map[string]bool{
	protocol.CapOpenVPN: true,
}

// builtNode is the result of compiling one node: either an outbound or an
// endpoint (WireGuard, OpenVPN are endpoints in sing-box >= 1.11).
type builtNode struct {
	Outbound *option.Outbound
	Endpoint *option.Endpoint
}

// buildNode compiles a node under the given tag.
func buildNode(node *protocol.ProxyNode, tag string) (*builtNode, error) {
	node.EnsureID()
	for _, c := range node.Requires {
		if !singboxCapabilities[c] {
			return nil, &UnsupportedError{Capability: c, Detail: "not available in sing-box " + "1.14"}
		}
	}
	switch node.Type {
	case protocol.ProtoWireGuard:
		o, err := wireGuardEndpoint(node)
		if err != nil {
			return nil, err
		}
		return &builtNode{Endpoint: &option.Endpoint{Type: C.TypeWireGuard, Tag: tag, Options: o.Options}}, nil
	case protocol.ProtoOpenVPN:
		ep, err := openVPNEndpoint(node)
		if err != nil {
			return nil, err
		}
		ep.Tag = tag
		return &builtNode{Endpoint: ep}, nil
	}
	o, err := buildOutbound(node)
	if err != nil {
		return nil, err
	}
	o.Tag = tag
	return &builtNode{Outbound: &o}, nil
}

func buildOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	node.EnsureID()
	switch node.Type {
	case protocol.ProtoVLESS:
		return vlessOutbound(node)
	case protocol.ProtoVMess:
		return vmessOutbound(node)
	case protocol.ProtoTrojan:
		return trojanOutbound(node)
	case protocol.ProtoShadowsocks:
		return shadowsocksOutbound(node)
	case protocol.ProtoSocks:
		return socksOutbound(node)
	case protocol.ProtoHTTP:
		return httpOutbound(node)
	case protocol.ProtoHysteria2:
		return hysteria2Outbound(node)
	case protocol.ProtoTUIC:
		return tuicOutbound(node)
	case protocol.ProtoAnyTLS:
		return anyTLSOutbound(node)
	case protocol.ProtoSSH:
		return sshOutbound(node)
	case protocol.ProtoWireGuard:
		return wireGuardEndpoint(node)
	default:
		return option.Outbound{}, fmt.Errorf("protocol %q not supported by sing-box adapter", node.Type)
	}
}

func serverOptions(node *protocol.ProxyNode) option.ServerOptions {
	return option.ServerOptions{Server: node.Server, ServerPort: uint16(node.Port)}
}

func tlsOptions(t *protocol.TLSConfig) *option.OutboundTLSOptions {
	if t == nil || !t.Enabled {
		return nil
	}
	o := &option.OutboundTLSOptions{
		Enabled:    true,
		ServerName: t.ServerName,
		Insecure:   t.Insecure,
		ALPN:       t.ALPN,
	}
	if t.Reality != nil && t.Reality.Enabled {
		o.Reality = &option.OutboundRealityOptions{
			Enabled:   true,
			PublicKey: t.Reality.PublicKey,
			ShortID:   t.Reality.ShortID,
		}
		if !t.UTLS { // REALITY requires a uTLS fingerprint
			o.UTLS = &option.OutboundUTLSOptions{Enabled: true, Fingerprint: orDefaultStr(t.Fingerprint, "chrome")}
		}
	}
	o.Fragment = t.Fragment
	o.RecordFragment = t.RecordFragment
	if t.ECH {
		o.ECH = &option.OutboundECHOptions{Enabled: true, Config: t.ECHConfig}
	}
	if t.UTLS {
		fp := t.Fingerprint
		if fp == "" {
			fp = "chrome"
		}
		o.UTLS = &option.OutboundUTLSOptions{Enabled: true, Fingerprint: fp}
	}
	return o
}

// transportOptions maps our transport model onto V2Ray transport options.
func transportOptions(tc *protocol.TransportConfig) *option.V2RayTransportOptions {
	if tc == nil || tc.Type == "" || tc.Type == "tcp" || tc.Type == "raw" {
		return nil
	}
	switch strings.ToLower(tc.Type) {
	case "ws":
		ws := &option.V2RayWebsocketOptions{Path: tc.Path}
		if tc.Host != "" {
			ws.Headers = badoption.HTTPHeader{"Host": []string{tc.Host}}
		}
		for k, v := range tc.Headers {
			if !strings.EqualFold(k, "Host") {
				ws.Headers[k] = []string{v}
			}
		}
		return &option.V2RayTransportOptions{Type: "ws", WebsocketOptions: *ws}
	case "grpc":
		return &option.V2RayTransportOptions{
			Type:        "grpc",
			GRPCOptions: option.V2RayGRPCOptions{ServiceName: tc.ServiceName},
		}
	case "httpupgrade":
		return &option.V2RayTransportOptions{
			Type:               "httpupgrade",
			HTTPUpgradeOptions: option.V2RayHTTPUpgradeOptions{Host: tc.Host, Path: tc.Path},
		}
	case "http", "h2":
		return &option.V2RayTransportOptions{
			Type:        "http",
			HTTPOptions: option.V2RayHTTPOptions{Host: []string{tc.Host}, Path: tc.Path},
		}
	default:
		return nil
	}
}

func vlessOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	if node.UUID == "" {
		return option.Outbound{}, fmt.Errorf("vless: missing uuid")
	}
	o := &option.VLESSOutboundOptions{
		ServerOptions:  serverOptions(node),
		UUID:           node.UUID,
		Flow:           node.Flow,
		Transport:      transportOptions(node.Transport),
		PacketEncoding: packetEncodingPtr("xudp"),
		Multiplex:      muxOptions(node.Mux),
	}
	o.TLS = tlsOptions(node.TLS)
	return option.Outbound{Type: C.TypeVLESS, Tag: "proxy", Options: o}, nil
}

func vmessOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	if node.UUID == "" {
		return option.Outbound{}, fmt.Errorf("vmess: missing uuid")
	}
	o := &option.VMessOutboundOptions{
		ServerOptions:  serverOptions(node),
		UUID:           node.UUID,
		Security:       orDefaultStr(node.Security, "auto"),
		AlterId:        node.AlterID,
		Transport:      transportOptions(node.Transport),
		PacketEncoding: "xudp",
	}
	o.TLS = tlsOptions(node.TLS)
	return option.Outbound{Type: C.TypeVMess, Tag: "proxy", Options: o}, nil
}

func packetEncodingPtr(v string) *string { return &v }

func trojanOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	if node.Password == "" {
		return option.Outbound{}, fmt.Errorf("trojan: missing password")
	}
	tls := node.TLS
	if tls == nil {
		tls = &protocol.TLSConfig{Enabled: true, ServerName: node.Server}
	}
	o := &option.TrojanOutboundOptions{
		ServerOptions: serverOptions(node),
		Password:      node.Password,
		Transport:     transportOptions(node.Transport),
		Multiplex:     muxOptions(node.Mux),
	}
	o.TLS = tlsOptions(tls)
	return option.Outbound{Type: C.TypeTrojan, Tag: "proxy", Options: o}, nil
}

func shadowsocksOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	if node.Security == "" || node.Password == "" {
		return option.Outbound{}, fmt.Errorf("shadowsocks: missing method/password")
	}
	o := &option.ShadowsocksOutboundOptions{
		ServerOptions: serverOptions(node),
		Method:        node.Security,
		Password:      node.Password,
	}
	return option.Outbound{Type: C.TypeShadowsocks, Tag: "proxy", Options: o}, nil
}

func socksOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	o := &option.SOCKSOutboundOptions{
		ServerOptions: serverOptions(node),
		Version:       "5",
		Username:      node.UUID,
		Password:      node.Password,
	}
	return option.Outbound{Type: C.TypeSOCKS, Tag: "proxy", Options: o}, nil
}

func httpOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	o := &option.HTTPOutboundOptions{
		ServerOptions: serverOptions(node),
		Username:      node.UUID,
		Password:      node.Password,
	}
	o.TLS = tlsOptions(node.TLS)
	return option.Outbound{Type: C.TypeHTTP, Tag: "proxy", Options: o}, nil
}

func hysteria2Outbound(node *protocol.ProxyNode) (option.Outbound, error) {
	tls := node.TLS
	if tls == nil {
		tls = &protocol.TLSConfig{Enabled: true, ServerName: node.Server}
	}
	o := &option.Hysteria2OutboundOptions{
		ServerOptions: serverOptions(node),
		Password:      node.Password,
	}
	o.TLS = tlsOptions(tls)
	if node.Hysteria2 != nil && node.Hysteria2.ObfsPassword != "" {
		o.Obfs = &option.Hysteria2Obfs{
			Type:     orDefaultStr(node.Hysteria2.ObfsType, "salamander"),
			Password: node.Hysteria2.ObfsPassword,
		}
	}
	return option.Outbound{Type: C.TypeHysteria2, Tag: "proxy", Options: o}, nil
}

func tuicOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	if node.UUID == "" {
		return option.Outbound{}, fmt.Errorf("tuic: missing uuid")
	}
	tls := node.TLS
	if tls == nil {
		tls = &protocol.TLSConfig{Enabled: true, ServerName: node.Server}
	}
	o := &option.TUICOutboundOptions{
		ServerOptions: serverOptions(node),
		UUID:          node.UUID,
		Password:      node.Password,
	}
	o.TLS = tlsOptions(tls)
	if node.TUIC != nil {
		o.CongestionControl = node.TUIC.CongestionControl
		o.UDPRelayMode = node.TUIC.UDPRelayMode
	}
	return option.Outbound{Type: C.TypeTUIC, Tag: "proxy", Options: o}, nil
}

// wireGuardEndpoint builds a WireGuard endpoint (sing-box 1.11+ style).
func wireGuardEndpoint(node *protocol.ProxyNode) (option.Outbound, error) {
	wg := node.WireGuard
	if wg == nil || wg.PrivateKey == "" || wg.PublicKey == "" {
		return option.Outbound{}, fmt.Errorf("wireguard: missing keys")
	}
	ep := &option.WireGuardEndpointOptions{
		PrivateKey: wg.PrivateKey,
		ListenPort: 0,
		DialerOptions: option.DialerOptions{
			Detour: "", // direct
		},
	}
	for _, a := range wg.LocalAddress {
		if p, err := netip.ParsePrefix(a); err == nil {
			ep.Address = append(ep.Address, p)
		} else if ip, err := netip.ParseAddr(a); err == nil {
			ep.Address = append(ep.Address, netip.PrefixFrom(ip, ip.BitLen()))
		}
	}
	if len(ep.Address) == 0 {
		return option.Outbound{}, fmt.Errorf("wireguard: no valid local address")
	}
	if wg.MTU > 0 {
		ep.MTU = uint32(wg.MTU)
	}
	peer := option.WireGuardPeer{
		Address:      node.Server,
		Port:         uint16(node.Port),
		PublicKey:    wg.PublicKey,
		AllowedIPs:   []netip.Prefix{netip.MustParsePrefix("0.0.0.0/0"), netip.MustParsePrefix("::/0")},
		Reserved:     wg.Reserved,
		PreSharedKey: wg.PreSharedKey,
	}
	ep.Peers = []option.WireGuardPeer{peer}
	return option.Outbound{Type: C.TypeWireGuard, Tag: "proxy", Options: ep}, nil
}

func muxOptions(m *protocol.MuxConfig) *option.OutboundMultiplexOptions {
	if m == nil || !m.Enabled {
		return nil
	}
	return &option.OutboundMultiplexOptions{
		Enabled:        true,
		Protocol:       orDefaultStr(m.Protocol, "smux"),
		MaxConnections: m.MaxConnections,
		Padding:        m.Padding,
	}
}

func anyTLSOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	if node.Password == "" {
		return option.Outbound{}, fmt.Errorf("anytls: missing password")
	}
	tls := node.TLS
	if tls == nil {
		tls = &protocol.TLSConfig{Enabled: true, ServerName: node.Server}
	}
	o := &option.AnyTLSOutboundOptions{ServerOptions: serverOptions(node), Password: node.Password}
	o.TLS = tlsOptions(tls)
	return option.Outbound{Type: C.TypeAnyTLS, Tag: "proxy", Options: o}, nil
}

func sshOutbound(node *protocol.ProxyNode) (option.Outbound, error) {
	o := &option.SSHOutboundOptions{
		ServerOptions: serverOptions(node),
		User:          node.UUID,
		Password:      node.Password,
	}
	if node.SSH != nil {
		if node.SSH.PrivateKey != "" {
			o.PrivateKey = []string{node.SSH.PrivateKey}
		}
		o.PrivateKeyPassphrase = node.SSH.Passphrase
		o.HostKey = node.SSH.HostKeys
	}
	if o.User == "" {
		o.User = "root"
	}
	if o.Password == "" && len(o.PrivateKey) == 0 {
		return option.Outbound{}, fmt.Errorf("ssh: need password or private key")
	}
	return option.Outbound{Type: C.TypeSSH, Tag: "proxy", Options: o}, nil
}
