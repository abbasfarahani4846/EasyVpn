package warp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRegisterAndNode(t *testing.T) {
	var gotKey string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || !strings.HasSuffix(r.URL.Path, "/reg") {
			http.NotFound(w, r)
			return
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		gotKey, _ = body["key"].(string)
		_, _ = w.Write([]byte(`{"id":"dev1","token":"tok","account":{"warp_plus":false},
		 "config":{"client_id":"` + base64.StdEncoding.EncodeToString([]byte{1, 2, 3, 4}) + `",
		  "peers":[{"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=","endpoint":{"v4":"162.159.192.7:0","host":"engage.cloudflareclient.com:2408"}}],
		  "interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110::1"}}}}`))
	}))
	defer srv.Close()

	c := NewClient(srv.Client())
	c.API = srv.URL + "/v0a2158"
	a, err := c.Register(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if k, err := base64.StdEncoding.DecodeString(gotKey); err != nil || len(k) != 32 {
		t.Fatalf("public key sent to API is not a 32-byte base64 key: %q", gotKey)
	}
	if got := a.Reserved(); len(got) != 3 || got[0] != 1 || got[2] != 3 {
		t.Fatalf("reserved = %v", got)
	}
	n, err := a.Node("WARP A", "")
	if err != nil {
		t.Fatal(err)
	}
	if n.Server != "engage.cloudflareclient.com" || n.Port != 2408 || n.WireGuard.PublicKey == "" ||
		len(n.WireGuard.LocalAddress) != 2 || n.WireGuard.LocalAddress[0] != "172.16.0.2/32" {
		t.Fatalf("bad node: %+v %+v", n, n.WireGuard)
	}
	// Endpoint override (a scanned clean IP).
	n2, err := a.Node("WARP B", "188.114.97.1:894")
	if err != nil || n2.Server != "188.114.97.1" || n2.Port != 894 {
		t.Fatalf("override: %+v %v", n2, err)
	}
}
