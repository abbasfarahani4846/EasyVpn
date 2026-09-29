package rulesync

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestBaselineExtractedAndValid(t *testing.T) {
	dir := t.TempDir()
	m, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, tag := range []string{"geosite-ir", "geoip-ir", "geosite-ads-all"} {
		b, err := os.ReadFile(filepath.Join(dir, tag+".srs"))
		if err != nil {
			t.Fatalf("%s missing: %v", tag, err)
		}
		if err := Validate(b); err != nil {
			t.Fatalf("%s invalid: %v", tag, err)
		}
	}
	if len(m.Entries("ir")) < 8 {
		t.Fatalf("expected IR entries, got %d", len(m.Entries("ir")))
	}
	if len(m.Countries()) < 3 {
		t.Fatal("expected ir/cn/ru packs")
	}
}

func TestSyncMirrorFallbackAndConditional(t *testing.T) {
	base, _ := os.ReadFile("baseline/geoip-ir.srs")
	hits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		switch r.URL.Path {
		case "/bad":
			w.Write([]byte("<html>blocked</html>"))
		case "/good":
			if r.Header.Get("If-None-Match") == `"v1"` {
				w.WriteHeader(http.StatusNotModified)
				return
			}
			w.Header().Set("ETag", `"v1"`)
			w.Write(base)
		default:
			w.WriteHeader(404)
		}
	}))
	defer srv.Close()

	m, err := New(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := m.AddCustom(RuleSetEntry{Tag: "custom-x", URLs: []string{"https://example.invalid/x.srs"}}); err != nil {
		t.Fatal(err)
	}
	// Replace with test server URLs (bypass https check by direct struct edit).
	m.custom = []RuleSetEntry{{Tag: "custom-x", URLs: []string{srv.URL + "/bad", srv.URL + "/good"}}}

	ev := m.Sync(context.Background(), "xx", []string{"custom-x"}, "", nil)
	if len(ev) != 1 || ev[0].Status != "ok" || ev[0].Source != srv.URL+"/good" {
		t.Fatalf("unexpected event: %+v", ev)
	}
	ev = m.Sync(context.Background(), "xx", []string{"custom-x"}, "", nil)
	if ev[0].Status != "not_modified" {
		t.Fatalf("expected not_modified, got %+v", ev[0])
	}
}

func TestAddCustomRejectsHTTP(t *testing.T) {
	m, _ := New(t.TempDir())
	if err := m.AddCustom(RuleSetEntry{Tag: "a", URLs: []string{"http://x/y.srs"}}); err == nil {
		t.Fatal("expected https-only error")
	}
}
