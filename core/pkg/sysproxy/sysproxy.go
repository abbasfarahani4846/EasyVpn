// Package sysproxy sets and restores the operating-system HTTP/SOCKS proxy for
// the "system_proxy" and "both" connection modes (desktop only).
//
// Safety rule: the previous OS proxy settings are persisted to disk BEFORE they
// are overridden and restored on disconnect, on app exit and — via Recover() —
// on the next launch if a crash left the override in place.
package sysproxy

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

// ErrUnsupported is returned on platforms without a system proxy (mobile).
var ErrUnsupported = errors.New("system proxy is not supported on this platform")

// backend abstracts the OS specific operations.
type backend interface {
	snapshot() (json.RawMessage, error)
	apply(host string, port int, bypass []string) error
	restore(snap json.RawMessage) error
}

// Manager applies and restores the system proxy, persisting the prior state.
type Manager struct {
	StateFile string
	b         backend
	mu        sync.Mutex
}

// New creates a manager storing its recovery state under dir.
func New(dir string) *Manager {
	return &Manager{StateFile: filepath.Join(dir, "sysproxy_state.json"), b: platformBackend()}
}

// Supported reports whether the platform has a working backend.
func (m *Manager) Supported() bool { return m.b != nil }

// Enable points the OS proxy at host:port. bypass is a list of hosts/CIDRs that
// must not use the proxy. Calling Enable twice keeps the ORIGINAL snapshot.
func (m *Manager) Enable(host string, port int, bypass []string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.b == nil {
		return ErrUnsupported
	}
	if _, err := os.Stat(m.StateFile); errors.Is(err, os.ErrNotExist) {
		snap, err := m.b.snapshot()
		if err != nil {
			return err
		}
		if err := os.WriteFile(m.StateFile, snap, 0o600); err != nil {
			return err
		}
	}
	return m.b.apply(host, port, bypass)
}

// Restore puts the original settings back and forgets the snapshot.
func (m *Manager) Restore() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.b == nil {
		return nil
	}
	snap, err := os.ReadFile(m.StateFile)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if err := m.b.restore(snap); err != nil {
		return err
	}
	return os.Remove(m.StateFile)
}

// Recover restores a crash-leftover override (call once at startup).
func (m *Manager) Recover() error { return m.Restore() }

// DefaultBypass is the standard bypass list (LAN + loopback).
func DefaultBypass() []string {
	return []string{"localhost", "127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "*.local"}
}
