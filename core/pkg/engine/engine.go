// Package engine owns the core lifecycle state machine and glues parser,
// pinger, router and the active CoreAdapter together. All user-facing events
// flow through the transport.Bus.
package engine

import (
	"context"
	"fmt"
	"sync"
	"time"

	"easyvpn/core/pkg/adapter"
	"easyvpn/core/pkg/config"
	"easyvpn/core/pkg/pinger"
	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
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

// Engine is the single orchestrator instance owned by the C entry points.
type Engine struct {
	mu      sync.Mutex
	state   State
	errText string

	cacheDir string
	core     adapter.CoreAdapter
	bus      *transport.Bus
	parser   *config.Parser
	pinger   *pinger.Pinger

	routing    router.Model
	activeNode *protocol.ProxyNode
	localPort  int
	startCtx   context.Context
	stopFn     context.CancelFunc
}

func NewEngine(cacheDir string) *Engine {
	e := &Engine{
		state:    StateDisconnected,
		cacheDir: cacheDir,
		core:     adapter.NewSingBoxAdapter(),
		bus:      transport.NewBus(),
		parser:   config.NewParser(),
		pinger:   pinger.NewPinger(),
		routing:  router.Default(),
	}
	return e
}

// Bus exposes the event pipeline for subscription (Dart side).
func (e *Engine) Bus() *transport.Bus { return e.bus }

func (e *Engine) GetState() State {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.state
}

func (e *Engine) setState(s State, detail string) {
	e.mu.Lock()
	e.state = s
	e.errText = detail
	e.mu.Unlock()
	e.bus.Publish(transport.KindPriority, "state", map[string]string{
		"state":  string(s),
		"detail": detail,
	})
}

// StartWithNode starts a session through the active core adapter.
func (e *Engine) StartWithNode(node *protocol.ProxyNode, tunEnabled bool) error {
	if node == nil {
		return fmt.Errorf("no node")
	}
	e.mu.Lock()
	if e.state == StateConnecting || e.state == StateConnected {
		e.mu.Unlock()
		return fmt.Errorf("already connected; stop first")
	}
	node.EnsureID()
	e.activeNode = node
	ctx, cancel := context.WithCancel(context.Background())
	e.startCtx, e.stopFn = ctx, cancel
	e.mu.Unlock()

	e.setState(StateConnecting, "")

	req := &adapter.StartRequest{
		Node:      node,
		Routing:   e.currentRouting(),
		LocalPort: e.localPort,
		BindLocal: true,
		CacheDir:  e.cacheDir,
		LogLevel:  "info",
		StatsHook: func(s adapter.Stats) {
			e.bus.Publish(transport.KindBulk, "stats", s)
		},
		LogHook: func(level, msg string) {
			e.bus.Publish(transport.KindBulk, "log", map[string]string{"level": level, "msg": msg})
		},
		StateHook: func(state, detail string) {
			// Adapter-level transitions; engine state is authoritative here.
		},
	}
	err := e.core.Start(ctx, req)
	if err != nil {
		e.setState(StateError, err.Error())
		cancel()
		return err
	}
	_ = tunEnabled // TUN integration lands with platform phases (fd handoff)
	e.setState(StateConnected, "")
	return nil
}

func (e *Engine) Stop() error {
	e.setState(StateDisconnecting, "")
	e.mu.Lock()
	stopFn := e.stopFn
	e.stopFn = nil
	e.mu.Unlock()

	err := e.core.Stop(context.Background())
	if stopFn != nil {
		stopFn()
	}
	e.setState(StateDisconnected, "")
	return err
}

// currentRouting snapshot helper.
func (e *Engine) currentRouting() router.Model {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.routing
}

// SetRoutingModel replaces the routing model (hot-apply at next start).
func (e *Engine) SetRoutingModel(m router.Model) {
	e.mu.Lock()
	e.routing = m
	e.mu.Unlock()
}

func (e *Engine) SetRoutingCountry(countryCode string) {
	e.mu.Lock()
	e.routing.Country = countryCode
	e.mu.Unlock()
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

func (e *Engine) SwitchNode(node *protocol.ProxyNode) error {
	if node == nil {
		return fmt.Errorf("no node")
	}
	node.EnsureID()
	if err := e.core.SwitchNode(context.Background(), node); err != nil {
		// Fallback path: full restart through the new node.
		if e.GetState() == StateConnected {
			if stopErr := e.Stop(); stopErr != nil {
				return stopErr
			}
			return e.StartWithNode(node, false)
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

// GetStats returns the latest snapshot via the adapter (pull fallback).
func (e *Engine) GetStats() adapter.Stats {
	if s, ok := e.core.(interface{ LatestStats() adapter.Stats }); ok {
		return s.LatestStats()
	}
	return adapter.Stats{}
}

// ParseSubscription proxies into the universal parser.
func (e *Engine) ParseSubscription(content string) ([]*protocol.ProxyNode, error) {
	return e.parser.ParseContent(content)
}

// ParseSubscriptionWithWarnings exposes warnings for the import preview UI.
func (e *Engine) ParseSubscriptionWithWarnings(content string) (*config.ParseResult, error) {
	return e.parser.ParseWithWarnings(content)
}

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
