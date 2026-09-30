package engine

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime/debug"
	"time"
)

// CrashLogName is the file (inside the cache dir) that receives the Go
// runtime's panic / fatal-error output, so a crash is never silent.
const CrashLogName = "crash.log"

// InstallCrashLog routes unrecovered panics and fatal runtime errors to
// <cacheDir>/crash.log (appended, capped at ~256 KB).
func InstallCrashLog(cacheDir string) {
	if cacheDir == "" {
		return
	}
	p := filepath.Join(cacheDir, CrashLogName)
	if st, err := os.Stat(p); err == nil && st.Size() > 256<<10 {
		_ = os.Remove(p)
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return
	}
	fmt.Fprintf(f, "\n=== core started %s pid=%d ===\n", time.Now().Format(time.RFC3339), os.Getpid())
	_ = debug.SetCrashOutput(f, debug.CrashOptions{})
	// f stays open for the life of the process (the runtime writes to it on crash).
}

// LastCrash returns the tail of crash.log if the previous core run crashed
// (i.e. the log contains a panic / fatal error).
func LastCrash(cacheDir string) string {
	f, err := os.Open(filepath.Join(cacheDir, CrashLogName))
	if err != nil {
		return ""
	}
	defer f.Close()
	st, _ := f.Stat()
	const max = 24 << 10
	if st != nil && st.Size() > max {
		_, _ = f.Seek(st.Size()-max, io.SeekStart)
	}
	b, _ := io.ReadAll(f)
	s := string(b)
	for _, marker := range []string{"panic:", "fatal error:"} {
		if i := lastIndex(s, marker); i >= 0 {
			return s[i:]
		}
	}
	return ""
}

func lastIndex(s, sub string) int {
	for i := len(s) - len(sub); i >= 0; i-- {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
