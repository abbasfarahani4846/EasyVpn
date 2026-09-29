package config

import (
	"fmt"
	"strconv"
	"strings"

	"easyvpn/core/pkg/protocol"
)

// ParseOVPN converts an OpenVPN client profile (.ovpn) into a ProxyNode that
// the sing-box `openvpn-client` endpoint can run. Directives that are not
// mapped are collected in OpenVPNConfig.Warnings (never silently dropped).
func ParseOVPN(content, name string) (*protocol.ProxyNode, error) {
	c := &protocol.OpenVPNConfig{Mode: "tls"}
	defaultProto := "udp"
	var blocks = map[string]string{}
	lines := strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")

	// First pass: inline <tag>...</tag> blocks.
	var body []string
	for i := 0; i < len(lines); i++ {
		t := strings.TrimSpace(lines[i])
		if strings.HasPrefix(t, "<") && strings.HasSuffix(t, ">") && !strings.HasPrefix(t, "</") {
			tag := t[1 : len(t)-1]
			var buf []string
			j := i + 1
			for ; j < len(lines); j++ {
				if strings.TrimSpace(lines[j]) == "</"+tag+">" {
					break
				}
				buf = append(buf, lines[j])
			}
			blocks[tag] = strings.TrimSpace(strings.Join(buf, "\n"))
			i = j
			continue
		}
		body = append(body, lines[i])
	}

	warn := func(format string, a ...any) { c.Warnings = append(c.Warnings, fmt.Sprintf(format, a...)) }
	for _, raw := range body {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		f := strings.Fields(line)
		d, args := strings.ToLower(f[0]), f[1:]
		arg := func(i int) string {
			if i < len(args) {
				return args[i]
			}
			return ""
		}
		switch d {
		case "client", "dev", "nobind", "persist-key", "persist-tun", "resolv-retry", "verb", "mute",
			"mute-replay-warnings", "float", "tun-mtu", "explicit-exit-notify", "setenv", "script-security",
			"user", "group", "ping", "keepalive", "tls-client", "pull", "dev-type", "auth-nocache", "ns-cert-type":
			// harmless / handled by sing-box defaults
			if d == "keepalive" && len(args) >= 2 {
				if v, err := strconv.Atoi(args[1]); err == nil {
					c.PingRestartSec = v
				}
			}
			if d == "ns-cert-type" && arg(0) == "server" && c.RemoteCertTLS == "" {
				c.RemoteCertTLS = "server"
			}
		case "proto":
			p := strings.ToLower(arg(0))
			switch {
			case strings.HasPrefix(p, "tcp"):
				defaultProto = "tcp"
			case strings.HasPrefix(p, "udp"):
				defaultProto = "udp"
			}
		case "remote":
			r := protocol.OVPNRemote{Host: arg(0), Port: 1194}
			if v, err := strconv.Atoi(arg(1)); err == nil {
				r.Port = v
			}
			if p := strings.ToLower(arg(2)); strings.HasPrefix(p, "tcp") {
				r.Network = "tcp"
			} else if strings.HasPrefix(p, "udp") {
				r.Network = "udp"
			}
			c.Remotes = append(c.Remotes, r)
		case "remote-random":
			c.RemoteRandom = true
		case "cipher":
			c.Cipher = arg(0)
		case "data-ciphers", "ncp-ciphers":
			c.DataCiphers = strings.Split(arg(0), ":")
		case "data-ciphers-fallback":
			c.DataCiphersFallback = arg(0)
		case "auth":
			c.Auth = arg(0)
		case "auth-user-pass":
			if len(args) == 0 {
				warn("auth-user-pass: username/password must be provided by the user")
			} else {
				warn("auth-user-pass file %q is not readable on this platform; enter credentials in the app", args[0])
			}
		case "comp-lzo":
			if arg(0) == "" {
				c.CompressionLZO = "adaptive"
			} else {
				c.CompressionLZO = arg(0)
			}
		case "compress":
			if arg(0) == "" {
				c.Compression = "stub-v2"
			} else {
				c.Compression = arg(0)
			}
		case "remote-cert-tls":
			c.RemoteCertTLS = arg(0)
		case "verify-x509-name":
			c.ServerName = arg(0)
		case "redirect-gateway":
			c.RedirectGateway = true
			for _, a := range args {
				switch strings.ToLower(a) {
				case "def1":
					c.RedirectFlags = append(c.RedirectFlags, "def1")
				case "ipv6":
					c.RedirectFlags = append(c.RedirectFlags, "ipv6")
				case "!ipv4":
					c.RedirectFlags = append(c.RedirectFlags, "!ipv4")
				}
			}
		case "route-nopull":
			c.RouteNoPull = true
		case "route":
			if len(args) >= 2 {
				if p := cidrFromMask(arg(0), arg(1)); p != "" {
					c.Routes = append(c.Routes, p)
				}
			} else if len(args) == 1 && strings.Contains(args[0], "/") {
				c.Routes = append(c.Routes, args[0])
			}
		case "mssfix":
			c.MSSFix, _ = strconv.Atoi(arg(0))
		case "fragment":
			c.Fragment, _ = strconv.Atoi(arg(0))
		case "reneg-sec":
			c.RenegSec, _ = strconv.Atoi(arg(0))
		case "ping-restart":
			c.PingRestartSec, _ = strconv.Atoi(arg(0))
		case "topology":
			c.Topology = arg(0)
		case "key-direction":
			if arg(0) == "0" {
				c.KeyDirection = "server"
			} else if arg(0) == "1" {
				c.KeyDirection = "client"
			}
		case "tls-auth", "tls-crypt", "tls-crypt-v2", "secret", "ca", "cert", "key":
			// inline blocks are handled below; external files cannot be read here
			if _, ok := blocks[d]; !ok {
				warn("%s references an external file (%q); embed it inline (<%s>…</%s>) or import the archive", d, arg(0), d, d)
			}
			if d == "tls-auth" && len(args) >= 2 && c.KeyDirection == "" {
				if args[1] == "0" {
					c.KeyDirection = "server"
				} else if args[1] == "1" {
					c.KeyDirection = "client"
				}
			}
		default:
			warn("unmapped directive: %s", d)
		}
	}

	c.CA, c.Cert, c.Key = blocks["ca"], blocks["cert"], blocks["key"]
	switch {
	case blocks["tls-crypt-v2"] != "":
		c.ControlWrapType, c.ControlWrapKey = "tls_crypt_v2", blocks["tls-crypt-v2"]
	case blocks["tls-crypt"] != "":
		c.ControlWrapType, c.ControlWrapKey = "tls_crypt", blocks["tls-crypt"]
	case blocks["tls-auth"] != "":
		c.ControlWrapType, c.ControlWrapKey = "tls_auth", blocks["tls-auth"]
		c.ControlWrapDir = c.KeyDirection
	}
	if s := blocks["secret"]; s != "" {
		c.Mode, c.StaticKey = "static_key", s
		c.Warnings = append(c.Warnings, "static-key mode is legacy and has no forward secrecy")
	}
	for i := range c.Remotes {
		if c.Remotes[i].Network == "" {
			c.Remotes[i].Network = defaultProto
		}
	}
	if len(c.Remotes) == 0 {
		return nil, fmt.Errorf("ovpn: no 'remote' directive found")
	}
	c.Network = defaultProto
	if c.Mode == "tls" && c.CA == "" {
		c.Warnings = append(c.Warnings, "no inline CA certificate; the profile cannot be verified")
	}

	node := &protocol.ProxyNode{
		Name:    name,
		Type:    protocol.ProtoOpenVPN,
		Server:  c.Remotes[0].Host,
		Port:    c.Remotes[0].Port,
		OpenVPN: c,
	}
	if node.Name == "" {
		node.Name = fmt.Sprintf("OpenVPN %s", node.Server)
	}
	node.EnsureID()
	return node, nil
}

func cidrFromMask(ip, mask string) string {
	parts := strings.Split(mask, ".")
	if len(parts) != 4 {
		return ""
	}
	bits := 0
	for _, p := range parts {
		v, err := strconv.Atoi(p)
		if err != nil {
			return ""
		}
		for ; v > 0; v = (v << 1) & 0xff {
			bits++
		}
	}
	return fmt.Sprintf("%s/%d", ip, bits)
}

// LooksLikeOVPN reports whether content is an OpenVPN profile.
func LooksLikeOVPN(content string) bool {
	return strings.Contains(content, "\nremote ") || strings.HasPrefix(strings.TrimSpace(content), "client") ||
		(strings.Contains(content, "<ca>") && strings.Contains(content, "remote "))
}
