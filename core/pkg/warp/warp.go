// Package warp registers free Cloudflare WARP devices (the same client API flow
// as the official app / wgcf) and turns them into WireGuard nodes. Two
// independent devices give "WARP in WARP"; a WARP node as the last hop of a
// chain gives "exit via WARP" (the destination sees a Cloudflare address).
package warp

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"easyvpn/core/pkg/protocol"
)

// DefaultAPI is the Cloudflare client API base.
const DefaultAPI = "https://api.cloudflareclient.com/v0a2158"

// DefaultEndpoint is used when the API does not return a usable endpoint.
const DefaultEndpoint = "engage.cloudflareclient.com:2408"

// Account is a registered WARP device.
type Account struct {
	ID         string `json:"id"`
	Token      string `json:"token"`
	PrivateKey string `json:"private_key"`
	PeerKey    string `json:"peer_public_key"`
	Endpoint   string `json:"endpoint"` // host:port
	IPv4       string `json:"ipv4"`
	IPv6       string `json:"ipv6"`
	ClientID   string `json:"client_id"`
	WarpPlus   bool   `json:"warp_plus"`
	License    string `json:"license,omitempty"`
}

// Client talks to the WARP API.
type Client struct {
	API  string
	HTTP *http.Client
}

// NewClient returns a client using hc (nil = default with 20 s timeout).
func NewClient(hc *http.Client) *Client {
	if hc == nil {
		hc = &http.Client{Timeout: 20 * time.Second}
	}
	return &Client{API: DefaultAPI, HTTP: hc}
}

type regResponse struct {
	ID      string `json:"id"`
	Token   string `json:"token"`
	Account struct {
		WarpPlus bool   `json:"warp_plus"`
		License  string `json:"license"`
	} `json:"account"`
	Config struct {
		ClientID string `json:"client_id"`
		Peers    []struct {
			PublicKey string `json:"public_key"`
			Endpoint  struct {
				V4   string `json:"v4"`
				V6   string `json:"v6"`
				Host string `json:"host"`
			} `json:"endpoint"`
		} `json:"peers"`
		Interface struct {
			Addresses struct {
				V4 string `json:"v4"`
				V6 string `json:"v6"`
			} `json:"addresses"`
		} `json:"interface"`
	} `json:"config"`
}

func (c *Client) do(ctx context.Context, method, path, token string, body any, out any) error {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(c.API, "/")+path, rd)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "okhttp/3.12.1")
	req.Header.Set("CF-Client-Version", "a-6.30-3596")
	req.Header.Set("Content-Type", "application/json; charset=UTF-8")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("warp api %s %s: HTTP %d: %s", method, path, resp.StatusCode, truncate(string(b), 200))
	}
	if out != nil {
		if err := json.Unmarshal(b, out); err != nil {
			return fmt.Errorf("warp api: bad response: %w", err)
		}
	}
	return nil
}

// Register creates a new free WARP device.
func (c *Client) Register(ctx context.Context) (*Account, error) {
	priv, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	body := map[string]any{
		"key":           base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes()),
		"install_id":    "",
		"fcm_token":     "",
		"tos":           time.Now().UTC().Format("2006-01-02T15:04:05.000Z"),
		"model":         "PC",
		"serial_number": "",
		"locale":        "en_US",
	}
	var r regResponse
	if err := c.do(ctx, http.MethodPost, "/reg", "", body, &r); err != nil {
		return nil, err
	}
	if r.ID == "" || r.Token == "" || len(r.Config.Peers) == 0 || r.Config.Interface.Addresses.V4 == "" {
		return nil, fmt.Errorf("warp api: incomplete registration response")
	}
	p := r.Config.Peers[0]
	ep := p.Endpoint.Host
	if _, port, err := net.SplitHostPort(ep); err != nil || port == "0" || port == "" {
		ep = DefaultEndpoint
	}
	return &Account{
		ID: r.ID, Token: r.Token,
		PrivateKey: base64.StdEncoding.EncodeToString(priv.Bytes()),
		PeerKey:    p.PublicKey,
		Endpoint:   ep,
		IPv4:       r.Config.Interface.Addresses.V4,
		IPv6:       r.Config.Interface.Addresses.V6,
		ClientID:   r.Config.ClientID,
		WarpPlus:   r.Account.WarpPlus,
		License:    r.Account.License,
	}, nil
}

// SetLicense applies a WARP+ license key to the device (optional).
func (c *Client) SetLicense(ctx context.Context, a *Account, license string) error {
	if err := c.do(ctx, http.MethodPut, "/reg/"+a.ID+"/account", a.Token, map[string]string{"license": license}, nil); err != nil {
		return err
	}
	var r regResponse
	if err := c.do(ctx, http.MethodGet, "/reg/"+a.ID, a.Token, nil, &r); err == nil {
		a.WarpPlus = r.Account.WarpPlus
	}
	a.License = license
	return nil
}

// Reserved decodes the 3 "reserved" bytes WARP expects in every WireGuard
// packet header, derived from client_id.
func (a *Account) Reserved() []uint8 {
	b, err := base64.StdEncoding.DecodeString(a.ClientID)
	if err != nil || len(b) < 3 {
		return nil
	}
	return []uint8{b[0], b[1], b[2]}
}

// Node converts the account into a WireGuard node. endpoint overrides the
// server (e.g. a scanned clean IP:port) when non-empty.
func (a *Account) Node(name, endpoint string) (*protocol.ProxyNode, error) {
	ep := a.Endpoint
	if endpoint != "" {
		ep = endpoint
	}
	host, portStr, err := net.SplitHostPort(ep)
	if err != nil {
		return nil, fmt.Errorf("warp endpoint %q: %w", ep, err)
	}
	port, _ := strconv.Atoi(portStr)
	addrs := []string{a.IPv4 + "/32"}
	if a.IPv6 != "" {
		addrs = append(addrs, a.IPv6+"/128")
	}
	if name == "" {
		name = "WARP"
	}
	n := &protocol.ProxyNode{
		Name:   name,
		Type:   protocol.ProtoWireGuard,
		Server: host,
		Port:   port,
		Group:  "WARP",
		WireGuard: &protocol.WireGuardConfig{
			PrivateKey:   a.PrivateKey,
			PublicKey:    a.PeerKey,
			LocalAddress: addrs,
			MTU:          1280,
			Reserved:     a.Reserved(),
		},
	}
	n.EnsureID()
	return n, nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}
