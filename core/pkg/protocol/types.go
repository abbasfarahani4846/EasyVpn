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
	ProtoAnyTLS      ProtocolType = "anytls"
	ProtoSSH         ProtocolType = "ssh"
)

// Capability names describe engine features a node needs. A node lists them in
// ProxyNode.Requires and the engine picks a CoreAdapter that supports all.
const (
	CapXHTTP   = "xhttp"   // VLESS XHTTP / SplitHTTP transport
	CapTCPHTTP = "tcphttp" // TCP with HTTP header camouflage
	CapMLKEM   = "mlkem"   // VLESS post-quantum encryption
	CapAWG     = "awg"     // AmneziaWG obfuscation
	CapIKEv2   = "ikev2"   // platform IKEv2/IPsec
	CapOpenVPN = "openvpn"
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
	// Anti-DPI options (Hiddify "TLS tricks").
	Fragment       bool     `json:"fragment,omitempty"`
	RecordFragment bool     `json:"record_fragment,omitempty"`
	ECH            bool     `json:"ech,omitempty"`
	ECHConfig      []string `json:"ech_config,omitempty"`
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
	Method      string            `json:"method,omitempty"`
	// XHTTP (not supported by mainline sing-box; requires an Xray-capable core).
	Mode  string `json:"mode,omitempty"`
	Extra string `json:"extra,omitempty"` // raw JSON of the xhttp "extra" object
}

// MuxConfig configures sing-box multiplexing for an outbound.
type MuxConfig struct {
	Enabled        bool   `json:"enabled"`
	Protocol       string `json:"protocol,omitempty"` // smux, yamux, h2mux
	MaxConnections int    `json:"max_connections,omitempty"`
	Padding        bool   `json:"padding,omitempty"`
}

// OpenVPNConfig is the subset of an .ovpn profile mapped onto sing-box's
// `openvpn-client` endpoint (see config.ParseOVPN).
type OpenVPNConfig struct {
	Mode                string       `json:"mode,omitempty"` // tls | static_key
	Network             string       `json:"network,omitempty"`
	Remotes             []OVPNRemote `json:"remotes,omitempty"`
	RemoteRandom        bool         `json:"remote_random,omitempty"`
	Username            string       `json:"username,omitempty"`
	Password            string       `json:"password,omitempty"`
	CA                  string       `json:"ca,omitempty"`   // PEM
	Cert                string       `json:"cert,omitempty"` // PEM
	Key                 string       `json:"key,omitempty"`  // PEM
	StaticKey           string       `json:"static_key,omitempty"`
	KeyDirection        string       `json:"key_direction,omitempty"`
	ControlWrapType     string       `json:"control_wrap_type,omitempty"` // tls_auth|tls_crypt|tls_crypt_v2
	ControlWrapKey      string       `json:"control_wrap_key,omitempty"`
	ControlWrapDir      string       `json:"control_wrap_direction,omitempty"`
	Cipher              string       `json:"cipher,omitempty"`
	DataCiphers         []string     `json:"data_ciphers,omitempty"`
	DataCiphersFallback string       `json:"data_ciphers_fallback,omitempty"`
	Auth                string       `json:"auth,omitempty"`
	Compression         string       `json:"compression,omitempty"`
	CompressionLZO      string       `json:"compression_lzo,omitempty"`
	RemoteCertTLS       string       `json:"remote_cert_tls,omitempty"`
	ServerName          string       `json:"server_name,omitempty"`
	RedirectGateway     bool         `json:"redirect_gateway,omitempty"`
	RedirectFlags       []string     `json:"redirect_gateway_flags,omitempty"`
	RouteNoPull         bool         `json:"route_no_pull,omitempty"`
	Routes              []string     `json:"routes,omitempty"`
	MSSFix              int          `json:"mss_fix,omitempty"`
	Fragment            int          `json:"fragment,omitempty"`
	PingRestartSec      int          `json:"ping_restart_sec,omitempty"`
	RenegSec            int          `json:"reneg_sec,omitempty"`
	Topology            string       `json:"topology,omitempty"`
	Warnings            []string     `json:"warnings,omitempty"`
}

// OVPNRemote is one `remote` directive.
type OVPNRemote struct {
	Host    string `json:"host"`
	Port    int    `json:"port"`
	Network string `json:"network,omitempty"` // udp|tcp
}

// SSHConfig holds SSH outbound credentials.
type SSHConfig struct {
	PrivateKey string   `json:"private_key,omitempty"`
	Passphrase string   `json:"passphrase,omitempty"`
	HostKeys   []string `json:"host_keys,omitempty"`
}

// WireGuardConfig holds WireGuard endpoint settings.
type WireGuardConfig struct {
	PrivateKey   string   `json:"private_key"`
	PublicKey    string   `json:"public_key"`
	PreSharedKey string   `json:"pre_shared_key,omitempty"`
	LocalAddress []string `json:"local_address"`
	MTU          int      `json:"mtu,omitempty"`
	Reserved     []uint8  `json:"reserved,omitempty"`
	// AmneziaWG obfuscation parameters; presence adds the "awg" capability.
	AWG map[string]string `json:"awg,omitempty"`
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
	Mux        *MuxConfig       `json:"mux,omitempty"`
	OpenVPN    *OpenVPNConfig   `json:"openvpn,omitempty"`
	SSH        *SSHConfig       `json:"ssh,omitempty"`
	// Requires lists engine capabilities this node needs (CapXHTTP, ...).
	Requires []string `json:"requires,omitempty"`

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
	if n.Transport != nil {
		fields = append(fields, n.Transport.Mode)
	}
	if n.OpenVPN != nil {
		for _, r := range n.OpenVPN.Remotes {
			fields = append(fields, r.Host, itoa(r.Port), r.Network)
		}
		fields = append(fields, n.OpenVPN.Username, n.OpenVPN.Mode)
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
	n.EnsureRequires()
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

// ComputeRequires derives the capability list from the node's fields.
func (n *ProxyNode) ComputeRequires() []string {
	var out []string
	if n.Transport != nil && strings.EqualFold(n.Transport.Type, "xhttp") {
		out = append(out, CapXHTTP)
	}
	if n.Transport != nil && strings.EqualFold(n.Transport.Type, "tcp-http") {
		out = append(out, CapTCPHTTP)
	}
	if strings.HasPrefix(strings.ToLower(n.Encryption), "mlkem") {
		out = append(out, CapMLKEM)
	}
	if n.WireGuard != nil && len(n.WireGuard.AWG) > 0 {
		out = append(out, CapAWG)
	}
	return out
}

// EnsureRequires fills Requires when empty.
func (n *ProxyNode) EnsureRequires() {
	if len(n.Requires) == 0 {
		n.Requires = n.ComputeRequires()
	}
}

// SupportedProtocols returns protocol types the sing-box adapter can dial.
func SupportedProtocols() []ProtocolType {
	return []ProtocolType{
		ProtoVLESS, ProtoVMess, ProtoTrojan, ProtoShadowsocks,
		ProtoSocks, ProtoHTTP, ProtoHysteria2, ProtoTUIC, ProtoWireGuard,
		ProtoOpenVPN, ProtoAnyTLS, ProtoSSH,
	}
}
