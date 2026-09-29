package config

import (
	"fmt"
	"strconv"
	"strings"

	"easyvpn/core/pkg/protocol"
)

// ParseWGQuick converts a wg-quick .conf (Interface + first Peer) into a node.
// AmneziaWG obfuscation keys (Jc, Jmin, Jmax, S1..S4, H1..H4, I1..I5) are kept
// in WireGuardConfig.AWG which adds the "awg" capability.
func ParseWGQuick(content, name string) (*protocol.ProxyNode, error) {
	wg := &protocol.WireGuardConfig{}
	var endpoint string
	section := ""
	awgKeys := map[string]bool{"jc": true, "jmin": true, "jmax": true, "s1": true, "s2": true, "s3": true, "s4": true,
		"h1": true, "h2": true, "h3": true, "h4": true, "i1": true, "i2": true, "i3": true, "i4": true, "i5": true}
	peers := 0
	for _, raw := range strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n") {
		line := strings.TrimSpace(raw)
		if i := strings.Index(line, "#"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") {
			section = strings.ToLower(strings.Trim(line, "[]"))
			if section == "peer" {
				peers++
			}
			continue
		}
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}
		k, v := strings.ToLower(strings.TrimSpace(kv[0])), strings.TrimSpace(kv[1])
		switch section {
		case "interface":
			switch {
			case k == "privatekey":
				wg.PrivateKey = v
			case k == "address":
				for _, a := range strings.Split(v, ",") {
					wg.LocalAddress = append(wg.LocalAddress, strings.TrimSpace(a))
				}
			case k == "mtu":
				wg.MTU, _ = strconv.Atoi(v)
			case awgKeys[k]:
				if wg.AWG == nil {
					wg.AWG = map[string]string{}
				}
				wg.AWG[k] = v
			}
		case "peer":
			if peers > 1 {
				continue // only the first peer is used
			}
			switch k {
			case "publickey":
				wg.PublicKey = v
			case "presharedkey":
				wg.PreSharedKey = v
			case "endpoint":
				endpoint = v
			}
		}
	}
	if wg.PrivateKey == "" || wg.PublicKey == "" || endpoint == "" {
		return nil, fmt.Errorf("wireguard: incomplete config (need PrivateKey, PublicKey, Endpoint)")
	}
	host, port := endpoint, 51820
	if i := strings.LastIndex(endpoint, ":"); i > 0 {
		host = strings.Trim(endpoint[:i], "[]")
		if p, err := strconv.Atoi(endpoint[i+1:]); err == nil {
			port = p
		}
	}
	n := &protocol.ProxyNode{Name: name, Type: protocol.ProtoWireGuard, Server: host, Port: port, WireGuard: wg}
	if n.Name == "" {
		n.Name = "WireGuard " + host
	}
	n.EnsureID()
	return n, nil
}

// LooksLikeWGQuick reports whether content is a wg-quick config.
func LooksLikeWGQuick(content string) bool {
	return strings.Contains(content, "[Interface]") && strings.Contains(content, "[Peer]")
}
