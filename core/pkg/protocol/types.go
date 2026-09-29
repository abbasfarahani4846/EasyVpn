// Package protocol defines the internal, engine-agnostic proxy node model.
// This model is the single source of truth shared between the Go core and the
// Flutter app (mirrored by lib/core/bridge/messages.dart). Node IDs are
// content hashes so favorites/aliases survive subscription re-imports.
package protocol

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

type ProtocolType string

const (
	ProtoVLESS       ProtocolType = "vless"
	ProtoVMess       ProtocolType = "vmess"
	ProtoTrojan      ProtocolType = "trojan"
	ProtoShadowsocks ProtocolType = "shadowsocks"
	ProtoSocks       ProtocolType = "socks"
	ProtoHTTP        ProtocolType = "http"
	ProtoWireGuard   ProtocolType = "wireguard"
	ProtoHysteria2   ProtocolType = "hysteria2"
	ProtoTUIC        ProtocolType = "tuic"
	ProtoOpenVPN     ProtocolType = "openvpn"
)

// TLSConfig holds outbound TLS / REALITY settings.
type TLSConfig struct {
	Enabled     bool     `json:"enabled"`
	ServerName  string   `json:"server_name,omitempty"`
	Insecure    bool     `json:"insecure,omitempty"`
	ALPN        []string `json:"alpn,omitempty"`
	Reality     *Reality `json:"reality,omitempty"`
	UTLS        bool     `json:"utls,omitempty"`
	Fingerprint string   `json:"fingerprint,omitempty"`
}

// Reality holds REALITY-specific fields.
type Reality struct {
	Enabled   bool   `json:"enabled"`
	PublicKey string `json:"public_key"`
	ShortID   string `json:"short_id,omitempty"`
}

// TransportConfig holds V2Ray transport (ws/grpc/httpupgrade/http) settings.
type TransportConfig struct {
	Type        string            `json:"type"` // tcp, ws, grpc, httpupgrade, http, quic
	Path        string            `json:"path,omitempty"`
	Host        string            `json:"host,omitempty"`
	ServiceName string            `json:"service_name,omitempty"`
	Headers     map[string]string `json:"headers,omitempty"`
}

// WireGuardConfig holds WireGuard endpoint settings.
type WireGuardConfig struct {
	PrivateKey   string   `json:"private_key"`
	PublicKey    string   `json:"public_key"`
	PreSharedKey string   `json:"pre_shared_key,omitempty"`
	LocalAddress []string `json:"local_address"`
	MTU          int      `json:"mtu,omitempty"`
	Reserved     []uint8  `json:"reserved,omitempty"`
}

// Hysteria2Config holds Hysteria2-specific settings.
type Hysteria2Config struct {
	ObfsPassword string `json:"obfs_password,omitempty"`
	ObfsType     string `json:"obfs_type,omitempty"`
	UpMbps       int    `json:"up_mbps,omitempty"`
	DownMbps     int    `json:"down_mbps,omitempty"`
}

// TUICConfig holds TUIC-specific settings.
type TUICConfig struct {
	CongestionControl string `json:"congestion_control,omitempty"`
	UDPRelayMode      string `json:"udp_relay_mode,omitempty"`
}

// ProxyNode is the universal internal node representation.
type ProxyNode struct {
	ID         string           `json:"id"`
	Name       string           `json:"name"`
	Type       ProtocolType     `json:"type"`
	Server     string           `json:"server"`
	Port       int              `json:"port"`
	UUID       string           `json:"uuid,omitempty"`
	Password   string           `json:"password,omitempty"`
	Security   string           `json:"security,omitempty"` // vmess cipher / ss method
	Encryption string           `json:"encryption,omitempty"`
	Flow       string           `json:"flow,omitempty"`
	AlterID    int              `json:"alter_id,omitempty"`
	TLS        *TLSConfig       `json:"tls,omitempty"`
	Transport  *TransportConfig `json:"transport,omitempty"`
	WireGuard  *WireGuardConfig `json:"wireguard,omitempty"`
	Hysteria2  *Hysteria2Config `json:"hysteria2,omitempty"`
	TUIC       *TUICConfig      `json:"tuic,omitempty"`

	LatencyMs int64  `json:"latency_ms"`
	Group     string `json:"group,omitempty"`
	// RawConfig preserves the original URI/YAML fragment for export fidelity.
	RawConfig string `json:"raw_config,omitempty"`
}

// IdentityFields returns the fields that make a node functionally unique.
// Favorites and aliases must survive subscription refreshes, so the node ID
// is derived from these fields rather than the raw line (names change often).
func (n *ProxyNode) IdentityFields() []string {
	fields := []string{
		string(n.Type), strings.ToLower(n.Server), itoa(n.Port),
		n.UUID, n.Password, n.Security, n.Encryption, n.Flow,
	}
	if n.TLS != nil {
		fields = append(fields,
			boolStr(n.TLS.Enabled), n.TLS.ServerName,
			boolStr(n.TLS.Insecure), strings.Join(n.TLS.ALPN, ","))
		if n.TLS.Reality != nil && n.TLS.Reality.Enabled {
			fields = append(fields, n.TLS.Reality.PublicKey, n.TLS.Reality.ShortID)
		}
	}
	if n.Transport != nil {
		fields = append(fields, n.Transport.Type, n.Transport.Path, n.Transport.Host, n.Transport.ServiceName)
	}
	if n.WireGuard != nil {
		fields = append(fields, n.WireGuard.PrivateKey, n.WireGuard.PublicKey,
			strings.Join(n.WireGuard.LocalAddress, ","))
	}
	if n.Hysteria2 != nil {
		fields = append(fields, n.Hysteria2.ObfsPassword)
	}
	return fields
}

// ComputeID derives a stable content-hash ID for the node.
func (n *ProxyNode) ComputeID() string {
	h := sha256.Sum256([]byte(strings.Join(n.IdentityFields(), "|")))
	return hex.EncodeToString(h[:16]) // 128-bit, compact
}

// EnsureID fills the ID field if it is empty.
func (n *ProxyNode) EnsureID() {
	if n.ID == "" {
		n.ID = n.ComputeID()
	}
}

func boolStr(b bool) string {
	if b {
		return "1"
	}
	return "0"
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [20]byte
	pos := len(b)
	for i > 0 {
		pos--
		b[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		b[pos] = '-'
	}
	return string(b[pos:])
}

// SupportedProtocols returns protocol types the Go core can actually dial.
// OpenVPN is listed for completeness; its endpoint is compiled in via build tags.
func SupportedProtocols() []ProtocolType {
	return []ProtocolType{
		ProtoVLESS, ProtoVMess, ProtoTrojan, ProtoShadowsocks,
		ProtoSocks, ProtoHTTP, ProtoHysteria2, ProtoTUIC, ProtoWireGuard, ProtoOpenVPN,
	}
}
