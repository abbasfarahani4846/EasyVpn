package engine

import (
	"context"
	"encoding/json"
	"strings"
	"sync"
	"time"
)

// Site is one IP/region-sensitive service checked through the tunnel.
type Site struct {
	Name string `json:"name"`
	URL  string `json:"url"`
	// Blocked lists body markers (lower-case) that mean "region / IP blocked"
	// even when the HTTP status looks fine.
	Blocked []string `json:"blocked,omitempty"`
	// OKStatus lists extra statuses that still mean "reachable, not blocked"
	// (e.g. 401 from an API that needs a key).
	OKStatus []int `json:"ok_status,omitempty"`
}

// SiteResult is the verdict for one site.
type SiteResult struct {
	Name    string `json:"name"`
	URL     string `json:"url"`
	Status  string `json:"status"` // ok | blocked | error
	HTTP    int    `json:"http,omitempty"`
	Ms      int64  `json:"ms,omitempty"`
	Detail  string `json:"detail,omitempty"`
	Country string `json:"country,omitempty"`
}

var geoMarkers = []string{
	"not available in your country", "isn't supported in your country",
	"is not supported in your country", "not supported in your region",
	"not available in your region", "unsupported_country", "unsupported country",
	"app unavailable", "unavailable in your region", "sorry, you have been blocked",
	"access denied", "error 1020",
}

// DefaultSites are services known to be strict about the client IP/region.
func DefaultSites() []Site {
	return []Site{
		{Name: "Google", URL: "https://www.google.com/generate_204"},
		{Name: "Gemini", URL: "https://gemini.google.com/app", Blocked: []string{"isn't supported in your country", "not available in your country", "not supported in your country"}},
		{Name: "ChatGPT API", URL: "https://api.openai.com/v1/models", OKStatus: []int{401}, Blocked: []string{"unsupported_country"}},
		{Name: "Claude", URL: "https://claude.ai/login", Blocked: []string{"app unavailable", "unavailable in your region"}},
		{Name: "YouTube", URL: "https://www.youtube.com/"},
		{Name: "Facebook", URL: "https://www.facebook.com/"},
		{Name: "Instagram", URL: "https://www.instagram.com/"},
		{Name: "X (Twitter)", URL: "https://x.com/"},
		{Name: "Telegram", URL: "https://web.telegram.org/"},
		{Name: "Spotify", URL: "https://open.spotify.com/"},
		{Name: "GitHub", URL: "https://github.com/"},
		{Name: "ipinfo.io", URL: "https://ipinfo.io/json"},
	}
}

// classify turns an HTTP answer into a verdict.
func classify(s Site, status int, body []byte) (string, string) {
	low := strings.ToLower(string(body))
	markers := append(append([]string{}, s.Blocked...), geoMarkers...)
	for _, m := range markers {
		if m != "" && strings.Contains(low, m) {
			return "blocked", m
		}
	}
	for _, ok := range s.OKStatus {
		if status == ok {
			return "ok", ""
		}
	}
	switch {
	case status == 403 || status == 451:
		return "blocked", "HTTP " + statusText(status)
	case status >= 200 && status < 400:
		return "ok", ""
	default:
		return "error", "HTTP " + statusText(status)
	}
}

// SiteCheck probes every site through the running tunnel (in parallel).
func (e *Engine) SiteCheck(ctx context.Context, sites []Site) ([]SiteResult, error) {
	if e.GetState() != StateConnected {
		return nil, errNotConnected
	}
	if len(sites) == 0 {
		sites = DefaultSites()
	}
	res := make([]SiteResult, len(sites))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 6)
	for i, s := range sites {
		wg.Add(1)
		go func(i int, s Site) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			r := SiteResult{Name: s.Name, URL: s.URL}
			pctx, cancel := context.WithTimeout(ctx, 15*time.Second)
			defer cancel()
			p, err := e.core.HTTPProbe(pctx, s.URL, 256<<10)
			if err != nil {
				r.Status, r.Detail = "error", shortErr(err)
			} else {
				r.HTTP, r.Ms = p.Status, p.Elapsed.Milliseconds()
				r.Status, r.Detail = classify(s, p.Status, p.Body)
				if strings.Contains(s.URL, "ipinfo.io") {
					var j struct {
						IP      string `json:"ip"`
						Country string `json:"country"`
						Org     string `json:"org"`
					}
					if json.Unmarshal(p.Body, &j) == nil && j.IP != "" {
						r.Country = j.Country
						r.Detail = j.IP + " · " + j.Org
					}
				}
			}
			res[i] = r
		}(i, s)
	}
	wg.Wait()
	return res, nil
}

func shortErr(err error) string {
	s := err.Error()
	if len(s) > 140 {
		s = s[:140] + "…"
	}
	return s
}

func statusText(i int) string {
	b, _ := json.Marshal(i)
	return string(b)
}

var errNotConnected = errorString("not_connected")

type errorString string

func (e errorString) Error() string { return string(e) }
