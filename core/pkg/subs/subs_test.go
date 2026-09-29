package subs

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchParsesHeaders(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Subscription-Userinfo", "upload=1; download=2; total=30; expire=99")
		w.Header().Set("Profile-Update-Interval", "6")
		w.Write([]byte("vless://x"))
	}))
	defer srv.Close()
	r, err := Fetch(context.Background(), srv.URL, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if r.Body != "vless://x" || r.UserInfo.Total != 30 || r.UserInfo.Expire != 99 || r.UpdateIntervalH != 6 || r.Via != "direct" {
		t.Fatalf("%+v %+v", r, r.UserInfo)
	}
}

func TestFetchFallsBackToProxy(t *testing.T) {
	// Direct target that always 500s; "proxy" is a fake forward proxy that serves content.
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("via-proxy")) }))
	defer proxy.Close()
	r, err := Fetch(context.Background(), "http://blocked.example.invalid/sub", "", proxy.URL)
	if err != nil || r.Body != "via-proxy" || r.Via != "proxy" {
		t.Fatalf("err=%v r=%+v", err, r)
	}
}
