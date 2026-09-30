// Package windscribe turns ONE WireGuard config that the user generated in
// their own Windscribe account (windscribe.com ▸ Config Generator; free and Pro
// accounts) into nodes for every location the account may use, using
// Windscribe's PUBLIC server list (no login, no private API):
//
//	https://assets.windscribe.com/serverlist/mob-v2/{0|1}/{revision}
//
// Each location group publishes its WireGuard endpoint host and server public
// key; the user's key pair, address and pre-shared key are account-wide, so
// only the peer changes per location. Free accounts see only pro=0 groups.
package windscribe

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"easyvpn/core/pkg/protocol"
)

// ListURL is the public server-list base (the path suffix is {pro}/{rev}).
var ListURL = "https://assets.windscribe.com/serverlist/mob-v2"

// Group is one city-level server group.
type Group struct {
	ID         int    `json:"id"`
	City       string `json:"city"`
	Nick       string `json:"nick"`
	Pro        int    `json:"pro"`
	WGPubKey   string `json:"wg_pubkey"`
	WGEndpoint string `json:"wg_endpoint"`
	PingIP     string `json:"ping_ip"`
	Health     int    `json:"health"`
}

// Location is a country/region with its groups.
type Location struct {
	ID          int     `json:"id"`
	Name        string  `json:"name"`
	CountryCode string  `json:"country_code"`
	PremiumOnly int     `json:"premium_only"`
	Status      int     `json:"status"`
	Groups      []Group `json:"groups"`
}

type listResponse struct {
	Data []Location `json:"data"`
}

// FetchLocations downloads the public list. pro selects the Pro list (all
// groups); the free list marks non-free groups with pro=1.
func FetchLocations(ctx context.Context, hc *http.Client, pro bool) ([]Location, error) {
	if hc == nil {
		hc = &http.Client{Timeout: 20 * time.Second}
	}
	p := "0"
	if pro {
		p = "1"
	}
	u := fmt.Sprintf("%s/%s/%d", strings.TrimRight(ListURL, "/"), p, time.Now().Unix())
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	resp, err := hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("windscribe server list: HTTP %d", resp.StatusCode)
	}
	var r listResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(&r); err != nil {
		return nil, fmt.Errorf("windscribe server list: %w", err)
	}
	if len(r.Data) == 0 {
		return nil, fmt.Errorf("windscribe server list is empty")
	}
	return r.Data, nil
}

// Expand clones the user's WireGuard template node for every usable group.
// includePro=false keeps only free groups. The template's port is kept
// (Windscribe WG listens on several ports: 443, 80, 53, 123, 1194, 65142...).
func Expand(template *protocol.ProxyNode, locs []Location, includePro bool) ([]*protocol.ProxyNode, error) {
	if template == nil || template.Type != protocol.ProtoWireGuard || template.WireGuard == nil {
		return nil, fmt.Errorf("a Windscribe WireGuard config is required (windscribe.com ▸ Config Generator ▸ WireGuard)")
	}
	port := template.Port
	if port <= 0 {
		port = 443
	}
	var out []*protocol.ProxyNode
	for _, l := range locs {
		if l.Status != 0 && l.Status != 1 {
			continue // disabled / maintenance
		}
		for _, g := range l.Groups {
			if g.WGEndpoint == "" || g.WGPubKey == "" {
				continue
			}
			if !includePro && (g.Pro != 0 || l.PremiumOnly != 0) {
				continue
			}
			wg := *template.WireGuard
			wg.PublicKey = g.WGPubKey
			wg.LocalAddress = append([]string(nil), template.WireGuard.LocalAddress...)
			n := &protocol.ProxyNode{
				Name:      nodeName(l, g),
				Type:      protocol.ProtoWireGuard,
				Server:    g.WGEndpoint,
				Port:      port,
				Group:     "Windscribe " + l.CountryCode,
				WireGuard: &wg,
			}
			n.EnsureID()
			out = append(out, n)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no Windscribe locations available for this account type")
	}
	return out, nil
}

func nodeName(l Location, g Group) string {
	name := flag(l.CountryCode) + " " + l.Name + " · " + g.City
	if g.Nick != "" {
		name += " " + g.Nick
	}
	if g.Pro != 0 {
		name += " ★"
	}
	return strings.TrimSpace(name)
}

func flag(cc string) string {
	cc = strings.ToUpper(cc)
	if len(cc) != 2 || cc[0] < 'A' || cc[0] > 'Z' || cc[1] < 'A' || cc[1] > 'Z' {
		return ""
	}
	return string(rune(0x1F1E6+int(cc[0]-'A'))) + string(rune(0x1F1E6+int(cc[1]-'A')))
}

// IsWindscribeConfig reports whether a node looks like a Windscribe WG config
// (endpoint on a Windscribe domain), so the UI can offer "expand to all locations".
func IsWindscribeConfig(n *protocol.ProxyNode) bool {
	if n == nil || n.Type != protocol.ProtoWireGuard {
		return false
	}
	h := strings.ToLower(n.Server)
	for _, d := range []string{"windscribe.com", "whiskergalaxy.com", "totallyacdn.com", "staticnetcontent.com"} {
		if strings.HasSuffix(h, d) {
			return true
		}
	}
	return false
}
