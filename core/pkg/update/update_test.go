package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func fakeGitHub(t *testing.T, apk []byte) *httptest.Server {
	sum := sha256.Sum256(apk)
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/releases"):
			rels := []map[string]any{
				{"tag_name": "nightly", "prerelease": true, "html_url": "https://x/nightly", "body": "notes", "assets": []map[string]any{
					{"name": "EasyVPN-nightly-abc1234-android-arm64-v8a.apk", "browser_download_url": srv.URL + "/dl/app.apk"},
					{"name": "EasyVPN-nightly-abc1234-windows-x64-portable.zip", "browser_download_url": srv.URL + "/dl/w.zip"},
					{"name": "SHA256SUMS.txt", "browser_download_url": srv.URL + "/dl/sums"},
				}},
				{"tag_name": "v1.2.0", "prerelease": false, "assets": []map[string]any{
					{"name": "EasyVPN-1.2.0-linux-amd64.deb", "browser_download_url": srv.URL + "/dl/x.deb"},
				}},
			}
			_ = json.NewEncoder(w).Encode(rels)
		case r.URL.Path == "/dl/sums":
			_, _ = w.Write([]byte(hex.EncodeToString(sum[:]) + "  EasyVPN-nightly-abc1234-android-arm64-v8a.apk\n"))
		case r.URL.Path == "/dl/app.apk":
			_, _ = w.Write(apk)
		default:
			http.NotFound(w, r)
		}
	}))
	return srv
}

func TestCheckAndDownload(t *testing.T) {
	apk := []byte(strings.Repeat("apk-bytes", 1000))
	srv := fakeGitHub(t, apk)
	defer srv.Close()
	API = srv.URL

	info, err := Check(context.Background(), srv.Client(), "nightly", "nightly-0000000", Target{Platform: "android", Arch: "arm64"})
	if err != nil {
		t.Fatal(err)
	}
	if !info.Available || info.Latest != "nightly-abc1234" || info.Asset == nil || len(info.SHA256) != 64 {
		t.Fatalf("unexpected info: %+v", info)
	}
	// Same build -> no update; dev builds never update.
	if i, _ := Check(context.Background(), srv.Client(), "nightly", "nightly-abc1234", Target{Platform: "android"}); i.Available {
		t.Fatal("same label must not be an update")
	}
	if i, _ := Check(context.Background(), srv.Client(), "nightly", "dev", Target{Platform: "android"}); i.Available {
		t.Fatal("dev build must not auto-update")
	}
	// Stable channel picks v1.2.0 and the deb for linux/deb.
	if i, _ := Check(context.Background(), srv.Client(), "stable", "1.1.0", Target{Platform: "linux", Package: "deb"}); !i.Available || i.Latest != "1.2.0" {
		t.Fatalf("stable: %+v", i)
	}

	dir := t.TempDir()
	path, err := Download(context.Background(), srv.Client(), info.Asset.URL, dir, info.Asset.Name, info.SHA256, nil)
	if err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(path); string(b) != string(apk) {
		t.Fatal("downloaded bytes differ")
	}
	// Tampered checksum is refused and leaves no file behind.
	bad := strings.Repeat("0", 64)
	if _, err := Download(context.Background(), srv.Client(), info.Asset.URL, dir, "x.apk", bad, nil); err == nil {
		t.Fatal("checksum mismatch must fail")
	}
	if _, err := os.Stat(dir + "/x.apk"); err == nil {
		t.Fatal("mismatched file must be removed")
	}
	if _, err := Download(context.Background(), srv.Client(), info.Asset.URL, dir, "y.apk", "", nil); err == nil {
		t.Fatal("missing checksum must be refused")
	}
}
