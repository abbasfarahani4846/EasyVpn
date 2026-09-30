// Package rulesync downloads, validates and caches sing-box binary rule-sets
// (.srs) from verified GitHub sources. It replaces sing-box's deprecated
// remote rule-set download: the router declares "local" rule-sets pointing at
// this package's cache directory.
//
// Behaviour (docs/MASTER_PROMPT.md §F3): mirror list in order, retry through
// the running proxy when direct access fails (mandatory in Iran), 32 MB size
// cap, magic-byte validation, atomic rename, conditional requests (ETag), and
// a bundled baseline so first launch works offline.
package rulesync

import (
	"bytes"
	"context"
	"embed"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

//go:embed registry.json
var registryJSON []byte

//go:embed baseline/*.srs
var baselineFS embed.FS

// MaxSize is the hard download cap per rule-set.
const MaxSize = 32 << 20

// RuleSetEntry is one downloadable rule-set.
type RuleSetEntry struct {
	Tag          string   `json:"tag"`
	Category     string   `json:"category"` // country|ads|security|service|geo
	Format       string   `json:"format,omitempty"`
	URLs         []string `json:"urls"`
	RefreshHours int      `json:"refresh_hours,omitempty"`
	SHA256       string   `json:"sha256,omitempty"`
	Baseline     bool     `json:"baseline,omitempty"` // shipped inside the binary
	Disabled     bool     `json:"disabled,omitempty"`
}

// TLSTricks are per-country recommended anti-DPI defaults.
type TLSTricks struct {
	Fragment bool `json:"fragment"`
}

// ServiceOverrides mirrors router.ServiceOverrides without importing it.
type ServiceOverrides struct {
	Proxy  []string `json:"proxy,omitempty"`
	Direct []string `json:"direct,omitempty"`
}

// Country is a per-country pack.
type Country struct {
	Name             string           `json:"name"`
	TLD              string           `json:"tld,omitempty"`
	TLSTricks        TLSTricks        `json:"tls_tricks"`
	ServiceOverrides ServiceOverrides `json:"service_overrides"`
	RuleSets         []RuleSetEntry   `json:"rule_sets"`
}

// Registry is the parsed registry.json.
type Registry struct {
	Version   int                 `json:"version"`
	Countries map[string]*Country `json:"countries"`
	Global    struct {
		RuleSets []RuleSetEntry `json:"rule_sets"`
	} `json:"global"`
}

// LoadBuiltinRegistry parses the embedded registry.
func LoadBuiltinRegistry() (*Registry, error) {
	var r Registry
	if err := json.Unmarshal(registryJSON, &r); err != nil {
		return nil, err
	}
	return &r, nil
}

// Event describes the result of syncing one rule-set.
type Event struct {
	Tag    string `json:"tag"`
	Status string `json:"status"` // ok|not_modified|failed|baseline
	Bytes  int64  `json:"bytes,omitempty"`
	Source string `json:"source,omitempty"`
	Via    string `json:"via,omitempty"` // direct|proxy
	Error  string `json:"error,omitempty"`
}

// Status is the on-disk state of one cached rule-set.
type Status struct {
	Tag       string    `json:"tag"`
	Present   bool      `json:"present"`
	Bytes     int64     `json:"bytes"`
	FetchedAt time.Time `json:"fetched_at,omitempty"`
	Source    string    `json:"source,omitempty"`
	NextAt    time.Time `json:"next_refresh,omitempty"`
}

type meta struct {
	ETag         string    `json:"etag,omitempty"`
	LastModified string    `json:"last_modified,omitempty"`
	FetchedAt    time.Time `json:"fetched_at"`
	Source       string    `json:"source,omitempty"`
}

// Manager owns a cache directory of rule-sets.
type Manager struct {
	Dir string
	Reg *Registry
	// Client is used for direct downloads (default: 30 s timeout).
	Client *http.Client

	mu     sync.Mutex
	custom []RuleSetEntry
}

// New creates a manager, extracting the embedded baseline for any tag that is
// not cached yet.
func New(dir string) (*Manager, error) {
	reg, err := LoadBuiltinRegistry()
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	m := &Manager{Dir: dir, Reg: reg, Client: &http.Client{Timeout: 30 * time.Second}}
	m.loadCustom()
	if err := m.EnsureBaseline(); err != nil {
		return nil, err
	}
	return m, nil
}

// EnsureBaseline copies embedded rule-sets that are missing from the cache.
func (m *Manager) EnsureBaseline() error {
	entries, err := baselineFS.ReadDir("baseline")
	if err != nil {
		return err
	}
	for _, e := range entries {
		dst := filepath.Join(m.Dir, e.Name())
		if st, err := os.Stat(dst); err == nil && st.Size() > 0 {
			continue
		}
		data, err := baselineFS.ReadFile("baseline/" + e.Name())
		if err != nil {
			return err
		}
		if err := writeAtomic(dst, data); err != nil {
			return err
		}
	}
	return nil
}

// Entries returns the rule-sets for a country (country pack + global + custom),
// de-duplicated by tag (country entries win).
func (m *Manager) Entries(country string) []RuleSetEntry {
	m.mu.Lock()
	defer m.mu.Unlock()
	seen := map[string]bool{}
	var out []RuleSetEntry
	add := func(list []RuleSetEntry) {
		for _, e := range list {
			if e.Disabled || seen[e.Tag] {
				continue
			}
			seen[e.Tag] = true
			out = append(out, e)
		}
	}
	if c := m.Reg.Countries[strings.ToLower(country)]; c != nil {
		add(c.RuleSets)
	}
	add(m.Reg.Global.RuleSets)
	add(m.custom)
	return out
}

// CountryPack returns the pack for a country or nil.
func (m *Manager) CountryPack(country string) *Country {
	return m.Reg.Countries[strings.ToLower(country)]
}

// Countries lists available country codes.
func (m *Manager) Countries() []string {
	var out []string
	for k := range m.Reg.Countries {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// Statuses reports cache state for a country's rule-sets.
func (m *Manager) Statuses(country string) []Status {
	var out []Status
	for _, e := range m.Entries(country) {
		st := Status{Tag: e.Tag}
		if fi, err := os.Stat(m.path(e.Tag)); err == nil {
			st.Present, st.Bytes = true, fi.Size()
		}
		if mt := m.readMeta(e.Tag); mt != nil {
			st.FetchedAt, st.Source = mt.FetchedAt, mt.Source
			h := e.RefreshHours
			if h <= 0 {
				h = 24
			}
			st.NextAt = mt.FetchedAt.Add(time.Duration(h) * time.Hour)
		}
		out = append(out, st)
	}
	return out
}

// Due returns the tags whose refresh time has passed (or never fetched).
func (m *Manager) Due(country string, now time.Time) []string {
	var tags []string
	for _, s := range m.Statuses(country) {
		if s.FetchedAt.IsZero() || !now.Before(s.NextAt) {
			tags = append(tags, s.Tag)
		}
	}
	return tags
}

// Sync refreshes the given tags (all of the country's when tags is empty).
// proxyURL, when set (e.g. "http://127.0.0.1:2080"), is used as a fallback
// after direct attempts fail. onEvent is called once per tag.
func (m *Manager) Sync(ctx context.Context, country string, tags []string, proxyURL string, onEvent func(Event)) []Event {
	want := map[string]bool{}
	for _, t := range tags {
		want[t] = true
	}
	var events []Event
	for _, e := range m.Entries(country) {
		if len(want) > 0 && !want[e.Tag] {
			continue
		}
		if ctx.Err() != nil {
			break
		}
		ev := m.syncOne(ctx, e, proxyURL)
		events = append(events, ev)
		if onEvent != nil {
			onEvent(ev)
		}
	}
	return events
}

func (m *Manager) syncOne(ctx context.Context, e RuleSetEntry, proxyURL string) Event {
	ev := Event{Tag: e.Tag, Status: "failed"}
	var lastErr error
	try := func(client *http.Client, via string) bool {
		for _, u := range e.URLs {
			data, mt, notModified, err := m.fetch(ctx, client, u, m.readMeta(e.Tag))
			if err != nil {
				lastErr = err
				continue
			}
			if notModified {
				ev.Status, ev.Source, ev.Via = "not_modified", u, via
				m.touch(e.Tag, u)
				return true
			}
			if err := Validate(data); err != nil {
				lastErr = fmt.Errorf("%s: %w", u, err)
				continue
			}
			if e.SHA256 != "" && !strings.EqualFold(e.SHA256, sha256hex(data)) {
				lastErr = fmt.Errorf("%s: sha256 mismatch", u)
				continue
			}
			if err := writeAtomic(m.path(e.Tag), data); err != nil {
				lastErr = err
				continue
			}
			mt.Source = u
			m.writeMeta(e.Tag, mt)
			ev.Status, ev.Bytes, ev.Source, ev.Via = "ok", int64(len(data)), u, via
			return true
		}
		return false
	}
	if try(m.Client, "direct") {
		return ev
	}
	if proxyURL != "" {
		if pu, err := url.Parse(proxyURL); err == nil {
			pc := &http.Client{
				Timeout:   60 * time.Second,
				Transport: &http.Transport{Proxy: http.ProxyURL(pu)},
			}
			if try(pc, "proxy") {
				return ev
			}
		}
	}
	if lastErr != nil {
		ev.Error = lastErr.Error()
	}
	// The cached (or baseline) copy stays in place; report that.
	if _, err := os.Stat(m.path(e.Tag)); err == nil {
		ev.Status = "baseline"
	}
	return ev
}

func (m *Manager) fetch(ctx context.Context, c *http.Client, u string, prev *meta) (data []byte, mt *meta, notModified bool, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, nil, false, err
	}
	req.Header.Set("User-Agent", "EasyVPN-rulesync/1")
	if prev != nil {
		if prev.ETag != "" {
			req.Header.Set("If-None-Match", prev.ETag)
		}
		if prev.LastModified != "" {
			req.Header.Set("If-Modified-Since", prev.LastModified)
		}
	}
	resp, err := c.Do(req)
	if err != nil {
		return nil, nil, false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotModified {
		return nil, nil, true, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, nil, false, fmt.Errorf("%s: HTTP %d", u, resp.StatusCode)
	}
	if resp.ContentLength > MaxSize {
		return nil, nil, false, fmt.Errorf("%s: too large (%d bytes)", u, resp.ContentLength)
	}
	data, err = io.ReadAll(io.LimitReader(resp.Body, MaxSize+1))
	if err != nil {
		return nil, nil, false, err
	}
	if len(data) > MaxSize {
		return nil, nil, false, fmt.Errorf("%s: exceeds %d MB cap", u, MaxSize>>20)
	}
	return data, &meta{
		ETag:         resp.Header.Get("ETag"),
		LastModified: resp.Header.Get("Last-Modified"),
		FetchedAt:    time.Now().UTC(),
	}, false, nil
}

// Validate checks the sing-box .srs magic ("SRS" + version byte) and that the
// payload is not trivially empty.
func Validate(data []byte) error {
	if len(data) < 8 {
		return fmt.Errorf("rule-set too small")
	}
	if !bytes.HasPrefix(data, []byte("SRS")) {
		return fmt.Errorf("not a sing-box .srs file (bad magic)")
	}
	if data[3] == 0 || data[3] > 5 {
		return fmt.Errorf("unsupported .srs version %d", data[3])
	}
	return nil
}

// AddCustom registers (and persists) a user-defined rule-set.
func (m *Manager) AddCustom(e RuleSetEntry) error {
	if e.Tag == "" || len(e.URLs) == 0 {
		return fmt.Errorf("custom rule-set needs tag and url")
	}
	if strings.ContainsAny(e.Tag, `/\`) {
		return fmt.Errorf("invalid tag")
	}
	for _, u := range e.URLs {
		pu, err := url.Parse(u)
		if err != nil || pu.Scheme != "https" {
			return fmt.Errorf("custom rule-set URLs must be https: %q", u)
		}
	}
	e.Category = "custom"
	m.mu.Lock()
	replaced := false
	for i := range m.custom {
		if m.custom[i].Tag == e.Tag {
			m.custom[i], replaced = e, true
		}
	}
	if !replaced {
		m.custom = append(m.custom, e)
	}
	m.mu.Unlock()
	return m.saveCustom()
}

// RemoveCustom deletes a user-defined rule-set and its cache file.
func (m *Manager) RemoveCustom(tag string) error {
	m.mu.Lock()
	var kept []RuleSetEntry
	for _, e := range m.custom {
		if e.Tag != tag {
			kept = append(kept, e)
		}
	}
	m.custom = kept
	m.mu.Unlock()
	_ = os.Remove(m.path(tag))
	_ = os.Remove(m.path(tag) + ".meta")
	return m.saveCustom()
}

func (m *Manager) customPath() string { return filepath.Join(m.Dir, "custom.json") }

func (m *Manager) loadCustom() {
	if b, err := os.ReadFile(m.customPath()); err == nil {
		_ = json.Unmarshal(b, &m.custom)
	}
}

func (m *Manager) saveCustom() error {
	m.mu.Lock()
	b, _ := json.MarshalIndent(m.custom, "", "  ")
	m.mu.Unlock()
	return writeAtomic(m.customPath(), b)
}

func (m *Manager) path(tag string) string { return filepath.Join(m.Dir, tag+".srs") }

func (m *Manager) readMeta(tag string) *meta {
	b, err := os.ReadFile(m.path(tag) + ".meta")
	if err != nil {
		return nil
	}
	var mt meta
	if json.Unmarshal(b, &mt) != nil {
		return nil
	}
	return &mt
}

func (m *Manager) writeMeta(tag string, mt *meta) {
	b, _ := json.Marshal(mt)
	_ = writeAtomic(m.path(tag)+".meta", b)
}

func (m *Manager) touch(tag, source string) {
	mt := m.readMeta(tag)
	if mt == nil {
		mt = &meta{}
	}
	mt.FetchedAt, mt.Source = time.Now().UTC(), source
	m.writeMeta(tag, mt)
}

// writeAtomic writes via temp file + rename so readers never see a partial file.
func writeAtomic(dst string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".tmp-*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return err
	}
	if err := os.Rename(name, dst); err != nil {
		os.Remove(name)
		return err
	}
	return nil
}
