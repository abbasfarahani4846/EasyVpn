package engine

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// A real crash in a child process must land in crash.log and be reported by
// LastCrash (this is what "Copy diagnostics" shows after "core crashed").
func TestCrashLogCapturesPanic(t *testing.T) {
	if os.Getenv("EZ_CRASH_CHILD") != "" {
		InstallCrashLog(os.Getenv("EZ_CRASH_CHILD"))
		go func() { panic("boom from a goroutine") }()
		select {}
	}
	dir := t.TempDir()
	cmd := exec.Command(os.Args[0], "-test.run=TestCrashLogCapturesPanic")
	cmd.Env = append(os.Environ(), "EZ_CRASH_CHILD="+dir)
	_ = cmd.Run() // exits with status 2
	got := LastCrash(dir)
	if !strings.Contains(got, "panic: boom from a goroutine") || !strings.Contains(got, "goroutine") {
		t.Fatalf("crash not captured: %q", got)
	}
}
