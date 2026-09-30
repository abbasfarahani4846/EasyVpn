package rpc

import (
	"encoding/json"
	"strings"
	"testing"

	"easyvpn/core/pkg/engine"
)

func newServer(t *testing.T) *Server {
	t.Helper()
	return &Server{Eng: engine.NewEngine(t.TempDir())}
}

func call(t *testing.T, s *Server, method string, args any) Response {
	t.Helper()
	a, _ := json.Marshal(args)
	req, _ := json.Marshal(Request{ID: "1", Method: method, Args: a})
	var resp Response
	if err := json.Unmarshal(s.Handle(req), &resp); err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestImportExportRoundTripAndBackup(t *testing.T) {
	s := newServer(t)
	links := "vless://b831381d-6324-4d53-ad4f-8cda48b30811@h.example.com:443?security=tls&sni=h.example.com&type=ws&path=%2Fw&encryption=none#a\ntrojan://pw@t.example.com:443?security=tls&sni=t.example.com#b"
	r := call(t, s, "ParseContent", map[string]string{"content": links})
	if r.Error != "" {
		t.Fatal(r.Error)
	}
	res := r.Result.(map[string]any)
	nodes := res["nodes"].([]any)
	if len(nodes) != 2 {
		t.Fatalf("want 2 nodes, got %d", len(nodes))
	}
	for _, f := range []string{"uri", "clash", "singbox"} {
		e := call(t, s, "Export", map[string]any{"format": f, "nodes": nodes})
		if e.Error != "" || e.Result.(map[string]any)["payload"] == "" {
			t.Fatalf("export %s: %v", f, e.Error)
		}
	}
	// exported URI list re-imports to the same node count
	exp := call(t, s, "Export", map[string]any{"format": "uri", "nodes": nodes}).Result.(map[string]any)["payload"].(string)
	r = call(t, s, "ParseContent", map[string]string{"content": exp})
	if len(r.Result.(map[string]any)["nodes"].([]any)) != 2 {
		t.Fatal("re-import lost nodes")
	}

	enc := call(t, s, "BackupEncrypt", map[string]any{"data": map[string]any{"nodes": nodes}, "passphrase": "pw"})
	blob := enc.Result.(map[string]any)["blob"].(string)
	if dec := call(t, s, "BackupDecrypt", map[string]string{"blob": blob, "passphrase": "pw"}); dec.Error != "" {
		t.Fatal(dec.Error)
	}
	if dec := call(t, s, "BackupDecrypt", map[string]string{"blob": blob, "passphrase": "bad"}); !strings.Contains(dec.Error, "wrong passphrase") {
		t.Fatalf("want wrong passphrase error, got %q", dec.Error)
	}
}

func TestCountryAndRulesStatus(t *testing.T) {
	s := newServer(t)
	r := call(t, s, "SetCountry", map[string]string{"country": "ir"})
	if r.Error != "" {
		t.Fatal(r.Error)
	}
	st := call(t, s, "RuleSetStatus", nil)
	list := st.Result.(map[string]any)["statuses"].([]any)
	if len(list) < 8 {
		t.Fatalf("expected IR statuses, got %d", len(list))
	}
	for _, it := range list {
		if !it.(map[string]any)["present"].(bool) {
			t.Fatalf("baseline should make every IR rule-set present: %v", it)
		}
	}
	if d := call(t, s, "DetectCountry", map[string]string{"locale": "fa_IR"}); d.Result.(map[string]any)["country"] != "ir" {
		t.Fatalf("detect failed: %+v", d)
	}
}

func TestStartUnsupportedNodeIsTypedError(t *testing.T) {
	s := newServer(t)
	// AmneziaWG needs the mihomo engine, which is not bundled: neither sing-box nor Xray can run it.
	node := map[string]any{"name": "x", "type": "wireguard", "server": "h.example.com", "port": 51820,
		"wireguard": map[string]any{"private_key": "eCtX0T4W4+Z7JPVQvZkYtUvYB4m0mpXGpjD5jT4tkVk=", "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
			"local_address": []string{"10.0.0.2/32"}, "awg": map[string]string{"jc": "4"}}}
	r := call(t, s, "Start", map[string]any{"node": node, "mode": "proxy_only"})
	if !strings.Contains(r.Error, "unsupported_by_core:awg") {
		t.Fatalf("want typed capability error, got %q", r.Error)
	}
	if st := call(t, s, "GetState", nil).Result.(map[string]any)["state"]; st != "error" {
		t.Fatalf("state should be error, got %v", st)
	}
}

func TestUnknownMethod(t *testing.T) {
	if r := call(t, newServer(t), "Nope", nil); r.Error == "" {
		t.Fatal("expected error")
	}
}

func TestSealOpen(t *testing.T) {
	s := newServer(t)
	key := "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=" // 32 bytes
	enc := call(t, s, "Seal", map[string]any{"key": key, "items": []string{"secret-1", "secret-2"}})
	if enc.Error != "" {
		t.Fatal(enc.Error)
	}
	items := enc.Result.(map[string]any)["items"].([]any)
	dec := call(t, s, "Open", map[string]any{"key": key, "items": items})
	got := dec.Result.(map[string]any)["items"].([]any)
	if got[0] != "secret-1" || got[1] != "secret-2" {
		t.Fatalf("round trip failed: %v (%s)", got, dec.Error)
	}
}

func TestXhttpNodeStartsThroughXraySidecar(t *testing.T) {
	s := newServer(t)
	node := map[string]any{"name": "x", "type": "vless", "server": "127.0.0.1", "port": 9, "uuid": "b831381d-6324-4d53-ad4f-8cda48b30811",
		"encryption": "none", "transport": map[string]any{"type": "xhttp", "path": "/x"}}
	r := call(t, s, "Start", map[string]any{"node": node, "mode": "proxy_only", "local_port": 24080})
	if r.Error != "" {
		t.Fatalf("xhttp node must start via the xray sidecar: %s", r.Error)
	}
	if st := call(t, s, "GetState", nil).Result.(map[string]any)["state"]; st != "connected" {
		t.Fatalf("state=%v", st)
	}
	if e := call(t, s, "Stop", nil); e.Error != "" {
		t.Fatal(e.Error)
	}
}
