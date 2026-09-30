package engine

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"easyvpn/core/pkg/protocol"
)

func TestClassifySiteAnswers(t *testing.T) {
	gem := Site{Name: "Gemini", Blocked: []string{"isn't supported in your country"}}
	api := Site{Name: "API", OKStatus: []int{401}, Blocked: []string{"unsupported_country"}}
	cases := []struct {
		s      Site
		status int
		body   string
		want   string
	}{
		{gem, 200, "<html>Gemini</html>", "ok"},
		{gem, 200, "Gemini isn't supported in your country yet", "blocked"},
		{api, 401, `{"error":"missing key"}`, "ok"},
		{api, 403, `{"error":{"code":"unsupported_country_region_territory"}}`, "blocked"},
		{Site{}, 451, "", "blocked"},
		{Site{}, 403, "", "blocked"},
		{Site{}, 302, "", "ok"},
		{Site{}, 502, "", "error"},
	}
	for _, c := range cases {
		if got, _ := classify(c.s, c.status, []byte(c.body)); got != c.want {
			t.Errorf("%s %d %q: got %s want %s", c.s.Name, c.status, c.body, got, c.want)
		}
	}
}

// End to end: through a real connection, each local "service" gets the right verdict.
func TestSiteCheckThroughTunnel(t *testing.T) {
	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("hello")) }))
	defer ok.Close()
	geo := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Sorry, this service is not available in your country"))
	}))
	defer geo.Close()
	forbid := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(403) }))
	defer forbid.Close()

	e := NewEngine(t.TempDir())
	if _, err := e.SiteCheck(context.Background(), nil); err == nil {
		t.Fatal("site check must require a connection")
	}
	node := &protocol.ProxyNode{Name: "up", Type: protocol.ProtoSocks, Server: "127.0.0.1", Port: startSocks(t)}
	if err := e.Start(StartParams{Node: node, Mode: "proxy_only", LocalPort: 26581}); err != nil {
		t.Fatal(err)
	}
	defer e.Stop()
	res, err := e.SiteCheck(context.Background(), []Site{
		{Name: "ok", URL: ok.URL}, {Name: "geo", URL: geo.URL}, {Name: "403", URL: forbid.URL},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"ok", "blocked", "blocked"}
	for i, r := range res {
		if r.Status != want[i] {
			t.Errorf("%s: got %s (%s) want %s", r.Name, r.Status, r.Detail, want[i])
		}
	}
}
