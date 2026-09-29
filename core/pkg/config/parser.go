// Package config implements the universal configuration parser: raw proxy
// URIs, Base64 subscription payloads, Clash/mihomo YAML and sing-box JSON.
// Everything maps into the internal protocol.ProxyNode model.
package config

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

// ParseResult carries parsed nodes plus non-fatal warnings for the UI.
type ParseResult struct {
	Nodes    []*protocol.ProxyNode `json:"nodes"`
	Warnings []string              `json:"warnings,omitempty"`
}

type Parser struct{}

func NewParser() *Parser { return &Parser{} }

// ParseContent auto-detects the payload format and returns parsed nodes.
// Detection order: JSON -> YAML -> Base64 -> line-by-line URIs.
func (p *Parser) ParseContent(content string) ([]*protocol.ProxyNode, error) {
	res, err := p.ParseWithWarnings(content)
	if err != nil {
		return nil, err
	}
	return res.Nodes, nil
}

func (p *Parser) ParseWithWarnings(content string) (*ParseResult, error) {
	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		return nil, fmt.Errorf("empty content")
	}
	res := &ParseResult{}

	// 1. JSON payloads: sing-box outbounds, Xray/v2ray configs, or arrays.
	if strings.HasPrefix(trimmed, "{") || strings.HasPrefix(trimmed, "[") {
		if nodes, err := p.parseJSONConfigs(trimmed); err == nil && len(nodes) > 0 {
			res.Nodes = nodes
			res.Warnings = append(res.Warnings, "format: json")
			return res, nil
		}
	}

	// 2. YAML payloads: Clash / mihomo `proxies:` list.
	if strings.Contains(trimmed, "proxies:") {
		if nodes, warns, ok := parseClashYAML([]byte(trimmed)); ok && len(nodes) > 0 {
			res.Nodes = nodes
			res.Warnings = warns
			return res, nil
		}
	}

	// 3. Base64-encoded subscription payloads (up to two layers).
	if looksLikeBase64(trimmed) {
		if decoded, err := decodeBase64Loose(trimmed); err == nil {
			if inner, err := p.ParseWithWarnings(string(decoded)); err == nil && len(inner.Nodes) > 0 {
				inner.Warnings = append(inner.Warnings, "format: base64")
				return inner, nil
			}
		}
	}

	// 4. Plain URI list, one link per line.
	lines := strings.Split(strings.ReplaceAll(trimmed, "\r\n", "\n"), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") {
			continue
		}
		node, err := p.ParseURI(line)
		if err != nil {
			res.Warnings = append(res.Warnings, "skip: "+err.Error())
			continue
		}
		res.Nodes = append(res.Nodes, node)
	}
	if len(res.Nodes) == 0 {
		return nil, fmt.Errorf("no supported nodes found in content")
	}
	return res, nil
}

func looksLikeBase64(s string) bool {
	if strings.ContainsAny(s, "://{} \n\t") {
		return false
	}
	if len(s) < 16 {
		return false
	}
	for _, r := range s {
		switch {
		case r >= 'A' && r <= 'Z', r >= 'a' && r <= 'z', r >= '0' && r <= '9',
			r == '+', r == '/', r == '-', r == '_', r == '=':
		default:
			return false
		}
	}
	return true
}

// decodeBase64Loose accepts std/URL alphabets with or without padding.
func decodeBase64Loose(s string) ([]byte, error) {
	s = strings.Map(func(r rune) rune {
		switch r {
		case '\r', '\n', ' ', '\t':
			return -1
		}
		return r
	}, s)
	if dec, err := base64.StdEncoding.DecodeString(s); err == nil {
		return dec, nil
	}
	if dec, err := base64.URLEncoding.DecodeString(s); err == nil {
		return dec, nil
	}
	if dec, err := base64.RawStdEncoding.DecodeString(s); err == nil {
		return dec, nil
	}
	return base64.RawURLEncoding.DecodeString(s)
}

// ParseURI parses a single proxy share link.
func (p *Parser) ParseURI(rawURI string) (*protocol.ProxyNode, error) {
	rawURI = strings.TrimSpace(rawURI)
	i := strings.IndexAny(rawURI, "#")
	var fragment string
	if i >= 0 {
		fragment = rawURI[i+1:]
		rawURI = rawURI[:i]
	}
	schemeIdx := strings.Index(rawURI, "://")
	if schemeIdx <= 0 {
		return nil, fmt.Errorf("not a supported URI")
	}
	scheme := strings.ToLower(rawURI[:schemeIdx])
	body := rawURI[schemeIdx+3:]

	switch scheme {
	case "vless":
		return parseVLESS(body, fragment)
	case "trojan":
		return parseTrojan(body, fragment)
	case "ss":
		return parseShadowsocks(body, fragment)
	case "hysteria2", "hy2":
		return parseHysteria2(body, fragment)
	case "tuic":
		return parseTUIC(body, fragment)
	case "socks", "socks5":
		return parseSocks(body, fragment)
	case "http", "https":
		return parseHTTPProxy(body, fragment, scheme == "https")
	case "vmess":
		// vmess links carry the name inside the base64 JSON body.
		return parseVMess(rawURI)
	case "wireguard":
		return parseWireGuard(rawURI, fragment)
	default:
		return nil, fmt.Errorf("unsupported scheme: %s", scheme)
	}
}

func safeUnescape(s string) string {
	if v, err := url.QueryUnescape(s); err == nil {
		return v
	}
	return s
}

func displayName(fragment, fallback string, u *url.URL) string {
	if fragment != "" {
		return safeUnescape(fragment)
	}
	if u != nil && u.Host != "" {
		return fmt.Sprintf("%s-%s", fallback, u.Host)
	}
	return fallback
}

func parseVLESS(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("vless://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" || u.User == nil || u.User.Username() == "" {
		return nil, fmt.Errorf("invalid vless URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid vless port: %w", err)
	}
	q := u.Query()

	node := &protocol.ProxyNode{
		Name:   displayName(fragment, "VLESS", u),
		Type:   protocol.ProtoVLESS,
		Server: u.Hostname(),
		Port:   port,
		UUID:   u.User.Username(),
		Flow:   q.Get("flow"),
	}
	node.Encryption = q.Get("encryption")
	if node.Encryption == "" {
		node.Encryption = "none"
	}
	node.TLS = parseTLSQuery(q)
	node.Transport = parseTransportQuery(q)
	node.EnsureID()
	return node, nil
}

// parseTLSQuery extracts tls/reality parameters from URI query values.
func parseTLSQuery(q url.Values) *protocol.TLSConfig {
	security := strings.ToLower(q.Get("security"))
	if security == "" {
		security = "none"
	}
	enabled := security == "tls" || security == "reality" || q.Get("sni") != ""
	if !enabled {
		return nil
	}
	tls := &protocol.TLSConfig{
		Enabled:     true,
		ServerName:  q.Get("sni"),
		Insecure:    isTruthy(q.Get("allowInsecure")) || isTruthy(q.Get("insecure")),
		ALPN:        splitCSV(q.Get("alpn")),
		UTLS:        q.Get("fp") != "" && q.Get("fp") != "none",
		Fingerprint: q.Get("fp"),
	}
	if security == "reality" {
		tls.Reality = &protocol.Reality{
			Enabled:   true,
			PublicKey: q.Get("pbk"),
			ShortID:   q.Get("sid"),
		}
	}
	return tls
}

func parseTransportQuery(q url.Values) *protocol.TransportConfig {
	t := strings.ToLower(q.Get("type"))
	switch t {
	case "", "tcp", "raw":
		return nil
	case "ws", "grpc", "httpupgrade", "http", "quic":
		tc := &protocol.TransportConfig{Type: t, Path: q.Get("path"), Host: q.Get("host")}
		if t == "grpc" {
			tc.ServiceName = q.Get("serviceName")
			if tc.ServiceName == "" {
				tc.ServiceName = q.Get("path")
			}
		}
		if h := q.Get("host"); h != "" && tc.Host == "" {
			tc.Host = h
		}
		return tc
	default:
		return nil
	}
}

func parseTrojan(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("trojan://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" || u.User == nil {
		return nil, fmt.Errorf("invalid trojan URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid trojan port: %w", err)
	}
	q := u.Query()
	node := &protocol.ProxyNode{
		Name:      displayName(fragment, "Trojan", u),
		Type:      protocol.ProtoTrojan,
		Server:    u.Hostname(),
		Port:      port,
		Password:  u.User.Username(),
		TLS:       parseTLSQuery(q),
		Transport: parseTransportQuery(q),
	}
	if node.TLS == nil {
		// Trojan is TLS-only.
		node.TLS = &protocol.TLSConfig{Enabled: true, ServerName: u.Hostname()}
	}
	node.EnsureID()
	return node, nil
}

func parseShadowsocks(body, fragment string) (*protocol.ProxyNode, error) {
	// SIP002: ss://base64(method:pass)@host:port#name  or  ss://method:pass@host:port#name
	u, err := url.Parse("ss://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" {
		return nil, fmt.Errorf("invalid ss URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid ss port: %w", err)
	}
	node := &protocol.ProxyNode{
		Name:   displayName(fragment, "Shadowsocks", u),
		Type:   protocol.ProtoShadowsocks,
		Server: u.Hostname(),
		Port:   port,
	}
	if u.User != nil {
		userInfo := u.User.Username()
		pass, _ := u.User.Password()
		if pass == "" {
			// method:pass may be base64-encoded as a whole.
			if decoded, err := decodeBase64Loose(userInfo); err == nil {
				if idx := strings.IndexByte(string(decoded), ':'); idx > 0 {
					userInfo = string(decoded[:idx])
					pass = string(decoded[idx+1:])
				}
			}
		}
		node.Security = userInfo
		node.Password = pass
	}
	plugin := u.Query().Get("plugin")
	if plugin != "" {
		node.RawConfig = "plugin:" + plugin
	}
	node.EnsureID()
	return node, nil
}

func parseHysteria2(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("hysteria2://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" {
		return nil, fmt.Errorf("invalid hysteria2 URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		if port == 0 {
			port = 443
		} else {
			return nil, fmt.Errorf("invalid hysteria2 port: %w", err)
		}
	}
	q := u.Query()
	pass := ""
	if u.User != nil {
		pass = u.User.Username()
		if p2, ok := u.User.Password(); ok {
			pass = pass + ":" + p2
		}
	}
	node := &protocol.ProxyNode{
		Name:     displayName(fragment, "Hysteria2", u),
		Type:     protocol.ProtoHysteria2,
		Server:   u.Hostname(),
		Port:     port,
		Password: pass,
		TLS: &protocol.TLSConfig{
			Enabled:     true,
			ServerName:  q.Get("sni"),
			Insecure:    isTruthy(q.Get("insecure")) || isTruthy(q.Get("allowInsecure")),
			Fingerprint: q.Get("fp"),
		},
	}
	if obfsPass := q.Get("obfs-password"); obfsPass != "" {
		node.Hysteria2 = &protocol.Hysteria2Config{
			ObfsType:     orDefault(q.Get("obfs"), "salamander"),
			ObfsPassword: obfsPass,
		}
	}
	node.EnsureID()
	return node, nil
}

func parseTUIC(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("tuic://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" || u.User == nil {
		return nil, fmt.Errorf("invalid tuic URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid tuic port: %w", err)
	}
	q := u.Query()
	pass, _ := u.User.Password()
	node := &protocol.ProxyNode{
		Name:     displayName(fragment, "TUIC", u),
		Type:     protocol.ProtoTUIC,
		Server:   u.Hostname(),
		Port:     port,
		UUID:     u.User.Username(),
		Password: pass,
		TLS: &protocol.TLSConfig{
			Enabled:    true,
			ServerName: q.Get("sni"),
			Insecure:   isTruthy(q.Get("insecure")) || isTruthy(q.Get("allowInsecure")),
			ALPN:       splitCSV(q.Get("alpn")),
		},
		TUIC: &protocol.TUICConfig{
			CongestionControl: orDefault(q.Get("congestion_control"), "bbr"),
			UDPRelayMode:      q.Get("udp_relay_mode"),
		},
	}
	node.EnsureID()
	return node, nil
}

func parseSocks(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("socks://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" {
		return nil, fmt.Errorf("invalid socks URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid socks port: %w", err)
	}
	node := &protocol.ProxyNode{
		Name:   displayName(fragment, "SOCKS", u),
		Type:   protocol.ProtoSocks,
		Server: u.Hostname(),
		Port:   port,
	}
	if u.User != nil {
		node.UUID = u.User.Username()
		node.Password, _ = u.User.Password()
	}
	node.EnsureID()
	return node, nil
}

func parseHTTPProxy(body, fragment string, https bool) (*protocol.ProxyNode, error) {
	u, err := url.Parse("http://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" {
		return nil, fmt.Errorf("invalid http URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		port = 80
	}
	node := &protocol.ProxyNode{
		Name:   displayName(fragment, "HTTP", u),
		Type:   protocol.ProtoHTTP,
		Server: u.Hostname(),
		Port:   port,
	}
	if u.User != nil {
		node.UUID = u.User.Username()
		node.Password, _ = u.User.Password()
	}
	if https {
		node.TLS = &protocol.TLSConfig{Enabled: true, ServerName: u.Hostname()}
	}
	node.EnsureID()
	return node, nil
}

func parseVMess(raw string) (*protocol.ProxyNode, error) {
	content := strings.TrimPrefix(raw, "vmess://")
	decoded, err := decodeBase64Loose(content)
	if err != nil {
		return nil, fmt.Errorf("vmess: %w", err)
	}
	var v struct {
		V    any    `json:"v"`
		PS   string `json:"ps"`
		Add  string `json:"add"`
		Port any    `json:"port"`
		ID   string `json:"id"`
		Aid  any    `json:"aid"`
		Scy  string `json:"scy"`
		Net  string `json:"net"`
		Host string `json:"host"`
		Path string `json:"path"`
		TLS  string `json:"tls"`
		SNI  string `json:"sni"`
		Alpn string `json:"alpn"`
		Fp   string `json:"fp"`
	}
	if err := json.Unmarshal(decoded, &v); err != nil {
		return nil, fmt.Errorf("vmess json: %w", err)
	}
	if v.Add == "" || v.ID == "" {
		return nil, fmt.Errorf("vmess: missing add/id")
	}
	port := 443
	switch val := v.Port.(type) {
	case float64:
		port = int(val)
	case string:
		port, _ = strconv.Atoi(val)
	}
	aid := 0
	switch val := v.Aid.(type) {
	case float64:
		aid = int(val)
	case string:
		aid, _ = strconv.Atoi(val)
	}
	node := &protocol.ProxyNode{
		Name:     v.PS,
		Type:     protocol.ProtoVMess,
		Server:   v.Add,
		Port:     port,
		UUID:     v.ID,
		AlterID:  aid,
		Security: orDefault(v.Scy, "auto"),
	}
	if strings.EqualFold(v.TLS, "tls") {
		sni := v.SNI
		if sni == "" {
			sni = v.Host
		}
		node.TLS = &protocol.TLSConfig{Enabled: true, ServerName: sni, ALPN: splitCSV(v.Alpn), Fingerprint: v.Fp, UTLS: v.Fp != "" && v.Fp != "none"}
	}
	if t := strings.ToLower(v.Net); t != "" && t != "tcp" && t != "raw" {
		node.Transport = &protocol.TransportConfig{Type: t, Path: v.Path, Host: v.Host}
		if t == "grpc" {
			node.Transport.ServiceName = v.Path
		}
	}
	node.EnsureID()
	return node, nil
}

func parseWireGuard(raw, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if u.Host == "" {
		return nil, fmt.Errorf("invalid wireguard URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid wireguard port: %w", err)
	}
	q := u.Query()
	wg := &protocol.WireGuardConfig{
		PrivateKey: q.Get("privatekey"),
		PublicKey:  q.Get("publickey"),
		MTU:        intFromQuery(q, "mtu", 1408),
	}
	for _, a := range splitCSV(q.Get("address")) {
		if a != "" {
			wg.LocalAddress = append(wg.LocalAddress, a)
		}
	}
	if wg.PrivateKey == "" || wg.PublicKey == "" || len(wg.LocalAddress) == 0 {
		return nil, fmt.Errorf("wireguard: privatekey/publickey/address required")
	}
	if res := q.Get("reserved"); res != "" {
		for _, p := range splitCSV(res) {
			if v, err := strconv.Atoi(p); err == nil && v >= 0 && v <= 255 {
				wg.Reserved = append(wg.Reserved, uint8(v))
			}
		}
	}
	node := &protocol.ProxyNode{
		Name:      displayName(fragment, "WireGuard", u),
		Type:      protocol.ProtoWireGuard,
		Server:    u.Hostname(),
		Port:      port,
		WireGuard: wg,
	}
	node.EnsureID()
	return node, nil
}

// ---- Clash / mihomo YAML ----

type clashConfig struct {
	Proxies []map[string]any `yaml:"proxies"`
}

func parseClashYAML(data []byte) ([]*protocol.ProxyNode, []string, bool) {
	var cfg clashConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil || len(cfg.Proxies) == 0 {
		return nil, nil, false
	}
	var (
		nodes []*protocol.ProxyNode
		warns []string
	)
	for _, m := range cfg.Proxies {
		node, warn := clashProxyToNode(m)
		if warn != "" {
			warns = append(warns, warn)
		}
		if node != nil {
			nodes = append(nodes, node)
		}
	}
	return nodes, warns, true
}

func clashProxyToNode(m map[string]any) (*protocol.ProxyNode, string) {
	get := func(k string) string { return strVal(m[k]) }
	getInt := func(k string, def int) int {
		if v, ok := m[k]; ok {
			if f, ok := v.(int); ok {
				return f
			}
			if f, ok := v.(float64); ok {
				return int(f)
			}
			if s, ok := v.(string); ok {
				if n, err := strconv.Atoi(s); err == nil {
					return n
				}
			}
		}
		return def
	}
	name := get("name")
	server := get("server")
	port := getInt("port", 0)
	ptype := strings.ToLower(get("type"))
	if server == "" || port == 0 || name == "" {
		return nil, "clash: skip entry missing name/server/port"
	}
	node := &protocol.ProxyNode{Name: name, Server: server, Port: port}
	switch ptype {
	case "ss":
		node.Type = protocol.ProtoShadowsocks
		node.Security = get("cipher")
		node.Password = get("password")
	case "socks5":
		node.Type = protocol.ProtoSocks
		node.UUID = get("username")
		node.Password = get("password")
	case "http":
		node.Type = protocol.ProtoHTTP
		node.UUID = get("username")
		node.Password = get("password")
		if get("tls") == "true" {
			node.TLS = &protocol.TLSConfig{Enabled: true, ServerName: server}
		}
	case "vmess":
		node.Type = protocol.ProtoVMess
		node.UUID = get("uuid")
		node.AlterID = getInt("alterId", 0)
		node.Security = orDefault(get("cipher"), "auto")
	case "vless":
		node.Type = protocol.ProtoVLESS
		node.UUID = get("uuid")
		node.Flow = get("flow")
	case "trojan":
		node.Type = protocol.ProtoTrojan
		node.Password = get("password")
	case "hysteria2":
		node.Type = protocol.ProtoHysteria2
		node.Password = get("password")
		if obfs := get("obfs"); obfs != "" && obfs != "none" {
			node.Hysteria2 = &protocol.Hysteria2Config{ObfsType: obfs, ObfsPassword: get("obfs-password")}
		}
	case "tuic":
		node.Type = protocol.ProtoTUIC
		node.UUID = get("uuid")
		node.Password = get("password")
		node.TUIC = &protocol.TUICConfig{
			CongestionControl: orDefault(get("congestion-controller"), "bbr"),
		}
	default:
		return nil, fmt.Sprintf("clash: unsupported proxy type %q (%s)", ptype, name)
	}

	// TLS block (clash: tls: true + servername / reality-opts / client-fingerprint)
	if get("tls") == "true" || get("servername") != "" || m["reality-opts"] != nil {
		tls := &protocol.TLSConfig{Enabled: true, ServerName: get("servername")}
		if tls.ServerName == "" {
			tls.ServerName = server
		}
		tls.Insecure = get("skip-cert-verify") == "true"
		if fp := get("client-fingerprint"); fp != "" && fp != "none" {
			tls.Fingerprint = fp
			tls.UTLS = true
		}
		if ro, ok := m["reality-opts"].(map[string]any); ok {
			tls.Reality = &protocol.Reality{
				Enabled:   true,
				PublicKey: strVal(ro["public-key"]),
				ShortID:   strVal(ro["short-id"]),
			}
		}
		node.TLS = tls
	}

	// Transport (ws-opts / grpc-opts / http-opts / network)
	network := strings.ToLower(get("network"))
	switch network {
	case "ws":
		tc := &protocol.TransportConfig{Type: "ws", Path: get("path")}
		if wo, ok := m["ws-opts"].(map[string]any); ok {
			tc.Path = orDefault(strVal(wo["path"]), tc.Path)
			if h, ok := wo["headers"].(map[string]any); ok {
				tc.Host = strVal(h["Host"])
			}
		}
		node.Transport = tc
	case "grpc":
		tc := &protocol.TransportConfig{Type: "grpc"}
		if go_, ok := m["grpc-opts"].(map[string]any); ok {
			tc.ServiceName = strVal(go_["grpc-service-name"])
		}
		node.Transport = tc
	case "http", "h2":
		tc := &protocol.TransportConfig{Type: "http", Path: get("path")}
		if ho, ok := m["http-opts"].(map[string]any); ok {
			tc.Path = orDefault(strVal(ho["path"]), tc.Path)
		}
		node.Transport = tc
	case "httpupgrade":
		node.Transport = &protocol.TransportConfig{Type: "httpupgrade", Host: get("host"), Path: get("path")}
	}

	node.EnsureID()
	return node, ""
}

// ---- small helpers ----

func isTruthy(s string) bool {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

func orDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}

func splitCSV(s string) []string {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func intFromQuery(q url.Values, key string, def int) int {
	if v := q.Get(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func strVal(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case int:
		return strconv.Itoa(t)
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case bool:
		if t {
			return "true"
		}
		return "false"
	default:
		return ""
	}
}
