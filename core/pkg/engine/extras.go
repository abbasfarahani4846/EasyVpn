package engine

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"path/filepath"
	"time"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/providers/windscribe"
	"easyvpn/core/pkg/transport"
	"easyvpn/core/pkg/update"
	"easyvpn/core/pkg/warp"
)

// withNetwork runs fn with a direct HTTP client first and, if that fails and a
// tunnel is up, once more through the local proxy (same policy as
// subscriptions: GitHub/Cloudflare may be filtered on the direct path).
func (e *Engine) withNetwork(ctx context.Context, timeout time.Duration, fn func(*http.Client) error) error {
	err := fn(&http.Client{Timeout: timeout})
	if err == nil {
		return nil
	}
	if pu := e.localProxyURL(); pu != "" {
		if u, perr := url.Parse(pu); perr == nil {
			if err2 := fn(&http.Client{Timeout: timeout, Transport: &http.Transport{Proxy: http.ProxyURL(u)}}); err2 == nil {
				return nil
			} else {
				return errors.Join(err, err2)
			}
		}
	}
	return err
}

// WarpRegister creates a free WARP device (optionally applying a WARP+
// license) and returns it as a WireGuard node plus the account (for storage).
func (e *Engine) WarpRegister(ctx context.Context, name, endpoint, license string) (*protocol.ProxyNode, *warp.Account, error) {
	var acc *warp.Account
	err := e.withNetwork(ctx, 25*time.Second, func(hc *http.Client) error {
		c := warp.NewClient(hc)
		a, err := c.Register(ctx)
		if err != nil {
			return err
		}
		if license != "" {
			if err := c.SetLicense(ctx, a, license); err != nil {
				return err
			}
		}
		acc = a
		return nil
	})
	if err != nil {
		return nil, nil, err
	}
	n, err := acc.Node(name, endpoint)
	return n, acc, err
}

// WindscribeExpand turns one user-generated Windscribe WireGuard config into
// nodes for every location the account can use (public server list).
func (e *Engine) WindscribeExpand(ctx context.Context, template *protocol.ProxyNode, pro bool) ([]*protocol.ProxyNode, error) {
	var locs []windscribe.Location
	err := e.withNetwork(ctx, 25*time.Second, func(hc *http.Client) error {
		l, err := windscribe.FetchLocations(ctx, hc, pro)
		locs = l
		return err
	})
	if err != nil {
		return nil, err
	}
	return windscribe.Expand(template, locs, pro)
}

// UpdateCheck asks GitHub Releases for a newer build.
func (e *Engine) UpdateCheck(ctx context.Context, channel, current string, t update.Target) (*update.Info, error) {
	var info *update.Info
	err := e.withNetwork(ctx, 25*time.Second, func(hc *http.Client) error {
		i, err := update.Check(ctx, hc, channel, current, t)
		info = i
		return err
	})
	return info, err
}

// UpdateDownload downloads and verifies an update into <cache>/updates and
// publishes "updateProgress" events.
func (e *Engine) UpdateDownload(ctx context.Context, assetURL, name, sha string) (string, error) {
	dir := filepath.Join(e.cacheDir, "updates")
	var path string
	progress := func(done, total int64) {
		e.bus.Publish(transport.KindPriority, "updateProgress", map[string]int64{"done": done, "total": total})
	}
	err := e.withNetwork(ctx, 30*time.Minute, func(hc *http.Client) error {
		p, err := update.Download(ctx, hc, assetURL, dir, name, sha, progress)
		path = p
		return err
	})
	return path, err
}

// LastCrash returns the panic/fatal output of a previous crashed core run.
func (e *Engine) LastCrash() string { return LastCrash(e.cacheDir) }
