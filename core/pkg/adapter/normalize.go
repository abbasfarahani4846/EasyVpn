package adapter

import (
	"easyvpn/core/pkg/config"
	"easyvpn/core/pkg/protocol"
)

// NormalizeNode refreshes a node imported from Xray JSON from its original
// outbound, keeping identity (ID, name, group). Safe to call repeatedly.
func NormalizeNode(n *protocol.ProxyNode) {
	if n == nil || n.RawConfig == "" {
		return
	}
	fresh := config.ReparseXrayOutbound(n.RawConfig)
	if fresh == nil {
		return
	}
	id, name, group, lat := n.ID, n.Name, n.Group, n.LatencyMs
	*n = *fresh
	n.ID, n.Name, n.Group, n.LatencyMs = id, name, group, lat
	n.Requires = n.ComputeRequires()
}
