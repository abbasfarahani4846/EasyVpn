// Package geoip detects the user's country from cheap local signals (SIM,
// locale, timezone) with an optional egress-IP lookup. A manual override in
// settings always wins over the result (handled by the caller).
package geoip

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"
)

// Signals are the inputs supplied by the platform layer.
type Signals struct {
	SIMCountry     string `json:"sim_country,omitempty"`     // ISO-3166 alpha-2, e.g. "IR"
	NetworkCountry string `json:"network_country,omitempty"` // from telephony network
	Locale         string `json:"locale,omitempty"`          // "fa_IR", "fa-IR", "en_US", "fa"
	Timezone       string `json:"timezone,omitempty"`        // IANA, e.g. "Asia/Tehran"
}

// Result is the detection outcome.
type Result struct {
	Country    string  `json:"country"`    // lower-case alpha-2, "" if unknown
	Source     string  `json:"source"`     // sim|network|locale|timezone|language|ip|none
	Confidence float64 `json:"confidence"` // 0..1
}

var tzCountry = map[string]string{
	"Asia/Tehran": "ir", "Asia/Shanghai": "cn", "Asia/Urumqi": "cn", "Asia/Hong_Kong": "hk",
	"Europe/Moscow": "ru", "Europe/Kaliningrad": "ru", "Asia/Yekaterinburg": "ru", "Asia/Novosibirsk": "ru",
	"Asia/Vladivostok": "ru", "Asia/Istanbul": "tr", "Europe/Istanbul": "tr", "Asia/Kabul": "af",
	"Asia/Dubai": "ae", "Asia/Karachi": "pk", "Asia/Kolkata": "in", "Asia/Riyadh": "sa",
	"Europe/Kyiv": "ua", "Europe/Kiev": "ua", "Europe/Minsk": "by", "Asia/Tashkent": "uz",
}

var langCountry = map[string]string{"fa": "ir", "ru": "ru", "zh": "cn"}

// Detect applies the signal priority SIM > network > locale region > timezone > language.
func Detect(s Signals) Result {
	if c := norm(s.SIMCountry); c != "" {
		return Result{c, "sim", 0.95}
	}
	if c := norm(s.NetworkCountry); c != "" {
		return Result{c, "network", 0.85}
	}
	loc := strings.ReplaceAll(s.Locale, "-", "_")
	parts := strings.Split(loc, "_")
	if len(parts) >= 2 {
		if c := norm(parts[len(parts)-1]); c != "" {
			return Result{c, "locale", 0.7}
		}
	}
	if c, ok := tzCountry[s.Timezone]; ok {
		return Result{c, "timezone", 0.75}
	}
	if len(parts) >= 1 {
		if c, ok := langCountry[strings.ToLower(parts[0])]; ok {
			return Result{c, "language", 0.4}
		}
	}
	return Result{"", "none", 0}
}

func norm(c string) string {
	c = strings.ToLower(strings.TrimSpace(c))
	if len(c) != 2 {
		return ""
	}
	return c
}

// DefaultIPEndpoints are queried in order by LookupIP.
var DefaultIPEndpoints = []string{"https://api.country.is/", "https://ipwho.is/"}

// LookupIP asks a public endpoint for the country of the client's egress IP.
// client may route through the proxy to report the tunnel exit country.
func LookupIP(ctx context.Context, client *http.Client, endpoints []string) Result {
	if client == nil {
		client = &http.Client{Timeout: 6 * time.Second}
	}
	if len(endpoints) == 0 {
		endpoints = DefaultIPEndpoints
	}
	for _, ep := range endpoints {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, ep, nil)
		if err != nil {
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			continue
		}
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
		resp.Body.Close()
		var v struct {
			Country     string `json:"country"`
			CountryCode string `json:"country_code"`
		}
		if json.Unmarshal(b, &v) != nil {
			continue
		}
		if c := norm(v.Country); c != "" {
			return Result{c, "ip", 0.9}
		}
		if c := norm(v.CountryCode); c != "" {
			return Result{c, "ip", 0.9}
		}
	}
	return Result{"", "none", 0}
}
