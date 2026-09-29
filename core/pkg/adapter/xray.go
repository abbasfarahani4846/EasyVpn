package adapter

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"strings"

	"easyvpn/core/pkg/protocol"

	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all" // register all Xray protocols/transports
)

// XrayCapabilities are node features only Xray-core can honor. sing-box
// mainline lacks XHTTP, VLESS post-quantum encryption and TCP HTTP-header
// camouflage (see docs/MASTER_PROMPT.md §2.1).
var XrayCapabilities = map[string]bool{
	protocol.CapXHTTP:   true,
	protocol.CapMLKEM:   true,
	protocol.CapTCPHTTP: true,
}

// NeedsXray reports whether node must be served by Xray-core: it requires a
// capability sing-box lacks and Xray has.
func NeedsXray(n *protocol.ProxyNode) bool {
	n.EnsureID()
	need := false
	for _, c := range n.Requires {
		if singboxCapabilities[c] {
			continue
		}
		if !XrayCapabilities[c] {
			return false // neither engine can run it (e.g. awg): let the builder report it
		}
		need = true
	}
	return need
}

// XraySidecar is an in-process Xray-core instance that exposes ONE node as a
// loopback SOCKS5 proxy. sing-box keeps owning TUN, DNS and routing and simply
// treats the sidecar as a SOCKS upstream, so every connection mode keeps working
// for nodes that only Xray understands.
type XraySidecar struct {
	inst *xcore.Instance
	port int
	orig *protocol.ProxyNode
}

// StartXraySidecar starts Xray-core for node on a free 127.0.0.1 port.
func StartXraySidecar(node *protocol.ProxyNode) (*XraySidecar, error) {
	port, err := freeLoopbackPort()
	if err != nil {
		return nil, err
	}
	cfg, err := BuildXrayConfig(node, port)
	if err != nil {
		return nil, err
	}
	pb, err := serial.LoadJSONConfig(bytes.NewReader(cfg))
	if err != nil {
		return nil, fmt.Errorf("xray config: %w", err)
	}
	inst, err := xcore.New(pb)
	if err != nil {
		return nil, fmt.Errorf("xray init: %w", err)
	}
	if err := inst.Start(); err != nil {
		return nil, fmt.Errorf("xray start: %w", err)
	}
	return &XraySidecar{inst: inst, port: port, orig: node}, nil
}

// Close stops the instance.
func (x *XraySidecar) Close() error {
	if x == nil || x.inst == nil {
		return nil
	}
	err := x.inst.Close()
	x.inst = nil
	return err
}

// Node returns the synthetic SOCKS node sing-box should dial. The ID and name
// are the original node's so selection/hot-switch bookkeeping keeps working.
func (x *XraySidecar) Node() *protocol.ProxyNode {
	return &protocol.ProxyNode{
		ID:     x.orig.ID,
		Name:   x.orig.Name,
		Type:   protocol.ProtoSocks,
		Server: "127.0.0.1",
		Port:   x.port,
		Group:  x.orig.Group,
	}
}

func freeLoopbackPort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

// BuildXrayConfig renders an Xray JSON config: one SOCKS inbound, one outbound.
func BuildXrayConfig(n *protocol.ProxyNode, listenPort int) ([]byte, error) {
	var out map[string]any
	stream := xrayStream(n)
	switch n.Type {
	case protocol.ProtoVLESS:
		if n.UUID == "" {
			return nil, fmt.Errorf("vless: missing uuid")
		}
		user := map[string]any{"id": n.UUID, "encryption": orDefaultStr(n.Encryption, "none")}
		if n.Flow != "" {
			user["flow"] = n.Flow
		}
		out = map[string]any{"protocol": "vless", "settings": map[string]any{
			"vnext": []any{map[string]any{"address": n.Server, "port": n.Port, "users": []any{user}}},
		}}
	case protocol.ProtoVMess:
		out = map[string]any{"protocol": "vmess", "settings": map[string]any{
			"vnext": []any{map[string]any{"address": n.Server, "port": n.Port, "users": []any{
				map[string]any{"id": n.UUID, "alterId": n.AlterID, "security": orDefaultStr(n.Security, "auto")},
			}}},
		}}
	case protocol.ProtoTrojan:
		out = map[string]any{"protocol": "trojan", "settings": map[string]any{
			"servers": []any{map[string]any{"address": n.Server, "port": n.Port, "password": n.Password}},
		}}
	default:
		return nil, fmt.Errorf("xray sidecar does not support %s", n.Type)
	}
	if stream != nil {
		out["streamSettings"] = stream
	}
	out["tag"] = "proxy"
	cfg := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{map[string]any{
			"tag": "in", "listen": "127.0.0.1", "port": listenPort, "protocol": "socks",
			"settings": map[string]any{"udp": true, "auth": "noauth"},
		}},
		"outbounds": []any{out},
	}
	return json.Marshal(cfg)
}

func xrayStream(n *protocol.ProxyNode) map[string]any {
	s := map[string]any{}
	tr := n.Transport
	network := "tcp"
	if tr != nil && tr.Type != "" {
		network = tr.Type
	}
	switch strings.ToLower(network) {
	case "tcp-http":
		s["network"] = "tcp"
		hdr := map[string]any{"type": "http"}
		req := map[string]any{"version": "1.1", "method": "GET"}
		if tr.Path != "" {
			req["path"] = []string{tr.Path}
		} else {
			req["path"] = []string{"/"}
		}
		if tr.Host != "" {
			req["headers"] = map[string]any{"Host": []string{tr.Host}}
		}
		hdr["request"] = req
		s["tcpSettings"] = map[string]any{"header": hdr}
	case "ws":
		s["network"] = "ws"
		ws := map[string]any{"path": tr.Path}
		if tr.Host != "" {
			ws["headers"] = map[string]any{"Host": tr.Host}
		}
		s["wsSettings"] = ws
	case "grpc":
		s["network"] = "grpc"
		s["grpcSettings"] = map[string]any{"serviceName": tr.ServiceName}
	case "httpupgrade":
		s["network"] = "httpupgrade"
		s["httpupgradeSettings"] = map[string]any{"path": tr.Path, "host": tr.Host}
	case "http", "h2":
		s["network"] = "h2"
		s["httpSettings"] = map[string]any{"path": tr.Path, "host": []string{tr.Host}}
	case "xhttp":
		s["network"] = "xhttp"
		x := map[string]any{"path": orDefaultStr(tr.Path, "/")}
		if tr.Host != "" {
			x["host"] = tr.Host
		}
		if tr.Mode != "" {
			x["mode"] = tr.Mode
		}
		if tr.Extra != "" {
			var extra any
			if json.Unmarshal([]byte(tr.Extra), &extra) == nil {
				x["extra"] = extra
			}
		}
		s["xhttpSettings"] = x
	default:
		s["network"] = "tcp"
	}
	if t := n.TLS; t != nil && t.Enabled {
		if t.Reality != nil && t.Reality.Enabled {
			s["security"] = "reality"
			s["realitySettings"] = map[string]any{
				"serverName": t.ServerName, "fingerprint": orDefaultStr(t.Fingerprint, "chrome"),
				"publicKey": t.Reality.PublicKey, "shortId": t.Reality.ShortID,
			}
		} else {
			s["security"] = "tls"
			tls := map[string]any{"serverName": t.ServerName, "allowInsecure": t.Insecure}
			if len(t.ALPN) > 0 {
				tls["alpn"] = t.ALPN
			}
			if t.Fingerprint != "" {
				tls["fingerprint"] = t.Fingerprint
			}
			s["tlsSettings"] = tls
		}
	}
	return s
}
