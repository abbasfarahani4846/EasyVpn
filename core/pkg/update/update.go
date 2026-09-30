// Package update checks GitHub Releases for a newer build and downloads the
// matching asset, verified against the release's SHA256SUMS.txt. The project
// is open source, so GitHub is the update server; nothing else is contacted.
package update

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Repo is the GitHub repository publishing releases.
var Repo = "abbasfarahani4846/EasyVpn"

// API is the GitHub REST base (overridable in tests).
var API = "https://api.github.com"

// Asset is one release file.
type Asset struct {
	Name string `json:"name"`
	URL  string `json:"browser_download_url"`
	Size int64  `json:"size"`
}

type release struct {
	TagName    string  `json:"tag_name"`
	Name       string  `json:"name"`
	Body       string  `json:"body"`
	Prerelease bool    `json:"prerelease"`
	Draft      bool    `json:"draft"`
	Published  string  `json:"published_at"`
	HTMLURL    string  `json:"html_url"`
	Assets     []Asset `json:"assets"`
}

// Info is the result of a check.
type Info struct {
	Available bool   `json:"available"`
	Current   string `json:"current"`
	Latest    string `json:"latest"` // label, e.g. "1.2.3" or "nightly-cb45312"
	Channel   string `json:"channel"`
	Notes     string `json:"notes,omitempty"`
	PageURL   string `json:"page_url,omitempty"`
	Published string `json:"published,omitempty"`
	Asset     *Asset `json:"asset,omitempty"`
	SHA256    string `json:"sha256,omitempty"`
}

// Target identifies the running build.
type Target struct {
	Platform string `json:"platform"` // android|windows|linux|macos
	Arch     string `json:"arch"`     // arm64|x86_64|x64|amd64
	Portable bool   `json:"portable"` // windows/linux portable package
	Package  string `json:"package"`  // linux: "deb" or "tar" (default tar)
}

var labelRe = regexp.MustCompile(`^EasyVPN-(.+?)-(android|windows|linux|macos)-`)

// Check finds the newest release on channel ("stable" or "nightly") and
// compares its label with current. Development builds ("dev", "") never
// report an update.
func Check(ctx context.Context, hc *http.Client, channel, current string, t Target) (*Info, error) {
	if hc == nil {
		hc = &http.Client{Timeout: 20 * time.Second}
	}
	if channel != "nightly" {
		channel = "stable"
	}
	var rels []release
	if err := getJSON(ctx, hc, fmt.Sprintf("%s/repos/%s/releases?per_page=15", strings.TrimRight(API, "/"), Repo), &rels); err != nil {
		return nil, err
	}
	var pick *release
	for i := range rels {
		r := &rels[i]
		if r.Draft {
			continue
		}
		if channel == "nightly" && r.Prerelease && r.TagName == "nightly" {
			pick = r
			break
		}
		if channel == "stable" && !r.Prerelease && strings.HasPrefix(r.TagName, "v") {
			pick = r
			break
		}
	}
	info := &Info{Current: current, Channel: channel}
	if pick == nil {
		return info, nil
	}
	info.Latest = releaseLabel(pick)
	info.Notes, info.PageURL, info.Published = pick.Body, pick.HTMLURL, pick.Published
	info.Asset = pickAsset(pick.Assets, t)
	if info.Asset != nil {
		if sums := findAsset(pick.Assets, "SHA256SUMS.txt"); sums != nil {
			if m, err := fetchSums(ctx, hc, sums.URL); err == nil {
				info.SHA256 = m[info.Asset.Name]
			}
		}
	}
	info.Available = current != "" && current != "dev" && info.Latest != "" && info.Latest != current && info.Asset != nil
	return info, nil
}

func releaseLabel(r *release) string {
	for _, a := range r.Assets {
		if m := labelRe.FindStringSubmatch(a.Name); m != nil {
			return m[1]
		}
	}
	return strings.TrimPrefix(r.TagName, "v")
}

func pickAsset(as []Asset, t Target) *Asset {
	var want []string
	switch t.Platform {
	case "android":
		if t.Arch == "x86_64" || t.Arch == "amd64" {
			want = []string{"-android-x86_64.apk"}
		} else {
			want = []string{"-android-arm64-v8a.apk"}
		}
	case "windows":
		if t.Portable {
			want = []string{"-windows-x64-portable.zip", "-windows-x64.zip"}
		} else {
			want = []string{"-windows-x64.zip"}
		}
	case "linux":
		switch {
		case t.Package == "deb":
			want = []string{"-linux-amd64.deb"}
		case t.Portable:
			want = []string{"-linux-x64-portable.tar.gz", "-linux-x64.tar.gz"}
		default:
			want = []string{"-linux-x64.tar.gz"}
		}
	case "macos":
		want = []string{"-macos-arm64.zip"}
	}
	for _, suf := range want {
		for i := range as {
			if strings.HasPrefix(as[i].Name, "EasyVPN-") && strings.HasSuffix(as[i].Name, suf) {
				return &as[i]
			}
		}
	}
	return nil
}

func findAsset(as []Asset, name string) *Asset {
	for i := range as {
		if as[i].Name == name {
			return &as[i]
		}
	}
	return nil
}

func getJSON(ctx context.Context, hc *http.Client, url string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "EasyVPN-updater")
	resp, err := hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("github: HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(out)
}

// fetchSums parses "sha256  filename" lines.
func fetchSums(ctx context.Context, hc *http.Client, url string) (map[string]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("sums: HTTP %d", resp.StatusCode)
	}
	m := map[string]string{}
	sc := bufio.NewScanner(io.LimitReader(resp.Body, 1<<20))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) >= 2 && len(f[0]) == 64 {
			m[strings.TrimPrefix(f[len(f)-1], "*")] = strings.ToLower(f[0])
		}
	}
	return m, sc.Err()
}

// Download fetches url into dir/name and verifies sha256 (mandatory: an update
// without a published checksum is refused). progress receives (done, total).
func Download(ctx context.Context, hc *http.Client, url, dir, name, sha string, progress func(done, total int64)) (string, error) {
	if len(sha) != 64 {
		return "", fmt.Errorf("refusing update: no SHA-256 published for %s", name)
	}
	if hc == nil {
		hc = &http.Client{}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "EasyVPN-updater")
	resp, err := hc.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download: HTTP %d", resp.StatusCode)
	}
	dst := filepath.Join(dir, filepath.Base(name))
	tmp := dst + ".part"
	f, err := os.Create(tmp)
	if err != nil {
		return "", err
	}
	h := sha256.New()
	var done int64
	buf := make([]byte, 256<<10)
	last := time.Time{}
	for {
		n, rerr := resp.Body.Read(buf)
		if n > 0 {
			if _, err := f.Write(buf[:n]); err != nil {
				f.Close()
				os.Remove(tmp)
				return "", err
			}
			h.Write(buf[:n])
			done += int64(n)
			if progress != nil && time.Since(last) > 200*time.Millisecond {
				progress(done, resp.ContentLength)
				last = time.Now()
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			f.Close()
			os.Remove(tmp)
			return "", rerr
		}
	}
	f.Close()
	if got := hex.EncodeToString(h.Sum(nil)); !strings.EqualFold(got, sha) {
		os.Remove(tmp)
		return "", fmt.Errorf("checksum mismatch for %s: got %s want %s", name, got, sha)
	}
	if progress != nil {
		progress(done, done)
	}
	if err := os.Rename(tmp, dst); err != nil {
		return "", err
	}
	return dst, nil
}
