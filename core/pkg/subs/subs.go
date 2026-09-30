// Package subs fetches subscription URLs: direct first, then through the
// running proxy, parsing the standard usage/interval headers.
package subs

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// MaxBody caps a subscription download (64 MB handles ~200k nodes).
const MaxBody = 64 << 20

// UserInfo is the parsed `subscription-userinfo` header.
type UserInfo struct {
	Upload   int64 `json:"upload"`
	Download int64 `json:"download"`
	Total    int64 `json:"total"`
	Expire   int64 `json:"expire"` // unix seconds, 0 = unlimited
}

// Result is a fetched subscription payload plus metadata.
type Result struct {
	Body            string    `json:"body"`
	Via             string    `json:"via"` // direct|proxy
	UserInfo        *UserInfo `json:"userinfo,omitempty"`
	UpdateIntervalH int       `json:"update_interval_hours,omitempty"`
	ProfileTitle    string    `json:"profile_title,omitempty"`
	Attempts        []string  `json:"attempts,omitempty"`
}

// Fetch downloads a subscription. proxyURL (e.g. "http://127.0.0.1:2080") is
// tried only after the direct attempt fails.
func Fetch(ctx context.Context, rawURL, userAgent, proxyURL string) (*Result, error) {
	u, err := url.Parse(rawURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return nil, fmt.Errorf("invalid subscription URL")
	}
	if userAgent == "" {
		userAgent = "EasyVPN/1.0 (sing-box; clash.meta; v2rayN)"
	}
	res := &Result{}
	do := func(c *http.Client, via string) error {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
		if err != nil {
			return err
		}
		req.Header.Set("User-Agent", userAgent)
		resp, err := c.Do(req)
		if err != nil {
			res.Attempts = append(res.Attempts, via+": "+err.Error())
			return err
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			err := fmt.Errorf("HTTP %d", resp.StatusCode)
			res.Attempts = append(res.Attempts, via+": "+err.Error())
			return err
		}
		b, err := io.ReadAll(io.LimitReader(resp.Body, MaxBody+1))
		if err != nil {
			res.Attempts = append(res.Attempts, via+": "+err.Error())
			return err
		}
		if len(b) > MaxBody {
			return fmt.Errorf("subscription exceeds %d MB", MaxBody>>20)
		}
		res.Body, res.Via = string(b), via
		res.UserInfo = ParseUserInfo(resp.Header.Get("Subscription-Userinfo"))
		if h := resp.Header.Get("Profile-Update-Interval"); h != "" {
			res.UpdateIntervalH, _ = strconv.Atoi(strings.TrimSpace(h))
		}
		res.ProfileTitle = decodeTitle(resp.Header.Get("Profile-Title"))
		return nil
	}
	if err := do(&http.Client{Timeout: 25 * time.Second}, "direct"); err == nil {
		return res, nil
	}
	if proxyURL != "" {
		if pu, perr := url.Parse(proxyURL); perr == nil {
			pc := &http.Client{Timeout: 40 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
			if err := do(pc, "proxy"); err == nil {
				return res, nil
			}
		}
	}
	return res, fmt.Errorf("subscription fetch failed: %s", strings.Join(res.Attempts, "; "))
}

// ParseUserInfo parses "upload=1; download=2; total=3; expire=4".
func ParseUserInfo(h string) *UserInfo {
	if strings.TrimSpace(h) == "" {
		return nil
	}
	ui := &UserInfo{}
	for _, part := range strings.Split(h, ";") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) != 2 {
			continue
		}
		n, _ := strconv.ParseInt(strings.TrimSpace(kv[1]), 10, 64)
		switch strings.ToLower(strings.TrimSpace(kv[0])) {
		case "upload":
			ui.Upload = n
		case "download":
			ui.Download = n
		case "total":
			ui.Total = n
		case "expire":
			ui.Expire = n
		}
	}
	return ui
}

func decodeTitle(v string) string {
	v = strings.TrimSpace(v)
	if strings.HasPrefix(v, "base64:") {
		if b, err := decodeB64(strings.TrimPrefix(v, "base64:")); err == nil {
			return string(b)
		}
	}
	return v
}
