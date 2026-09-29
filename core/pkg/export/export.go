// Package export serializes nodes to share links, Clash/mihomo YAML and
// sing-box JSON (also used for the "export profile" feature).
package export

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"

	"easyvpn/core/pkg/protocol"

	"gopkg.in/yaml.v3"
)

// URI returns the share link for a node. OpenVPN nodes have no URI form; use
// OVPNFile. WireGuard nodes export as a wireguard:// link.
func URI(n *protocol.ProxyNode) (string, error) {
	name := url.QueryEscape(n.Name)
	host := hostPort(n)
	switch n.Type {
	case protocol.ProtoVLESS:
		q := tlsTransportQuery(n)
		q.Set("encryption", orStr(n.Encryption, "none"))
		if n.Flow != "" {
			q.Set("flow", n.Flow)
		}
		return fmt.Sprintf("vless://%s@%s?%s#%s", n.UUID, host, q.Encode(), name), nil
	case protocol.ProtoVMess:
		obj := map[string]any{
			"v": "2", "ps": n.Name, "add": n.Server, "port": strconv.Itoa(n.Port), "id": n.UUID,
			"aid": strconv.Itoa(n.AlterID), "scy": orStr(n.Security, "auto"), "net": "tcp", "type": "none",
		}
		if t := n.Transport; t != nil {
			obj["net"], obj["path"], obj["host"] = t.Type, t.Path, t.Host
		}
		if n.TLS != nil && n.TLS.Enabled {
			obj["tls"], obj["sni"] = "tls", n.TLS.ServerName
		}
		b, _ := json.Marshal(obj)
		return "vmess://" + base64.StdEncoding.EncodeToString(b), nil
	case protocol.ProtoTrojan:
		return fmt.Sprintf("trojan://%s@%s?%s#%s", url.QueryEscape(n.Password), host, tlsTransportQuery(n).Encode(), name), nil
	case protocol.ProtoShadowsocks:
		ui := base64.RawURLEncoding.EncodeToString([]byte(n.Security + ":" + n.Password))
		return fmt.Sprintf("ss://%s@%s#%s", ui, host, name), nil
	case protocol.ProtoHysteria2:
		q := tlsTransportQuery(n)
		if h := n.Hysteria2; h != nil && h.ObfsPassword != "" {
			q.Set("obfs", orStr(h.ObfsType, "salamander"))
			q.Set("obfs-password", h.ObfsPassword)
		}
		return fmt.Sprintf("hysteria2://%s@%s?%s#%s", url.QueryEscape(n.Password), host, q.Encode(), name), nil
	case protocol.ProtoTUIC:
		q := tlsTransportQuery(n)
		if t := n.TUIC; t != nil {
			if t.CongestionControl != "" {
				q.Set("congestion_control", t.CongestionControl)
			}
			if t.UDPRelayMode != "" {
				q.Set("udp_relay_mode", t.UDPRelayMode)
			}
		}
		return fmt.Sprintf("tuic://%s:%s@%s?%s#%s", n.UUID, url.QueryEscape(n.Password), host, q.Encode(), name), nil
	case protocol.ProtoAnyTLS:
		return fmt.Sprintf("anytls://%s@%s?%s#%s", url.QueryEscape(n.Password), host, tlsTransportQuery(n).Encode(), name), nil
	case protocol.ProtoSSH:
		return fmt.Sprintf("ssh://%s:%s@%s#%s", url.QueryEscape(n.UUID), url.QueryEscape(n.Password), host, name), nil
	case protocol.ProtoSocks:
		return fmt.Sprintf("socks5://%s:%s@%s#%s", url.QueryEscape(n.UUID), url.QueryEscape(n.Password), host, name), nil
	case protocol.ProtoHTTP:
		return fmt.Sprintf("http://%s:%s@%s#%s", url.QueryEscape(n.UUID), url.QueryEscape(n.Password), host, name), nil
	case protocol.ProtoWireGuard:
		return WGQuick(n)
	}
	return "", fmt.Errorf("no URI form for %s (use the file export)", n.Type)
}

func hostPort(n *protocol.ProxyNode) string {
	h := n.Server
	if strings.Contains(h, ":") && !strings.HasPrefix(h, "[") {
		h = "[" + h + "]"
	}
	return h + ":" + strconv.Itoa(n.Port)
}

func orStr(v, d string) string {
	if v == "" {
		return d
	}
	return v
}

func tlsTransportQuery(n *protocol.ProxyNode) url.Values {
	q := url.Values{}
	if t := n.TLS; t != nil && t.Enabled {
		if t.Reality != nil && t.Reality.Enabled {
			q.Set("security", "reality")
			q.Set("pbk", t.Reality.PublicKey)
			if t.Reality.ShortID != "" {
				q.Set("sid", t.Reality.ShortID)
			}
		} else {
			q.Set("security", "tls")
		}
		if t.ServerName != "" {
			q.Set("sni", t.ServerName)
		}
		if t.Fingerprint != "" {
			q.Set("fp", t.Fingerprint)
		}
		if len(t.ALPN) > 0 {
			q.Set("alpn", strings.Join(t.ALPN, ","))
		}
		if t.Insecure {
			q.Set("insecure", "1")
		}
	}
	if tr := n.Transport; tr != nil && tr.Type != "" {
		q.Set("type", tr.Type)
		if tr.Path != "" {
			q.Set("path", tr.Path)
		}
		if tr.Host != "" {
			q.Set("host", tr.Host)
		}
		if tr.ServiceName != "" {
			q.Set("serviceName", tr.ServiceName)
		}
		if tr.Mode != "" {
			q.Set("mode", tr.Mode)
		}
		if tr.Extra != "" {
			q.Set("extra", tr.Extra)
		}
	}
	return q
}

// URIList exports many nodes, one link per line; nodes without a URI form are
// reported in skipped.
func URIList(nodes []*protocol.ProxyNode) (out string, skipped []string) {
	var lines []string
	for _, n := range nodes {
		u, err := URI(n)
		if err != nil {
			skipped = append(skipped, n.Name)
			continue
		}
		lines = append(lines, u)
	}
	return strings.Join(lines, "\n"), skipped
}

// WGQuick renders a wg-quick style config for a WireGuard node.
func WGQuick(n *protocol.ProxyNode) (string, error) {
	w := n.WireGuard
	if w == nil {
		return "", fmt.Errorf("not a wireguard node")
	}
	var b strings.Builder
	b.WriteString("[Interface]\n")
	fmt.Fprintf(&b, "PrivateKey = %s\nAddress = %s\n", w.PrivateKey, strings.Join(w.LocalAddress, ", "))
	if w.MTU > 0 {
		fmt.Fprintf(&b, "MTU = %d\n", w.MTU)
	}
	for k, v := range w.AWG {
		fmt.Fprintf(&b, "%s = %s\n", strings.ToUpper(k[:1])+k[1:], v)
	}
	b.WriteString("\n[Peer]\n")
	fmt.Fprintf(&b, "PublicKey = %s\n", w.PublicKey)
	if w.PreSharedKey != "" {
		fmt.Fprintf(&b, "PresharedKey = %s\n", w.PreSharedKey)
	}
	fmt.Fprintf(&b, "AllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = %s\n", hostPort(n))
	return b.String(), nil
}

// ClashYAML renders a Clash/mihomo config with a proxies list and one select group.
func ClashYAML(nodes []*protocol.ProxyNode) (string, error) {
	var proxies []map[string]any
	var names []string
	for _, n := range nodes {
		p := clashProxy(n)
		if p == nil {
			continue
		}
		proxies = append(proxies, p)
		names = append(names, n.Name)
	}
	doc := map[string]any{
		"mixed-port": 7890, "allow-lan": false, "mode": "rule", "log-level": "info",
		"proxies": proxies,
		"proxy-groups": []map[string]any{
			{"name": "PROXY", "type": "select", "proxies": names},
		},
		"rules": []string{"MATCH,PROXY"},
	}
	b, err := yaml.Marshal(doc)
	return string(b), err
}

func clashTLS(p map[string]any, n *protocol.ProxyNode) {
	t := n.TLS
	if t == nil || !t.Enabled {
		return
	}
	p["tls"] = true
	if t.ServerName != "" {
		p["servername"] = t.ServerName
	}
	if t.Insecure {
		p["skip-cert-verify"] = true
	}
	if len(t.ALPN) > 0 {
		p["alpn"] = t.ALPN
	}
	if t.Fingerprint != "" {
		p["client-fingerprint"] = t.Fingerprint
	}
	if t.Reality != nil && t.Reality.Enabled {
		p["reality-opts"] = map[string]any{"public-key": t.Reality.PublicKey, "short-id": t.Reality.ShortID}
	}
}

func clashNet(p map[string]any, n *protocol.ProxyNode) {
	tr := n.Transport
	if tr == nil {
		return
	}
	switch tr.Type {
	case "ws":
		p["network"] = "ws"
		opts := map[string]any{"path": tr.Path}
		if tr.Host != "" {
			opts["headers"] = map[string]any{"Host": tr.Host}
		}
		p["ws-opts"] = opts
	case "grpc":
		p["network"] = "grpc"
		p["grpc-opts"] = map[string]any{"grpc-service-name": tr.ServiceName}
	case "http", "h2":
		p["network"] = "h2"
		p["h2-opts"] = map[string]any{"path": tr.Path, "host": []string{tr.Host}}
	case "httpupgrade":
		p["network"] = "ws"
		p["ws-opts"] = map[string]any{"path": tr.Path, "v2ray-http-upgrade": true}
	case "xhttp":
		p["network"] = "xhttp"
		p["xhttp-opts"] = map[string]any{"path": tr.Path, "host": tr.Host, "mode": tr.Mode}
	}
}

func clashProxy(n *protocol.ProxyNode) map[string]any {
	base := map[string]any{"name": n.Name, "server": n.Server, "port": n.Port}
	switch n.Type {
	case protocol.ProtoVLESS:
		base["type"], base["uuid"], base["udp"] = "vless", n.UUID, true
		if n.Flow != "" {
			base["flow"] = n.Flow
		}
		clashTLS(base, n)
		clashNet(base, n)
	case protocol.ProtoVMess:
		base["type"], base["uuid"], base["alterId"], base["cipher"], base["udp"] = "vmess", n.UUID, n.AlterID, orStr(n.Security, "auto"), true
		clashTLS(base, n)
		clashNet(base, n)
	case protocol.ProtoTrojan:
		base["type"], base["password"], base["udp"] = "trojan", n.Password, true
		clashTLS(base, n)
		if n.TLS != nil && n.TLS.ServerName != "" {
			base["sni"] = n.TLS.ServerName
		}
		clashNet(base, n)
	case protocol.ProtoShadowsocks:
		base["type"], base["cipher"], base["password"], base["udp"] = "ss", n.Security, n.Password, true
	case protocol.ProtoHysteria2:
		base["type"], base["password"] = "hysteria2", n.Password
		if n.TLS != nil {
			base["sni"] = n.TLS.ServerName
			base["skip-cert-verify"] = n.TLS.Insecure
		}
		if h := n.Hysteria2; h != nil && h.ObfsPassword != "" {
			base["obfs"], base["obfs-password"] = orStr(h.ObfsType, "salamander"), h.ObfsPassword
		}
	case protocol.ProtoTUIC:
		base["type"], base["uuid"], base["password"] = "tuic", n.UUID, n.Password
		if n.TLS != nil {
			base["sni"] = n.TLS.ServerName
		}
		if t := n.TUIC; t != nil {
			base["congestion-controller"], base["udp-relay-mode"] = t.CongestionControl, t.UDPRelayMode
		}
	case protocol.ProtoAnyTLS:
		base["type"], base["password"] = "anytls", n.Password
		if n.TLS != nil {
			base["sni"] = n.TLS.ServerName
		}
	case protocol.ProtoWireGuard:
		w := n.WireGuard
		if w == nil {
			return nil
		}
		base["type"], base["private-key"], base["public-key"], base["udp"] = "wireguard", w.PrivateKey, w.PublicKey, true
		for _, a := range w.LocalAddress {
			if strings.Contains(a, ":") {
				base["ipv6"] = strings.Split(a, "/")[0]
			} else {
				base["ip"] = strings.Split(a, "/")[0]
			}
		}
	case protocol.ProtoSocks:
		base["type"], base["username"], base["password"] = "socks5", n.UUID, n.Password
	case protocol.ProtoHTTP:
		base["type"], base["username"], base["password"] = "http", n.UUID, n.Password
	default:
		return nil
	}
	return base
}
