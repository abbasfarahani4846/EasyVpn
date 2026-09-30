package engine

import (
	"context"
	"net"
	"net/netip"
	"time"

	"easyvpn/core/pkg/router"
)

// withLocalDNS pins the "local" resolver to a real DNS server on hosts that have
// no usable system resolver configuration. Android has no /etc/resolv.conf, so
// sing-box's "local" DNS would query 127.0.0.1:53 and every hostname lookup for
// the proxy server (or a direct domain) would fail. A user-chosen LocalDNS wins.
func withLocalDNS(m router.Model, system []string, android bool) router.Model {
	if m.LocalDNS != "" {
		return m
	}
	if u := usableDNS(system); len(u) > 0 {
		m.LocalDNS = "udp://" + u[0]
		return m
	}
	if android {
		m.LocalDNS = "udp://8.8.8.8"
	}
	return m
}

// useSystemResolver points Go's own resolver (net.DefaultResolver, used by the
// Xray sidecar and plain net.Dial) at the device DNS. Without /etc/resolv.conf Go
// falls back to 127.0.0.1:53, which does not exist on Android.
func useSystemResolver(system []string, android bool) {
	servers := usableDNS(system)
	if len(servers) == 0 {
		if !android {
			return
		}
		servers = []string{"8.8.8.8"}
	}
	var next uint32
	net.DefaultResolver = &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			d := net.Dialer{Timeout: 4 * time.Second}
			i := int(next) % len(servers)
			next++
			return d.DialContext(ctx, network, net.JoinHostPort(servers[i], "53"))
		},
	}
}

func usableDNS(system []string) []string {
	var out []string
	for _, s := range system {
		a, err := netip.ParseAddr(s)
		if err != nil || a.IsLoopback() || a.IsUnspecified() || a.Is6() {
			continue
		}
		out = append(out, a.String())
	}
	return out
}
