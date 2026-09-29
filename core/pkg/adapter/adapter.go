// Package adapter defines the pluggable core-engine interface and the
// sing-box based implementation. Future engines (mihomo, Xray-core, ...)
// implement the same CoreAdapter interface.
package adapter

import (
	"context"
	"fmt"
	"net/netip"
	"sync"
	"time"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/common/trafficcontrol"
	"github.com/sagernet/sing-box/common/urltest"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
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

// StartRequest fully describes a requested tunnel session.
type StartRequest struct {
	Node      *protocol.ProxyNode
	Routing   router.Model
	LocalPort int  // mixed-in listener port; 0 => 2080
	BindLocal bool // bind 127.0.0.1 instead of 0.0.0.0 (recommended)
	CacheDir  string
	LogLevel  string
	StatsHook func(Stats)
	LogHook   func(level, msg string)
	StateHook func(state, detail string)
}

// CoreAdapter abstracts a tunnel engine implementation.
type CoreAdapter interface {
	Name() string
	Start(ctx context.Context, req *StartRequest) error
	Stop(ctx context.Context) error
	SwitchNode(ctx context.Context, node *protocol.ProxyNode) error
	// UrlTest measures real proxy latency through a running instance.
	UrlTest(ctx context.Context, node *protocol.ProxyNode, timeoutMs int) (int64, error)
	Running() bool
}

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
}

func NewSingBoxAdapter() *SingBoxAdapter { return &SingBoxAdapter{} }

func (a *SingBoxAdapter) Name() string { return "sing-box" }

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

	opts, err := BuildOptions(req)
	if err != nil {
		return fmt.Errorf("build options: %w", err)
	}

	boxCtx := include.Context(ctx)
	// PlatformLogWriter captures log lines AND guarantees box.New registers
	// the traffic manager (needClashAPI path includes PlatformLogWriter != nil).
	instance, err := box.New(box.Options{
		Context:           boxCtx,
		Options:           opts,
		PlatformLogWriter: &platformLogger{hook: req.LogHook},
	})
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
	a.stopCh = make(chan struct{})
	if req.StatsHook != nil {
		go a.statsLoop()
	}
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

func (a *SingBoxAdapter) SwitchNode(_ context.Context, _ *protocol.ProxyNode) error {
	// Hot switching via the selector outbound lands with the clash-API build
	// tag in Phase 4; until then the engine restarts the session.
	return fmt.Errorf("hot node switch not yet supported; restart the session instead")
}

// UrlTest measures real proxy round-trip latency through a running box by
// dialing the test URL through the box's "proxy" outbound.
func (a *SingBoxAdapter) UrlTest(ctx context.Context, node *protocol.ProxyNode, timeoutMs int) (int64, error) {
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
	ms, err := urltest.URLTest(ctx, "", out)
	if err != nil {
		return 0, err
	}
	if ms <= 0 {
		ms = 1
	}
	return int64(ms), nil
}

func (a *SingBoxAdapter) statsLoop() {
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-a.stopCh:
			return
		case <-ticker.C:
			a.mu.Lock()
			tm := a.traffic
			hook := a.statsHook
			a.mu.Unlock()
			if tm == nil || hook == nil {
				continue
			}
			up, down := tm.Total()
			hook(Stats{
				TotalUpload:   up,
				TotalDownload: down,
				Connections:   int32(tm.ConnectionsLen()),
			})
		}
	}
}

// BuildOptions compiles the full sing-box option tree from our internal model.
// Exported so the engine can dump/validate generated configs.
func BuildOptions(req *StartRequest) (option.Options, error) {
	if req.Node == nil {
		return option.Options{}, fmt.Errorf("no node provided")
	}
	port := req.LocalPort
	if port <= 0 {
		port = 2080
	}

	outbound, err := buildOutbound(req.Node)
	if err != nil {
		return option.Options{}, err
	}

	listenAddr := badoption.Addr(netip.AddrFrom4([4]byte{127, 0, 0, 1}))
	routing := req.Routing
	opts := option.Options{
		Log: &option.LogOptions{
			Level:     orDefaultStr(routing.LogLevel, req.LogLevel, "info"),
			Timestamp: true,
		},		Inbounds: []option.Inbound{
			{
				Type: C.TypeMixed,
				Tag:  "mixed-in",
				Options: &option.HTTPMixedInboundOptions{
					ListenOptions: option.ListenOptions{
						Listen:     &listenAddr,
						ListenPort: uint16(port),
					},
				},
			},
		},
		Outbounds: []option.Outbound{outbound},
		Route: &option.RouteOptions{
			Rules:                 router.BuildRouteRules(routing),
			RuleSet:               router.BuildRuleSets(routing),
			Final:                 router.RouteFinal(routing),
			DefaultDomainResolver: &option.DomainResolveOptions{Server: "dns-local"},
		},
		DNS: router.BuildDNSOptions(routing),
	}
	return opts, nil
}

func orDefaultStr(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
