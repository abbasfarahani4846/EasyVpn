package sysproxy

import (
	"encoding/json"
	"os"
	"testing"
)

type fakeBackend struct {
	current string
	applied int
}

func (f *fakeBackend) snapshot() (json.RawMessage, error) { return json.Marshal(f.current) }
func (f *fakeBackend) apply(h string, p int, b []string) error {
	f.current = "proxy"
	f.applied++
	return nil
}
func (f *fakeBackend) restore(s json.RawMessage) error { return json.Unmarshal(s, &f.current) }

func TestEnableKeepsOriginalAndRestores(t *testing.T) {
	fb := &fakeBackend{current: "original"}
	m := &Manager{StateFile: t.TempDir() + "/s.json", b: fb}
	if err := m.Enable("127.0.0.1", 2080, DefaultBypass()); err != nil {
		t.Fatal(err)
	}
	if err := m.Enable("127.0.0.1", 2081, nil); err != nil { // second enable must not overwrite the snapshot
		t.Fatal(err)
	}
	if fb.current != "proxy" {
		t.Fatal("proxy not applied")
	}
	// Simulate crash + relaunch: a new manager with the same state file recovers.
	m2 := &Manager{StateFile: m.StateFile, b: fb}
	if err := m2.Recover(); err != nil {
		t.Fatal(err)
	}
	if fb.current != "original" {
		t.Fatalf("expected original restored, got %q", fb.current)
	}
	if _, err := os.Stat(m.StateFile); !os.IsNotExist(err) {
		t.Fatal("state file should be removed")
	}
}
