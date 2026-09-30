package adapter

import (
	"fmt"
	"net/netip"
	"time"

	"easyvpn/core/pkg/protocol"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
)

// openVPNEndpoint maps protocol.OpenVPNConfig (from config.ParseOVPN) onto the
// sing-box `openvpn-client` endpoint (available since sing-box 1.14.0).
func openVPNEndpoint(node *protocol.ProxyNode) (*option.Endpoint, error) {
	c := node.OpenVPN
	if c == nil {
		return nil, fmt.Errorf("openvpn: missing profile")
	}
	if len(c.Remotes) == 0 {
		return nil, fmt.Errorf("openvpn: profile has no remote")
	}
	o := &option.OpenVPNClientEndpointOptions{
		Mode:                 orDefaultStr(c.Mode, "tls"),
		Network:              c.Network,
		RemoteRandom:         c.RemoteRandom,
		Username:             c.Username,
		Password:             c.Password,
		Topology:             c.Topology,
		Cipher:               c.Cipher,
		DataCiphers:          c.DataCiphers,
		DataCiphersFallback:  c.DataCiphersFallback,
		Auth:                 c.Auth,
		Compression:          c.Compression,
		CompressionLZO:       c.CompressionLZO,
		RouteNoPull:          c.RouteNoPull,
		RedirectGateway:      c.RedirectGateway,
		RedirectGatewayFlags: c.RedirectFlags,
		KeyDirection:         c.KeyDirection,
	}
	if c.MSSFix > 0 {
		o.MSSFix = uint32(c.MSSFix)
	}
	if c.Fragment > 0 && (c.Network != "tcp") {
		o.Fragment = uint32(c.Fragment)
	}
	if c.PingRestartSec > 0 {
		o.PingRestart = badoption.Duration(time.Duration(c.PingRestartSec) * time.Second)
	}
	if c.RenegSec > 0 {
		o.RenegotiateInterval = badoption.Duration(time.Duration(c.RenegSec) * time.Second)
	}
	for _, p := range c.Routes {
		if pf, err := netip.ParsePrefix(p); err == nil {
			o.Routes = append(o.Routes, pf)
		}
	}
	for _, r := range c.Remotes {
		o.Servers = append(o.Servers, option.OpenVPNRemoteOptions{
			ServerOptions: option.ServerOptions{Server: r.Host, ServerPort: uint16(r.Port)},
			Network:       r.Network,
		})
	}
	if len(o.Servers) == 1 { // single remote: keep both forms out of conflict
		o.Servers = nil
		o.ServerOptions = option.ServerOptions{Server: c.Remotes[0].Host, ServerPort: uint16(c.Remotes[0].Port)}
		if o.Network == "" {
			o.Network = c.Remotes[0].Network
		}
	}

	if o.Mode == "static_key" {
		if c.StaticKey == "" {
			return nil, fmt.Errorf("openvpn: static_key mode without key")
		}
		o.StaticKey = []string{c.StaticKey}
	} else {
		tls := &option.OpenVPNOutboundTLSOptions{
			ServerName:           c.ServerName,
			RemoteCertificateTLS: c.RemoteCertTLS,
		}
		if c.CA != "" {
			tls.Certificate = []string{c.CA}
		}
		if c.Cert != "" {
			tls.ClientCertificate = []string{c.Cert}
		}
		if c.Key != "" {
			tls.ClientKey = []string{c.Key}
		}
		if c.ControlWrapType != "" {
			tls.ControlWrap = &option.OpenVPNControlWrapOptions{
				Type:      c.ControlWrapType,
				Key:       []string{c.ControlWrapKey},
				Direction: c.ControlWrapDir,
			}
		}
		if c.CA == "" {
			return nil, fmt.Errorf("openvpn: profile has no CA certificate")
		}
		o.TLS = tls
	}
	return &option.Endpoint{Type: C.TypeOpenVPNClient, Tag: "proxy", Options: o}, nil
}
