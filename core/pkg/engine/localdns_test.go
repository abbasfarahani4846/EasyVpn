package engine

import (
	"testing"

	"easyvpn/core/pkg/router"
)

func TestWithLocalDNS(t *testing.T) {
	cases := []struct {
		name    string
		in      string
		sys     []string
		android bool
		want    string
	}{
		{"uses first usable device dns", "", []string{"127.0.0.1", "::1", "192.168.1.1", "8.8.4.4"}, true, "udp://192.168.1.1"},
		{"user setting wins", "udp://78.157.42.100", []string{"192.168.1.1"}, true, "udp://78.157.42.100"},
		{"android fallback", "", nil, true, "udp://8.8.8.8"},
		{"desktop keeps system resolver", "", nil, false, ""},
	}
	for _, c := range cases {
		m := router.Default()
		m.LocalDNS = c.in
		if got := withLocalDNS(m, c.sys, c.android).LocalDNS; got != c.want {
			t.Errorf("%s: got %q want %q", c.name, got, c.want)
		}
	}
}
