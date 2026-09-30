package warp

import (
	"context"
	"os"
	"testing"
)

// Live registration against Cloudflare; opt-in with EASYVPN_LIVE=1.
func TestLiveRegister(t *testing.T) {
	if os.Getenv("EASYVPN_LIVE") != "1" {
		t.Skip("set EASYVPN_LIVE=1")
	}
	a, err := NewClient(nil).Register(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	n, err := a.Node("WARP", "")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("registered: endpoint=%s:%d v4=%s reserved=%v", n.Server, n.Port, a.IPv4, a.Reserved())
}
