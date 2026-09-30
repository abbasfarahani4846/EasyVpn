package config

import (
	"encoding/json"
	"fmt"
	"strings"

	"easyvpn/core/pkg/protocol"
)

// ---------------------------------------------------------------------------
// Format detection & dispatch
// ---------------------------------------------------------------------------

// parseJSONConfigs handles every JSON-based subscription shape:
//  1. A JSON array of full Xray/v2ray client configs (what v2rayNG receives).
//  2. A single full Xray/v2ray client config object (inbounds/outbounds/routing).
//  3. A sing-box config object (log/dns/inbounds/outbounds/route).
//  4. A bare JSON array of sing-box outbound objects.
func (p *Parser) parseJSONConfigs(content string) ([]*protocol.ProxyNode, error) {
	trimmed := strings.TrimSpace(content)

	// --- Array forms ---
	if strings.HasPrefix(trimmed, "[") {
		var arr []json.RawMessage
		if err := json.Unmarshal([]byte(trimmed), &arr); err != nil {
			return nil, err
		}
		var nodes []*protocol.ProxyNode
		for _, item := range arr {
			var probe map[string]json.RawMessage
			if json.Unmarshal(item, &probe) != nil {
				continue
			}
			if _, ok := probe["outbounds"]; ok {
				// Element is a full Xray client config.
				nodes = append(nodes, p.parseXrayConfigObject(item)...)
			} else if _, ok := probe["type"]; ok {
				// Element is a bare sing-box outbound.
				if n := p.parseSingboxOutboundRaw(item); n != nil {
					nodes = append(nodes, n)
				}
			}
		}
		if len(nodes) == 0 {
			return nil, fmt.Errorf("no proxy outbounds found in JSON array")
		}
		return nodes, nil
	}

	// --- Object forms ---
	var probe map[string]json.RawMessage
	if err := json.Unmarshal([]byte(trimmed), &probe); err != nil {
		return nil, err
	}
	if _, ok := probe["outbounds"]; !ok {
		return nil, fmt.Errorf("JSON object has no outbounds")
	}
	var obj struct {
		Outbounds []json.RawMessage `json:"outbounds"`
	}
	if err := json.Unmarshal([]byte(trimmed), &obj); err != nil || len(obj.Outbounds) == 0 {
		return nil, fmt.Errorf("invalid outbounds block")
	}

	var nodes []*protocol.ProxyNode
	var sawXrayShape bool
	for _, ob := range obj.Outbounds {
		var op map[string]json.RawMessage
		if json.Unmarshal(ob, &op) != nil {
			continue
		}
		if _, ok := op["protocol"]; ok {
			// Xray/v2ray outbound shape (protocol/settings/streamSettings).
			sawXrayShape = true
			if n := p.parseXrayOutbound(ob); n != nil {
				nodes = append(nodes, n)
			}
		} else if _, ok := op["type"]; ok {
			// sing-box outbound shape (type/server/server_port/...).
			if n := p.parseSingboxOutboundRaw(ob); n != nil {
				nodes = append(nodes, n)
			}
		}
	}
	// A full Xray config whose only outbounds are freedom/block yields zero
	// nodes; treat that as "not a proxy config" so callers can fall through.
	if len(nodes) == 0 && !sawXrayShape {
		return nil, fmt.Errorf("no proxy outbounds found in JSON object")
	}
	return nodes, nil
}

// ---------------------------------------------------------------------------
// Xray / v2ray core format
// ---------------------------------------------------------------------------

type xrayStreamSettings struct {
	Network     string `json:"network"`
	Security    string `json:"security"`
	TLSSettings *struct {
		ServerName    string   `json:"serverName"`
		AllowInsecure bool     `json:"allowInsecure"`
		ALPN          []string `json:"alpn"`
		Fingerprint   string   `json:"fingerprint"`
	} `json:"tlsSettings"`
	RealitySettings *struct {
		ServerName  string `json:"serverName"`
		Fingerprint string `json:"fingerprint"`
		PublicKey   string `json:"publicKey"`
		ShortID     string `json:"shortId"`
		SpiderX     string `json:"spiderX"`
	} `json:"realitySettings"`
	WSSettings *struct {
		Path    string            `json:"path"`
		Headers map[string]string `json:"headers"`
	} `json:"wsSettings"`
	HTTPSettings *struct {
		Path string   `json:"path"`
		Host []string `json:"host"`
	} `json:"httpSettings"`
	XHTTPSettings *struct {
		Path string `json:"path"`
		Host string `json:"host"`
		Mode string `json:"mode"`
	} `json:"xhttpSettings"`
	GRPCSettings *struct {
		ServiceName string `json:"serviceName"`
	} `json:"grpcSettings"`
	HTTPUpgradeSettings *struct {
		Path string `json:"path"`
		Host string `json:"host"`
	} `json:"httpupgradeSettings"`
	TCPSettings *struct {
		Header struct {
			Type    string `json:"type"`
			Request struct {
				Request struct {
					Headers struct {
						Host []string `json:"Host"`
					} `json:"headers"`
					Path []string `json:"path"`
				} `json:"request"`
			} `json:"request"`
		} `json:"header"`
	} `json:"tcpSettings"`
}

type xrayOutbound struct {
	Protocol string `json:"protocol"`
	Tag      string `json:"tag"`
	Settings struct {
		Vnext []struct {
			Address string `json:"address"`
			Port    int    `json:"port"`
			Users   []struct {
				ID         string `json:"id"`
				Flow       string `json:"flow"`
				Encryption string `json:"encryption"`
			} `json:"users"`
		} `json:"vnext"`
		Servers []struct {
			Address  string `json:"address"`
			Port     int    `json:"port"`
			Password string `json:"password"`
			Method   string `json:"method"`
		} `json:"servers"`
	} `json:"settings"`
	StreamSettings *xrayStreamSettings `json:"streamSettings"`
}

func (p *Parser) parseXrayConfigObject(raw json.RawMessage) []*protocol.ProxyNode {
	var obj struct {
		Outbounds []json.RawMessage `json:"outbounds"`
	}
	if err := json.Unmarshal(raw, &obj); err != nil {
		return nil
	}
	var nodes []*protocol.ProxyNode
	for _, ob := range obj.Outbounds {
		if n := p.parseXrayOutbound(ob); n != nil {
			nodes = append(nodes, n)
		}
	}
	return nodes
}

func (p *Parser) parseXrayOutbound(raw json.RawMessage) *protocol.ProxyNode {
	var ob xrayOutbound
	if err := json.Unmarshal(raw, &ob); err != nil {
		return nil
	}

	// Skip non-proxy outbounds.
	switch ob.Protocol {
	case "freedom", "blackhole", "dns", "loopback", "metrics", "wireguard", "":
		if ob.Protocol != "wireguard" {
			return nil
		}
	}

	node := &protocol.ProxyNode{
		Type:      xrayProtocolType(ob.Protocol),
		Name:      ob.Tag,
		RawConfig: string(raw),
	}

	switch ob.Protocol {
	case "vless", "vmess":
		if len(ob.Settings.Vnext) == 0 {
			return nil
		}
		v := ob.Settings.Vnext[0]
		node.Server = v.Address
		node.Port = v.Port
		if len(v.Users) > 0 {
			node.UUID = v.Users[0].ID
			node.Flow = v.Users[0].Flow
		}
	case "trojan", "shadowsocks":
		if len(ob.Settings.Servers) == 0 {
			return nil
		}
		s := ob.Settings.Servers[0]
		node.Server = s.Address
		node.Port = s.Port
		node.Password = s.Password
		node.Security = s.Method
	case "socks", "http":
		if len(ob.Settings.Servers) == 0 {
			return nil
		}
		s := ob.Settings.Servers[0]
		node.Server = s.Address
		node.Port = s.Port
	default:
		// Unknown protocol with vnext/servers we can still expose generically.
		if len(ob.Settings.Vnext) > 0 {
			node.Server = ob.Settings.Vnext[0].Address
			node.Port = ob.Settings.Vnext[0].Port
			if len(ob.Settings.Vnext[0].Users) > 0 {
				node.UUID = ob.Settings.Vnext[0].Users[0].ID
			}
		} else if len(ob.Settings.Servers) > 0 {
			node.Server = ob.Settings.Servers[0].Address
			node.Port = ob.Settings.Servers[0].Port
		}
	}

	if node.Server == "" || node.Port <= 0 {
		return nil
	}
	if node.Name == "" {
		node.Name = fmt.Sprintf("%s-%s:%d", node.Type, node.Server, node.Port)
	}
	if ob.StreamSettings != nil {
		applyXrayStreamSettings(node, ob.StreamSettings)
	}
	node.EnsureID()
	return node
}

func applyXrayStreamSettings(node *protocol.ProxyNode, ss *xrayStreamSettings) {
	// TLS / Reality
	switch ss.Security {
	case "tls":
		tls := ss.TLSSettings
		if tls != nil {
			node.TLS = &protocol.TLSConfig{
				Enabled:    true,
				ServerName: tls.ServerName,
				Insecure:   tls.AllowInsecure,
				ALPN:       tls.ALPN,
			}
		} else {
			node.TLS = &protocol.TLSConfig{Enabled: true, ServerName: node.Server}
		}
	case "reality":
		if r := ss.RealitySettings; r != nil {
			node.TLS = &protocol.TLSConfig{
				Enabled:     true,
				ServerName:  r.ServerName,
				Fingerprint: r.Fingerprint,
				UTLS:        r.Fingerprint != "" && r.Fingerprint != "none",
				Reality: &protocol.Reality{
					Enabled:   true,
					PublicKey: r.PublicKey,
					ShortID:   r.ShortID,
				},
			}
		}
	}

	// Transport
	net := ss.Network
	if net == "" {
		net = "tcp"
	}
	tc := &protocol.TransportConfig{Type: net}
	switch net {
	case "ws":
		if w := ss.WSSettings; w != nil {
			tc.Path = w.Path
			if h, ok := w.Headers["Host"]; ok {
				tc.Host = h
			} else if h, ok := w.Headers["host"]; ok {
				tc.Host = h
			}
		}
	case "http", "h2":
		tc.Type = "http"
		if h := ss.HTTPSettings; h != nil {
			tc.Path = h.Path
			if len(h.Host) > 0 {
				tc.Host = h.Host[0]
			}
		}
	case "xhttp", "splithttp":
		tc.Type = "xhttp"
		if x := ss.XHTTPSettings; x != nil {
			tc.Path = x.Path
			tc.Host = x.Host
			tc.Mode = x.Mode
		}
	case "grpc":
		if g := ss.GRPCSettings; g != nil {
			tc.ServiceName = g.ServiceName
		}
	case "httpupgrade":
		if u := ss.HTTPUpgradeSettings; u != nil {
			tc.Path = u.Path
			tc.Host = u.Host
		}
	case "tcp":
		if t := ss.TCPSettings; t != nil && strings.EqualFold(t.Header.Type, "http") {
			// TCP + HTTP header camouflage: not expressible in sing-box (its "http"
			// transport is HTTP/2); needs an Xray-capable core.
			tc.Type = "tcp-http"
			req := t.Header.Request.Request
			if len(req.Path) > 0 {
				tc.Path = req.Path[0]
			}
			if len(req.Headers.Host) > 0 {
				tc.Host = req.Headers.Host[0]
			}
		}
	}
	node.Transport = tc
}

func xrayProtocolType(p string) protocol.ProtocolType {
	switch p {
	case "shadowsocks":
		return protocol.ProtoShadowsocks
	case "socks":
		return protocol.ProtoSocks
	case "http":
		return protocol.ProtoHTTP
	case "wireguard":
		return protocol.ProtoWireGuard
	default:
		return protocol.ProtocolType(p)
	}
}

// ---------------------------------------------------------------------------
// sing-box outbound (enriched: TLS + transport preserved)
// ---------------------------------------------------------------------------

type sbOutbound struct {
	Type       string          `json:"type"`
	Tag        string          `json:"tag"`
	Server     string          `json:"server"`
	ServerPort int             `json:"server_port"`
	UUID       string          `json:"uuid"`
	Password   string          `json:"password"`
	Method     string          `json:"method"`
	Flow       string          `json:"flow"`
	TLS        json.RawMessage `json:"tls"`
	Transport  json.RawMessage `json:"transport"`
}

type sbTLSBlock struct {
	Enabled    bool     `json:"enabled"`
	ServerName string   `json:"server_name"`
	Insecure   bool     `json:"insecure"`
	ALPN       []string `json:"alpn"`
	Reality    *struct {
		Enabled   bool   `json:"enabled"`
		PublicKey string `json:"public_key"`
		ShortID   string `json:"short_id"`
	} `json:"reality"`
}

type sbTransportBlock struct {
	Type        string              `json:"type"`
	Path        string              `json:"path"`
	Host        json.RawMessage     `json:"host"`
	ServiceName string              `json:"service_name"`
	Mode        string              `json:"mode"`
	Headers     map[string][]string `json:"headers"`
}

var sbNonProxyTypes = map[string]bool{
	"direct": true, "block": true, "dns": true, "selector": true,
	"urltest": true, "tor": true, "miner": true,
}

func (p *Parser) parseSingboxOutboundRaw(raw json.RawMessage) *protocol.ProxyNode {
	var ob sbOutbound
	if err := json.Unmarshal(raw, &ob); err != nil {
		return nil
	}
	if sbNonProxyTypes[ob.Type] || ob.Server == "" || ob.ServerPort <= 0 {
		return nil
	}

	node := &protocol.ProxyNode{
		Name:      ob.Tag,
		Type:      protocol.ProtocolType(ob.Type),
		Server:    ob.Server,
		Port:      ob.ServerPort,
		UUID:      ob.UUID,
		Password:  ob.Password,
		Security:  ob.Method,
		Flow:      ob.Flow,
		RawConfig: string(raw),
	}

	if len(ob.TLS) > 0 {
		var t sbTLSBlock
		if json.Unmarshal(ob.TLS, &t) == nil && t.Enabled {
			node.TLS = &protocol.TLSConfig{
				Enabled:    true,
				ServerName: t.ServerName,
				Insecure:   t.Insecure,
				ALPN:       t.ALPN,
			}
			if t.Reality != nil && t.Reality.Enabled {
				node.TLS.Reality = &protocol.Reality{
					Enabled:   true,
					PublicKey: t.Reality.PublicKey,
					ShortID:   t.Reality.ShortID,
				}
			}
		}
	}

	if len(ob.Transport) > 0 {
		var tr sbTransportBlock
		if json.Unmarshal(ob.Transport, &tr) == nil && tr.Type != "" {
			tc := &protocol.TransportConfig{Type: tr.Type, Path: tr.Path, ServiceName: tr.ServiceName}
			tc.Host = decodeJSONStringOrArray(tr.Host)
			if tc.Host == "" && len(tr.Headers) > 0 {
				if hs, ok := tr.Headers["Host"]; ok && len(hs) > 0 {
					tc.Host = hs[0]
				}
			}
			node.Transport = tc
		}
	}

	if node.Name == "" {
		node.Name = fmt.Sprintf("%s-%s:%d", node.Type, node.Server, node.Port)
	}
	return node
}

func decodeJSONStringOrArray(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s
	}
	var arr []string
	if err := json.Unmarshal(raw, &arr); err == nil && len(arr) > 0 {
		return arr[0]
	}
	return ""
}
