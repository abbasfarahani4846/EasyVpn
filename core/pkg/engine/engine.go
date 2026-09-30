// Package engine owns the core lifecycle state machine and glues parser,
// pinger, router, rule-set sync, system proxy and the active CoreAdapter
// together. All user-facing events flow through the transport.Bus.
package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"easyvpn/core/pkg/adapter"
	"easyvpn/core/pkg/config"
	"easyvpn/core/pkg/geoip"
	"easyvpn/core/pkg/pinger"
	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
	"easyvpn/core/pkg/rulesync"
	"easyvpn/core/pkg/subs"
	"easyvpn/core/pkg/sysproxy"
	"easyvpn/core/pkg/transport"
)

type State string

const (
	StateDisconnected  State = "disconnected"
	StateConnecting    State = "connecting"
	StateConnected     State = "connected"
	StateDisconnecting State = "disconnecting"
	StateError         State = "error"
)

// StartParams describes a connection request.
type StartParams struct {
	Node       *protocol.ProxyNode   `json:"node"`
	Candidates []*protocol.ProxyNode `json:"candidates,omitempty"`
	Mode       string                `json:"mode"` // tun|system_proxy|both|proxy_only
	Tun        adapter.TunSettings   `json:"tun"`
	Tricks     *adapter.TLSTricks    `json:"tricks,omitempty"` // nil => country default
	Auth       *adapter.LocalAuth    `json:"auth,omitempty"`
	LocalPort  int                   `json:"local_port,omitempty"`
	AllowLAN   bool                  `json:"allow_lan,omitempty"`
	Bypass     []string              `json:"bypass,omitempty"` // system-proxy bypass list
	TestURL    string                `json:"test_url,omitempty"`
	// Chain: hops dialed before Node (proxy-in-proxy, exit via WARP, WARP-in-WARP).
	Chain []*protocol.ProxyNode `json:"chain,omitempty"`
}

// Engine is the single orchestrator instance owned by the C/RPC entry points.
type Engine struct {
	mu      sync.Mutex
	state   State
	errText string
	mode    adapter.ConnMode

	cacheDir string
	core     adapter.CoreAdapter
	bus      *transport.Bus
	parser   *config.Parser
	pinger   *pinger.Pinger
	rules    *rulesync.Manager
	sysProxy *sysproxy.Manager

	routing    router.Model
	tricks     adapter.TLSTricks
	activeNode *protocol.ProxyNode
	localPort  int
	stopFn     context.CancelFunc
	proxyOn    bool
	lastStart  StartParams

	sidecar *adapter.XraySidecar // Xray-core instance serving nodes sing-box cannot run

	rulesOnce sync.Once
	rulesErr  error
}

// NewEngine creates the engine and recovers any crash-leftover system proxy.
func NewEngine(cacheDir string) *Engine {
	PrepareRuntime(cacheDir)
	e := &Engine{
		state:    StateDisconnected,
		cacheDir: cacheDir,
		core:     adapter.NewSingBoxAdapter(),
		bus:      transport.NewBus(),
		parser:   config.NewParser(),
		pinger:   pinger.NewPinger(),
		routing:  router.Default(),
		sysProxy: sysproxy.New(cacheDir),
	}
	_ = e.sysProxy.Recover()
	return e
}

// Bus exposes the event pipeline for subscription (Dart side).
func (e *Engine) Bus() *transport.Bus { return e.bus }

func (e *Engine) GetState() State {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.state
}

// Info describes the build for the UI / diagnostics.
func (e *Engine) Info() map[string]any {
	return map[string]any{
		"core":         e.core.Name(),
		"version":      e.core.Version(),
		"capabilities": e.capabilities(),
		"protocols":    protocol.SupportedProtocols(),
		"system_proxy": e.sysProxy.Supported(),
	}
}

// capabilities is the union of every engine's optional node capabilities.
func (e *Engine) capabilities() []string {
	set := map[string]bool{}
	for _, c := range e.core.Capabilities() {
		set[c] = true
	}
	for c := range adapter.XrayCapabilities {
		set[c] = true
	}
	var out []string
	for c := range set {
		out = append(out, c)
	}
	sort.Strings(out)
	return out
}

func (e *Engine) setState(s State, detail string) {
	e.mu.Lock()
	e.state = s
	e.errText = detail
	mode := e.mode
	e.mu.Unlock()
	e.bus.Publish(transport.KindPriority, "state", map[string]string{
		"state":  string(s),
		"detail": detail,
		"mode":   string(mode),
	})
}

// rulesManager lazily creates the rule-set manager (extracts the baseline).
func (e *Engine) rulesManager() (*rulesync.Manager, error) {
	e.rulesOnce.Do(func() {
		e.rules, e.rulesErr = rulesync.New(filepath.Join(e.cacheDir, "rules"))
	})
	return e.rules, e.rulesErr
}

func (e *Engine) currentRouting() router.Model {
	e.mu.Lock()
	m := e.routing
	e.mu.Unlock()
	if rm, err := e.rulesManager(); err == nil {
		m.RuleSetDir = rm.Dir
	}
	return m
}

// ErrUnsupportedMode is returned when the platform cannot honor the mode.
var ErrUnsupportedMode = errors.New("connection mode not supported on this platform")

// Start starts a session through the active core adapter.
func (e *Engine) Start(p StartParams) error {
	node := p.Node
	if node == nil {
		return fmt.Errorf("no node")
	}
	node.EnsureID()
	adapter.NormalizeNode(node)
	for _, c := range p.Candidates {
		adapter.NormalizeNode(c)
	}
	for _, c := range p.Chain {
		if c != nil {
			c.EnsureID()
			adapter.NormalizeNode(c)
		}
	}
	mode := adapter.ParseConnMode(p.Mode)
	if mode == adapter.ModeSystemProxy && !e.sysProxy.Supported() {
		return fmt.Errorf("%w: system_proxy (use tun or proxy_only)", ErrUnsupportedMode)
	}

	e.mu.Lock()
	if e.state == StateConnecting || e.state == StateConnected {
		e.mu.Unlock()
		return fmt.Errorf("already connected; stop first")
	}
	e.activeNode = node
	e.mode = mode
	e.lastStart = p
	tricks := e.tricks
	if p.Tricks != nil {
		tricks = *p.Tricks
	}
	port := p.LocalPort
	if port <= 0 {
		port = e.localPort
	}
	if port <= 0 {
		port = 2080
	}
	ctx, cancel := context.WithCancel(context.Background())
	e.stopFn = cancel
	e.mu.Unlock()

	e.setState(StateConnecting, "")

	// Nodes that need Xray-core (XHTTP, ML-KEM, TCP HTTP header) run in an
	// in-process Xray sidecar exposed to sing-box as a loopback SOCKS upstream,
	// so TUN, DNS and routing keep working unchanged.
	runNode := node
	bypassPort := 0
	if adapter.NeedsXray(node) {
		// The bypass inbound keeps the sidecar out of the TUN and is also how a
		// chain reaches an Xray-only exit node.
		if mode.NeedsTUN() || len(p.Chain) > 0 {
			bypassPort = freeTCPPort()
		}
		sc, err := adapter.StartXraySidecarWith(node, adapter.SidecarOptions{BypassPort: bypassPort})
		if err != nil {
			e.setState(StateError, err.Error())
			cancel()
			return err
		}
		e.mu.Lock()
		e.sidecar = sc
		e.mu.Unlock()
		runNode = sc.Node()
	}

	req := &adapter.StartRequest{
		Node:             runNode,
		Candidates:       p.Candidates,
		Routing:          e.currentRouting(),
		Mode:             mode,
		Tun:              p.Tun,
		Tricks:           tricks,
		Auth:             p.Auth,
		LocalPort:        port,
		BindLocal:        true,
		AllowLAN:         p.AllowLAN,
		CacheDir:         e.cacheDir,
		LogLevel:         "info",
		TestURL:          p.TestURL,
		XrayBypassPort:   bypassPort,
		Chain:            p.Chain,
		ActiveViaSidecar: runNode != node,
		StatsHook: func(s adapter.Stats) {
			e.bus.Publish(transport.KindBulk, "stats", s)
		},
		LogHook: func(level, msg string) {
			e.bus.Publish(transport.KindBulk, "log", map[string]string{"level": level, "msg": msg})
		},
	}
	if err := e.core.Start(ctx, req); err != nil {
		e.closeSidecar()
		e.setState(StateError, err.Error())
		cancel()
		return err
	}

	// System proxy: only after the core is listening. Failure to set it must
	// not leave a half-connected state.
	if mode == adapter.ModeSystemProxy || mode == adapter.ModeBoth {
		bypass := p.Bypass
		if len(bypass) == 0 {
			bypass = sysproxy.DefaultBypass()
		}
		if err := e.sysProxy.Enable("127.0.0.1", port, bypass); err != nil {
			if mode == adapter.ModeSystemProxy {
				_ = e.sysProxy.Restore()
				_ = e.core.Stop(context.Background())
				cancel()
				e.setState(StateError, "system proxy: "+err.Error())
				return err
			}
			e.bus.Publish(transport.KindPriority, "log", map[string]string{"level": "warn", "msg": "system proxy unavailable, TUN only: " + err.Error()})
		} else {
			e.mu.Lock()
			e.proxyOn = true
			e.mu.Unlock()
		}
	}
	e.mu.Lock()
	e.localPort = port
	e.mu.Unlock()
	e.setState(StateConnected, "")
	if mode.NeedsTUN() {
		go e.selfCheck(p.TestURL)
	}
	return nil
}

// selfCheck fetches the test URL through the fresh tunnel and writes the verdict
// to the log, so "Copy diagnostics" tells whether the node or the tunnel is at fault.
func (e *Engine) selfCheck(url string) {
	if url == "" {
		url = "https://www.gstatic.com/generate_204"
	}
	pub := func(level, msg string) {
		e.bus.Publish(transport.KindPriority, "log", map[string]string{"level": level, "msg": msg})
	}
	var err error
	for i := 0; i < 3; i++ {
		time.Sleep(time.Duration(1+i) * time.Second)
		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
		_, err = e.core.HTTPGet(ctx, url)
		cancel()
		if err == nil {
			pub("info", "tunnel self-check ok: "+url)
			return
		}
	}
	pub("error", "tunnel self-check FAILED for "+url+": "+err.Error())
}

// StartWithNode is the legacy convenience wrapper (proxy_only / tun).
func (e *Engine) StartWithNode(node *protocol.ProxyNode, tunEnabled bool) error {
	m := "proxy_only"
	if tunEnabled {
		m = "tun"
	}
	return e.Start(StartParams{Node: node, Mode: m})
}

// Stop tears the session down and always restores the OS proxy.
func (e *Engine) Stop() error {
	e.setState(StateDisconnecting, "")
	e.mu.Lock()
	stopFn := e.stopFn
	e.stopFn = nil
	e.proxyOn = false
	e.mu.Unlock()

	_ = e.sysProxy.Restore()
	err := e.core.Stop(context.Background())
	e.closeSidecar()
	if stopFn != nil {
		stopFn()
	}
	e.setState(StateDisconnected, "")
	return err
}

func (e *Engine) closeSidecar() {
	e.mu.Lock()
	sc := e.sidecar
	e.sidecar = nil
	e.mu.Unlock()
	if sc != nil {
		_ = sc.Close()
	}
}

// Shutdown is called on app exit.
func (e *Engine) Shutdown() {
	if s := e.GetState(); s == StateConnected || s == StateConnecting {
		_ = e.Stop()
	}
	_ = e.sysProxy.Restore()
}

// SetRoutingModel replaces the routing model (applied at next start).
func (e *Engine) SetRoutingModel(m router.Model) {
	e.mu.Lock()
	e.routing = m
	e.mu.Unlock()
}

// GetRoutingModel returns the current model.
func (e *Engine) GetRoutingModel() router.Model { return e.currentRouting() }

// SetCountry selects the country pack: sets the country, loads its default
// service overrides and TLS-trick recommendation, and returns the pack.
func (e *Engine) SetCountry(cc string) (*rulesync.Country, error) {
	cc = strings.ToLower(strings.TrimSpace(cc))
	rm, err := e.rulesManager()
	if err != nil {
		return nil, err
	}
	pack := rm.CountryPack(cc)
	e.mu.Lock()
	e.routing.Country = strings.ToUpper(cc)
	if pack != nil {
		e.routing.ServiceOverrides = router.ServiceOverrides{
			Proxy: pack.ServiceOverrides.Proxy, Direct: pack.ServiceOverrides.Direct,
		}
		e.tricks.Fragment = pack.TLSTricks.Fragment
	} else {
		e.routing.ServiceOverrides = router.ServiceOverrides{}
	}
	e.mu.Unlock()
	return pack, nil
}

func (e *Engine) SetRoutingMode(mode router.RoutingMode) {
	e.mu.Lock()
	e.routing.Mode = mode
	e.mu.Unlock()
}

func (e *Engine) SetLocalPort(port int) {
	e.mu.Lock()
	e.localPort = port
	e.mu.Unlock()
}

// SetTricks stores the global TLS-trick toggles.
func (e *Engine) SetTricks(t adapter.TLSTricks) {
	e.mu.Lock()
	e.tricks = t
	e.mu.Unlock()
}

// DetectCountry runs local detection (SIM/locale/timezone).
func (e *Engine) DetectCountry(s geoip.Signals) geoip.Result { return geoip.Detect(s) }

// SwitchNode hot-swaps the active node; falls back to a restart when needed.
func (e *Engine) SwitchNode(node *protocol.ProxyNode) error {
	if node == nil {
		return fmt.Errorf("no node")
	}
	node.EnsureID()
	adapter.NormalizeNode(node)
	e.mu.Lock()
	viaSidecar := e.sidecar != nil
	chained := len(e.lastStart.Chain) > 0
	e.mu.Unlock()
	var err error
	if viaSidecar || chained || adapter.NeedsXray(node) {
		err = adapter.ErrNeedsRestart // the sidecar serves exactly one node
	} else {
		err = e.core.SwitchNode(context.Background(), node)
	}
	if err != nil {
		if errors.Is(err, adapter.ErrNeedsRestart) && e.GetState() == StateConnected {
			e.mu.Lock()
			p := e.lastStart
			e.mu.Unlock()
			if stopErr := e.Stop(); stopErr != nil {
				return stopErr
			}
			p.Node = node
			return e.Start(p)
		}
		return err
	}
	e.mu.Lock()
	e.activeNode = node
	e.mu.Unlock()
	return nil
}

func (e *Engine) ActiveNode() *protocol.ProxyNode {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.activeNode
}

// GetStats returns the latest snapshot.
func (e *Engine) GetStats() adapter.Stats { return e.core.LatestStats() }

// ParseSubscription proxies into the universal parser.
func (e *Engine) ParseSubscription(content string) ([]*protocol.ProxyNode, error) {
	return e.parser.ParseContent(content)
}

// ParseSubscriptionWithWarnings exposes warnings for the import preview UI.
func (e *Engine) ParseSubscriptionWithWarnings(content string) (*config.ParseResult, error) {
	return e.parser.ParseWithWarnings(content)
}

// FetchResult is a parsed subscription.
type FetchResult struct {
	Nodes    []*protocol.ProxyNode `json:"nodes"`
	Warnings []string              `json:"warnings,omitempty"`
	Via      string                `json:"via"`
	UserInfo *subs.UserInfo        `json:"userinfo,omitempty"`
	Interval int                   `json:"update_interval_hours,omitempty"`
	Title    string                `json:"title,omitempty"`
}

// FetchSubscription downloads and parses a subscription; when the direct
// attempt fails and a session is running it retries through the local proxy.
func (e *Engine) FetchSubscription(ctx context.Context, url, ua string, viaProxy bool) (*FetchResult, error) {
	proxyURL := ""
	if viaProxy {
		proxyURL = e.localProxyURL()
	}
	r, err := subs.Fetch(ctx, url, ua, proxyURL)
	if err != nil {
		return nil, err
	}
	pr, err := e.parser.ParseWithWarnings(r.Body)
	if err != nil {
		return nil, err
	}
	return &FetchResult{Nodes: pr.Nodes, Warnings: pr.Warnings, Via: r.Via, UserInfo: r.UserInfo,
		Interval: r.UpdateIntervalH, Title: r.ProfileTitle}, nil
}

// localProxyURL returns the running mixed inbound URL, or "".
func (e *Engine) localProxyURL() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.state != StateConnected || !e.mode.NeedsMixed() {
		return ""
	}
	auth := ""
	if e.lastStart.Auth != nil && e.lastStart.Auth.User != "" {
		auth = e.lastStart.Auth.User + ":" + e.lastStart.Auth.Pass + "@"
	}
	return fmt.Sprintf("http://%s127.0.0.1:%d", auth, e.localPort)
}

// SyncRuleSets refreshes rule-sets for the current country (or given tags),
// streaming one `ruleSync` event per tag. Falls back to the running proxy.
func (e *Engine) SyncRuleSets(ctx context.Context, tags []string) ([]rulesync.Event, error) {
	rm, err := e.rulesManager()
	if err != nil {
		return nil, err
	}
	e.mu.Lock()
	country := strings.ToLower(e.routing.Country)
	e.mu.Unlock()
	evs := rm.Sync(ctx, country, tags, e.localProxyURL(), func(ev rulesync.Event) {
		e.bus.Publish(transport.KindPriority, "ruleSync", ev)
	})
	return evs, nil
}

// RuleSetStatus lists cache state for the current country.
func (e *Engine) RuleSetStatus() ([]rulesync.Status, error) {
	rm, err := e.rulesManager()
	if err != nil {
		return nil, err
	}
	e.mu.Lock()
	country := strings.ToLower(e.routing.Country)
	e.mu.Unlock()
	return rm.Statuses(country), nil
}

// Rules exposes the manager (custom rule-sets, countries list).
func (e *Engine) Rules() (*rulesync.Manager, error) { return e.rulesManager() }

// TestNodesLatency runs a TCP-mode ping batch and streams batched results.
func (e *Engine) TestNodesLatency(ctx context.Context, nodes []*protocol.ProxyNode, mode pinger.Mode, onBatch func([]pinger.Result)) []pinger.Result {
	if mode == "" {
		mode = pinger.ModeTCP
	}
	return e.pinger.TestBatch(ctx, nodes, pinger.Options{
		Workers: 50,
		Timeout: 3 * time.Second,
		Mode:    mode,
		OnBatch: onBatch,
	})
}

// TestNodesURL measures real through-proxy latency in chunked throw-away
// boxes; results stream as `delay` events and are returned at the end.
func (e *Engine) TestNodesURL(ctx context.Context, nodes []*protocol.ProxyNode, url string, workers int, onBatch func([]adapter.URLTestResult)) []adapter.URLTestResult {
	return adapter.URLTestBatch(ctx, nodes, adapter.URLTestOptions{URL: url, Workers: workers, OnBatch: onBatch})
}

// DumpConfig renders the generated sing-box options for the debug screen.
func (e *Engine) DumpConfig(p StartParams) (string, error) {
	return adapter.DumpConfig(&adapter.StartRequest{
		Node: p.Node, Candidates: p.Candidates, Routing: e.currentRouting(),
		Mode: adapter.ParseConnMode(p.Mode), Tun: p.Tun, LocalPort: p.LocalPort,
	})
}

// ExitInfo describes the address the internet sees for the tunnel.
type ExitInfo struct {
	IP          string `json:"ip"`
	Country     string `json:"country"`
	CountryCode string `json:"countryCode"`
	City        string `json:"city"`
	ISP         string `json:"isp"`
	Source      string `json:"source"`
}

// defaultExitURLs are tried in order when the user did not set a custom URL.
var defaultExitURLs = []string{
	"https://ipwho.is/",
	"https://ipinfo.io/json",
	"http://ip-api.com/json/?fields=status,country,countryCode,city,query,isp",
	"https://api.ipify.org?format=json",
}

// LookupExit queries the user's URL first, then the defaults, through the running
// tunnel and normalizes the JSON of the well-known providers.
func (e *Engine) LookupExit(ctx context.Context, custom string) (*ExitInfo, error) {
	urls := defaultExitURLs
	if strings.TrimSpace(custom) != "" {
		urls = append([]string{strings.TrimSpace(custom)}, defaultExitURLs...)
	}
	var lastErr error
	for _, u := range urls {
		cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		b, err := e.core.HTTPGet(cctx, u)
		cancel()
		if err != nil {
			lastErr = fmt.Errorf("%s: %w", u, err)
			continue
		}
		if info := ParseExitJSON(b); info != nil {
			info.Source = u
			return info, nil
		}
		lastErr = fmt.Errorf("%s: unrecognized response", u)
	}
	return nil, lastErr
}

// ParseExitJSON normalizes ipwho.is / ipinfo.io / ip-api.com / ipify style answers.
func ParseExitJSON(b []byte) *ExitInfo {
	var m map[string]any
	if json.Unmarshal(b, &m) != nil {
		// a plain-text IP is acceptable too
		if ip := strings.TrimSpace(string(b)); net.ParseIP(ip) != nil {
			return &ExitInfo{IP: ip}
		}
		return nil
	}
	str := func(keys ...string) string {
		for _, k := range keys {
			if v, ok := m[k].(string); ok && v != "" {
				return v
			}
		}
		return ""
	}
	info := &ExitInfo{
		IP:          str("ip", "query", "origin"),
		Country:     str("country_name", "country"),
		CountryCode: str("country_code", "countryCode"),
		City:        str("city"),
		ISP:         str("isp", "org", "organization"),
	}
	if c, ok := m["connection"].(map[string]any); ok && info.ISP == "" {
		if v, ok := c["isp"].(string); ok {
			info.ISP = v
		}
	}
	// ipinfo.io returns the 2-letter code in "country"
	if info.CountryCode == "" && len(info.Country) == 2 {
		info.CountryCode, info.Country = info.Country, ""
	}
	if info.IP == "" || net.ParseIP(info.IP) == nil {
		return nil
	}
	return info
}

func freeTCPPort() int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}
