// Package adapter defines the pluggable core-engine interface and the
// sing-box based implementation. Future engines (mihomo, Xray-core, ...)
// implement the same CoreAdapter interface.
package adapter

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"

	box "github.com/sagernet/sing-box"
	sbadapter "github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/trafficcontrol"
	"github.com/sagernet/sing-box/common/urltest"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/auth"
	singjson "github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/common/json/badoption"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
)

// Stats is a traffic snapshot pushed by the running core.
type Stats struct {
	UploadSpeed   int64 `json:"upload_speed"`
	DownloadSpeed int64 `json:"download_speed"`
	TotalUpload   int64 `json:"total_upload"`
	TotalDownload int64 `json:"total_download"`
	Connections   int32 `json:"connections"`
}

// ConnMode selects which local inbounds the core creates.
type ConnMode string

const (
	ModeTUN         ConnMode = "tun"          // TUN inbound only
	ModeSystemProxy ConnMode = "system_proxy" // mixed inbound; caller sets the OS proxy
	ModeBoth        ConnMode = "both"         // TUN + mixed inbound (+ OS proxy set by caller)
	ModeProxyOnly   ConnMode = "proxy_only"   // mixed inbound, no OS changes
)

// NeedsTUN / NeedsMixed tell which inbounds a mode requires.
func (m ConnMode) NeedsTUN() bool   { return m == ModeTUN || m == ModeBoth }
func (m ConnMode) NeedsMixed() bool { return m != ModeTUN }

// ParseConnMode normalizes user input; unknown values default to proxy_only.
func ParseConnMode(v string) ConnMode {
	switch ConnMode(v) {
	case ModeTUN, ModeSystemProxy, ModeBoth, ModeProxyOnly:
		return ConnMode(v)
	}
	return ModeProxyOnly
}

// TunSettings configures the TUN inbound.
type TunSettings struct {
	MTU         uint32 `json:"mtu,omitempty"`
	StrictRoute bool   `json:"strict_route,omitempty"`
	IPv6        bool   `json:"ipv6,omitempty"`
	// FD is a host-provided TUN file descriptor (Android VpnService). When set the
	// core uses it instead of creating its own interface.
	FD              int      `json:"fd,omitempty"`
	IncludePackages []string `json:"include_packages,omitempty"` // Android per-app allow list
	ExcludePackages []string `json:"exclude_packages,omitempty"` // Android per-app deny list
	ExcludeIfaces   []string `json:"exclude_ifaces,omitempty"`
}

// TLSTricks are global anti-DPI toggles applied to every TLS-enabled node.
type TLSTricks struct {
	Fragment       bool `json:"fragment"`
	RecordFragment bool `json:"record_fragment"`
}

// LocalAuth optionally protects the mixed inbound with username/password.
type LocalAuth struct {
	User string `json:"user"`
	Pass string `json:"pass"`
}

// StartRequest fully describes a requested tunnel session.
type StartRequest struct {
	Node       *protocol.ProxyNode   // active node
	Candidates []*protocol.ProxyNode // extra nodes materialized for hot switching / auto-test (capped)
	Routing    router.Model
	Mode       ConnMode
	Tun        TunSettings
	Tricks     TLSTricks
	Auth       *LocalAuth
	LocalPort  int  // mixed-in listener port; 0 => 2080
	BindLocal  bool // bind 127.0.0.1 instead of 0.0.0.0 (recommended)
	AllowLAN   bool
	CacheDir   string
	LogLevel   string
	TestURL    string // connectivity/latency probe (urltest group); default gstatic 204
	// XrayBypassPort, when > 0, opens a loopback SOCKS inbound used only by the
	// Xray sidecar to reach its server; it is routed to the interface-bound
	// direct outbound so the sidecar never loops back into the TUN.
	XrayBypassPort int
	// Chain lists hops dialed before the active node (proxy-in-proxy, exit via
	// WARP, WARP-in-WARP). See chain.go.
	Chain []*protocol.ProxyNode
	// ActiveViaSidecar marks the active node as the Xray sidecar's loopback
	// SOCKS hop; the chain is then applied through XrayBypassPort.
	ActiveViaSidecar bool
	StatsHook        func(Stats)
	LogHook          func(level, msg string)
	StateHook        func(state, detail string)
}

// MaxMaterialized caps how many nodes are compiled into the running core.
const MaxMaterialized = 50

// CoreAdapter abstracts a tunnel engine implementation.
type CoreAdapter interface {
	Name() string
	Version() string
	// Capabilities lists node capabilities (protocol.Cap*) the engine honors.
	Capabilities() []string
	Start(ctx context.Context, req *StartRequest) error
	Stop(ctx context.Context) error
	// SwitchNode hot-swaps the active node without tearing the tunnel down. It
	// returns ErrNeedsRestart when the node is not part of the running core.
	SwitchNode(ctx context.Context, node *protocol.ProxyNode) error
	// UrlTest measures real proxy latency through a running instance.
	UrlTest(ctx context.Context, node *protocol.ProxyNode, testURL string, timeoutMs int) (int64, error)
	LatestStats() Stats
	Running() bool
	// HTTPGet fetches a plain-HTTP URL through the running tunnel.
	HTTPGet(ctx context.Context, rawURL string) ([]byte, error)
}

// ErrNeedsRestart is returned by SwitchNode when a full restart is required.
var ErrNeedsRestart = fmt.Errorf("node not materialized in running core; restart required")

// ---------------------------------------------------------------------------
// sing-box adapter
// ---------------------------------------------------------------------------

// platformLogger forwards sing-box log lines to a Dart-facing hook.
type platformLogger struct{ hook func(level, msg string) }

func (p *platformLogger) WriteMessage(level log.Level, message string) {
	if p.hook != nil {
		p.hook(log.FormatLevel(level), message)
	}
}

type SingBoxAdapter struct {
	mu        sync.Mutex
	instance  *box.Box
	traffic   *trafficcontrol.Manager
	history   *urltest.HistoryStorage
	statsHook func(Stats)
	stopCh    chan struct{}
	tags      map[string]string // node ID -> outbound tag
	latest    Stats
}

func NewSingBoxAdapter() *SingBoxAdapter { return &SingBoxAdapter{} }

func (a *SingBoxAdapter) Name() string { return "sing-box" }

func (a *SingBoxAdapter) Version() string {
	if bi, ok := debug.ReadBuildInfo(); ok {
		for _, d := range bi.Deps {
			if d.Path == "github.com/sagernet/sing-box" {
				return strings.TrimPrefix(d.Version, "v")
			}
		}
	}
	return C.Version
}

func (a *SingBoxAdapter) Capabilities() []string {
	var out []string
	for c, ok := range singboxCapabilities {
		if ok {
			out = append(out, c)
		}
	}
	return out
}

func (a *SingBoxAdapter) LatestStats() Stats {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.latest
}

func (a *SingBoxAdapter) Running() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.instance != nil
}

func (a *SingBoxAdapter) Start(ctx context.Context, req *StartRequest) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.instance != nil {
		return fmt.Errorf("adapter already running")
	}

	opts, tags, err := buildOptionsWithTags(req)
	if err != nil {
		return fmt.Errorf("build options: %w", err)
	}

	boxCtx := include.Context(ctx)
	// PlatformLogWriter captures log lines AND guarantees box.New registers
	// the traffic manager (needClashAPI path includes PlatformLogWriter != nil).
	boxOpts := box.Options{
		Context:           boxCtx,
		Options:           opts,
		PlatformLogWriter: &platformLogger{hook: req.LogHook},
	}
	if req.Tun.FD > 0 && req.Mode.NeedsTUN() {
		service.MustRegister[sbadapter.PlatformInterface](boxCtx, newFDPlatform(req.Tun.FD))
	}
	instance, err := box.New(boxOpts)
	if err != nil {
		return fmt.Errorf("create box: %w", err)
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		return fmt.Errorf("start box: %w", err)
	}

	a.instance = instance
	a.history = service.PtrFromContext[urltest.HistoryStorage](boxCtx)
	a.traffic = service.PtrFromContext[trafficcontrol.Manager](boxCtx)
	a.statsHook = req.StatsHook
	a.tags = tags
	a.latest = Stats{}
	a.stopCh = make(chan struct{})
	go a.statsLoop(a.stopCh)
	if req.StateHook != nil {
		req.StateHook("connected", "")
	}
	return nil
}

func (a *SingBoxAdapter) Stop(_ context.Context) error {
	a.mu.Lock()
	b := a.instance
	a.instance = nil
	a.traffic = nil
	a.history = nil
	a.tags = nil
	stopCh := a.stopCh
	a.stopCh = nil
	a.mu.Unlock()
	if stopCh != nil {
		close(stopCh)
	}
	if b == nil {
		return nil
	}
	return b.Close()
}

// selectable is implemented by sing-box's selector outbound.
type selectable interface{ SelectOutbound(tag string) bool }

func (a *SingBoxAdapter) SwitchNode(_ context.Context, node *protocol.ProxyNode) error {
	node.EnsureID()
	a.mu.Lock()
	b := a.instance
	tag, ok := a.tags[node.ID]
	a.mu.Unlock()
	if b == nil {
		return fmt.Errorf("box not running")
	}
	if !ok {
		return ErrNeedsRestart
	}
	out, found := b.Outbound().Outbound(selectorTag)
	if !found {
		return ErrNeedsRestart
	}
	sel, ok := out.(selectable)
	if !ok || !sel.SelectOutbound(tag) {
		return ErrNeedsRestart
	}
	return nil
}

// UrlTest measures real proxy round-trip latency through a running box by
// dialing the test URL through the box's "proxy" outbound.
func (a *SingBoxAdapter) UrlTest(ctx context.Context, node *protocol.ProxyNode, testURL string, timeoutMs int) (int64, error) {
	a.mu.Lock()
	b := a.instance
	a.mu.Unlock()
	if b == nil {
		return 0, fmt.Errorf("box not running")
	}
	out, ok := b.Outbound().Outbound("proxy")
	if !ok {
		return 0, fmt.Errorf("outbound \"proxy\" not found in running box")
	}
	if timeoutMs > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, time.Duration(timeoutMs)*time.Millisecond)
		defer cancel()
	}
	ms, err := urltest.URLTest(ctx, testURL, out)
	if err != nil {
		return 0, err
	}
	if ms <= 0 {
		ms = 1
	}
	return int64(ms), nil
}

func (a *SingBoxAdapter) statsLoop(stop chan struct{}) {
	defer func() { // stats are cosmetic; never crash the core over them
		if r := recover(); r != nil {
			fmt.Fprintln(os.Stderr, "stats loop panic:", r)
		}
	}()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	var lastUp, lastDown int64
	last := time.Now()
	for {
		select {
		case <-stop:
			return
		case now := <-ticker.C:
			a.mu.Lock()
			tm := a.traffic
			hook := a.statsHook
			a.mu.Unlock()
			if tm == nil {
				continue
			}
			up, down := tm.Total()
			dt := now.Sub(last).Seconds()
			var upBps, downBps int64
			if dt > 0 {
				upBps = int64(float64(up-lastUp) / dt)
				downBps = int64(float64(down-lastDown) / dt)
			}
			lastUp, lastDown, last = up, down, now
			st := Stats{
				UploadSpeed:   upBps,
				DownloadSpeed: downBps,
				TotalUpload:   up,
				TotalDownload: down,
				Connections:   int32(tm.ConnectionsLen()),
			}
			a.mu.Lock()
			a.latest = st
			a.mu.Unlock()
			if hook != nil {
				hook(st)
			}
		}
	}
}

const (
	selectorTag = "proxy"
	autoTag     = "auto"
	directTag   = "direct"
)

// BuildOptions compiles the full sing-box option tree from our internal model.
// Exported so the engine can dump/validate generated configs.
func BuildOptions(req *StartRequest) (option.Options, error) {
	o, _, err := buildOptionsWithTags(req)
	return o, err
}

// nodeTag returns the stable outbound tag of a node.
func nodeTag(n *protocol.ProxyNode) string {
	n.EnsureID()
	id := n.ID
	if len(id) > 12 {
		id = id[:12]
	}
	return "n-" + id
}

// applyTricks returns a copy of node with global TLS tricks applied.
func applyTricks(n *protocol.ProxyNode, t TLSTricks) *protocol.ProxyNode {
	if !t.Fragment && !t.RecordFragment {
		return n
	}
	c := *n
	if c.TLS != nil && c.TLS.Enabled {
		tls := *c.TLS
		tls.Fragment = tls.Fragment || t.Fragment
		tls.RecordFragment = tls.RecordFragment || t.RecordFragment
		c.TLS = &tls
	}
	return &c
}

func buildOptionsWithTags(req *StartRequest) (option.Options, map[string]string, error) {
	if req.Node == nil {
		return option.Options{}, nil, fmt.Errorf("no node provided")
	}
	mode := req.Mode
	if mode == "" {
		mode = ModeProxyOnly
	}
	port := req.LocalPort
	if port <= 0 {
		port = 2080
	}
	req.Node.EnsureID()

	// Materialize the active node first, then candidates (deduplicated, capped).
	list := []*protocol.ProxyNode{req.Node}
	seen := map[string]bool{req.Node.ID: true}
	for _, c := range req.Candidates {
		if c == nil || len(list) >= MaxMaterialized {
			continue
		}
		c.EnsureID()
		if seen[c.ID] {
			continue
		}
		seen[c.ID] = true
		list = append(list, c)
	}

	tags := map[string]string{}
	var outbounds []option.Outbound
	var endpoints []option.Endpoint
	var tagList []string
	chainObs, chainEps, lastHop, err := buildChain(req.Chain, req.Tricks)
	if err != nil {
		return option.Options{}, nil, err
	}
	outbounds = append(outbounds, chainObs...)
	endpoints = append(endpoints, chainEps...)
	for i, n := range list {
		id := n.ID
		tag := nodeTag(n)
		built, err := buildNode(applyTricks(n, req.Tricks), tag)
		if err != nil {
			if i == 0 {
				return option.Options{}, nil, err // the active node must compile
			}
			continue // an incompatible candidate is simply not materialized
		}
		// A sidecar-served active node is a loopback SOCKS hop: the chain is
		// applied inside Xray (it dials through the bypass inbound instead).
		if lastHop != "" && !(i == 0 && req.ActiveViaSidecar) {
			if built.Outbound != nil {
				setDetour(built.Outbound.Options, lastHop)
			} else {
				setDetour(built.Endpoint.Options, lastHop)
			}
		}
		if built.Outbound != nil {
			outbounds = append(outbounds, *built.Outbound)
		} else {
			endpoints = append(endpoints, *built.Endpoint)
		}
		tags[id] = tag
		tagList = append(tagList, tag)
	}
	activeTag := tags[req.Node.ID]

	selOutbounds := append([]string{}, tagList...)
	if len(tagList) > 1 {
		outbounds = append(outbounds, option.Outbound{
			Type: C.TypeURLTest, Tag: autoTag,
			Options: &option.URLTestOutboundOptions{
				Outbounds: tagList,
				URL:       orDefaultStr(req.TestURL, "https://www.gstatic.com/generate_204"),
				Interval:  badoption.Duration(10 * time.Minute),
				Tolerance: 50,
			},
		})
		selOutbounds = append(selOutbounds, autoTag)
	}
	outbounds = append(outbounds,
		option.Outbound{
			Type: C.TypeSelector, Tag: selectorTag,
			Options: &option.SelectorOutboundOptions{Outbounds: selOutbounds, Default: activeTag},
		},
		option.Outbound{Type: C.TypeDirect, Tag: directTag, Options: &option.DirectOutboundOptions{}},
	)

	routing := req.Routing
	var inbounds []option.Inbound
	if mode.NeedsMixed() {
		listen := badoption.Addr(netip.AddrFrom4([4]byte{127, 0, 0, 1}))
		if req.AllowLAN {
			listen = badoption.Addr(netip.IPv4Unspecified())
		}
		mixed := &option.HTTPMixedInboundOptions{
			ListenOptions: option.ListenOptions{Listen: &listen, ListenPort: uint16(port)},
		}
		if req.Auth != nil && req.Auth.User != "" {
			mixed.Users = []auth.User{{Username: req.Auth.User, Password: req.Auth.Pass}}
		}
		inbounds = append(inbounds, option.Inbound{Type: C.TypeMixed, Tag: "mixed-in", Options: mixed})
	}
	if mode.NeedsTUN() {
		inbounds = append(inbounds, option.Inbound{Type: C.TypeTun, Tag: "tun-in", Options: tunOptions(req.Tun)})
	}
	rules := router.BuildRouteRules(routing)
	if req.XrayBypassPort > 0 {
		lo := badoption.Addr(netip.AddrFrom4([4]byte{127, 0, 0, 1}))
		inbounds = append(inbounds, option.Inbound{Type: C.TypeSOCKS, Tag: xrayBypassTag, Options: &option.SocksInboundOptions{
			ListenOptions: option.ListenOptions{Listen: &lo, ListenPort: uint16(req.XrayBypassPort)},
		}})
		rules = append([]option.Rule{{Type: C.RuleTypeDefault, DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{Inbound: badoption.Listable[string]{xrayBypassTag}},
			RuleAction:     option.RuleAction{Action: C.RuleActionTypeRoute, RouteOptions: option.RouteActionOptions{Outbound: orDefaultStr(lastHop, directTag)}},
		}}}, rules...)
	}

	opts := option.Options{
		// The selector/urltest groups persist state in a cache file whose default
		// path is the relative "cache.db". The working directory is read-only on
		// Android, so the path must always point into the app cache directory.
		Experimental: &option.ExperimentalOptions{
			CacheFile: &option.CacheFileOptions{Enabled: true, Path: cacheFilePath(req.CacheDir)},
		},
		Log: &option.LogOptions{
			Level:     orDefaultStr(routing.LogLevel, req.LogLevel, "info"),
			Timestamp: true,
		},
		Inbounds:  inbounds,
		Outbounds: outbounds,
		Endpoints: endpoints,
		Route: &option.RouteOptions{
			Rules:                 rules,
			RuleSet:               router.BuildRuleSets(routing),
			Final:                 router.RouteFinal(routing),
			AutoDetectInterface:   mode.NeedsTUN() && req.Tun.FD <= 0,
			DefaultDomainResolver: &option.DomainResolveOptions{Server: router.DNSLocalTag},
		},
		DNS: router.BuildDNSOptions(routing),
	}
	return opts, tags, nil
}

const xrayBypassTag = "xray-bypass-in"

func tunOptions(t TunSettings) *option.TunInboundOptions {
	mtu := t.MTU
	if mtu == 0 {
		mtu = 9000
	}
	if t.FD > 0 && (mtu > 1500 || mtu < 576) {
		mtu = 1500
	}
	addrs := badoption.Listable[netip.Prefix]{netip.MustParsePrefix("172.19.0.1/30")}
	if t.IPv6 {
		addrs = append(addrs, netip.MustParsePrefix("fdfe:dcba:9876::1/126"))
	}
	o := &option.TunInboundOptions{
		MTU:         mtu,
		Address:     addrs,
		AutoRoute:   t.FD <= 0, // with a host fd the VpnService.Builder owns the routes
		StrictRoute: t.StrictRoute,
	}
	if t.FD > 0 {
		// Host-owned fd (Android): the app itself is excluded from the VPN, so the
		// kernel-socket "system" stack cannot see its own replies. gVisor runs
		// entirely inside the process and needs no routing help from the OS.
		o.Stack = "gvisor"
	}
	o.IncludePackage = t.IncludePackages
	o.ExcludePackage = t.ExcludePackages
	o.ExcludeInterface = t.ExcludeIfaces
	return o
}

func orDefaultStr(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// DumpConfig renders the compiled sing-box configuration as JSON (secrets are
// present — callers must redact before sharing).
func DumpConfig(req *StartRequest) (string, error) {
	opts, err := BuildOptions(req)
	if err != nil {
		return "", err
	}
	b, err := singjson.MarshalContext(include.Context(context.Background()), opts)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// ExportSingBox renders ALL given nodes as a standalone sing-box config
// (outbounds/endpoints + selector), for the "export profile" feature. Unlike
// the running core there is no materialization cap. Tags are node names.
func ExportSingBox(nodes []*protocol.ProxyNode) (string, error) {
	var opts option.Options
	var tags []string
	used := map[string]bool{}
	for _, n := range nodes {
		tag := n.Name
		if tag == "" || used[tag] {
			tag = nodeTag(n)
		}
		used[tag] = true
		built, err := buildNode(n, tag)
		if err != nil {
			continue // unsupported nodes are skipped from the export
		}
		if built.Outbound != nil {
			opts.Outbounds = append(opts.Outbounds, *built.Outbound)
		} else {
			opts.Endpoints = append(opts.Endpoints, *built.Endpoint)
		}
		tags = append(tags, tag)
	}
	if len(tags) == 0 {
		return "", fmt.Errorf("no exportable nodes")
	}
	opts.Outbounds = append(opts.Outbounds,
		option.Outbound{Type: C.TypeSelector, Tag: "proxy", Options: &option.SelectorOutboundOptions{Outbounds: tags, Default: tags[0]}},
		option.Outbound{Type: C.TypeDirect, Tag: "direct", Options: &option.DirectOutboundOptions{}})
	b, err := singjson.MarshalContext(include.Context(context.Background()), opts)
	return string(b), err
}

// HTTPGet performs a GET (http or https) through the running tunnel's "proxy"
// selector: this is how the app shows the REAL exit IP as seen from the internet.
func (a *SingBoxAdapter) HTTPGet(ctx context.Context, rawURL string) ([]byte, error) {
	a.mu.Lock()
	b := a.instance
	a.mu.Unlock()
	if b == nil {
		return nil, fmt.Errorf("box not running")
	}
	out, ok := b.Outbound().Outbound(selectorTag)
	if !ok {
		return nil, fmt.Errorf("proxy outbound not found")
	}
	u, err := url.Parse(rawURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return nil, fmt.Errorf("URL must start with http:// or https://")
	}
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			// The net/http transport layers TLS on top of the tunnel connection for https.
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return out.DialContext(ctx, network, M.ParseSocksaddr(addr))
			},
			DisableKeepAlives: true,
		},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "EasyVPN/1.0")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 { // generate_204 answers 204
		return nil, fmt.Errorf("HTTP %d from %s", resp.StatusCode, u.Host)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 64<<10))
}

// cacheFilePath returns an absolute, writable location for sing-box's cache file.
func cacheFilePath(dir string) string {
	if dir == "" {
		dir = os.TempDir()
	}
	_ = os.MkdirAll(dir, 0o755)
	return filepath.Join(dir, "singbox-cache.db")
}
