package windscribe

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"easyvpn/core/pkg/protocol"
)

const sampleList = `{"data":[
 {"id":65,"name":"US Central","country_code":"US","status":1,"premium_only":0,"groups":[
   {"id":156,"city":"Atlanta","nick":"Peachtree","pro":0,"wg_pubkey":"ciOW8sri5RR+ulCmENWpg5TVUFPz1URqHRk9zEYrYHg=","wg_endpoint":"atl-156-wg.whiskergalaxy.com"},
   {"id":86,"city":"Dallas","nick":"Ranch","pro":1,"wg_pubkey":"pASG4FD9LwOfJukT/wYbUF10gD6v8DVuv5hrNbiOnHQ=","wg_endpoint":"dfw-86-wg.whiskergalaxy.com"}]},
 {"id":7,"name":"Japan","country_code":"JP","status":1,"premium_only":1,"groups":[
   {"id":9,"city":"Tokyo","pro":1,"wg_pubkey":"k","wg_endpoint":"tyo-wg.whiskergalaxy.com"}]}],
 "info":{"revision":1}}`

func template() *protocol.ProxyNode {
	return &protocol.ProxyNode{Name: "ws", Type: protocol.ProtoWireGuard, Server: "atl-156-wg.whiskergalaxy.com", Port: 443,
		WireGuard: &protocol.WireGuardConfig{PrivateKey: "priv", PublicKey: "old", PreSharedKey: "psk", LocalAddress: []string{"100.64.1.2/32"}}}
}

func TestFetchAndExpand(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/serverlist/mob-v2/0/") {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write([]byte(sampleList))
	}))
	defer srv.Close()
	ListURL = srv.URL + "/serverlist/mob-v2"
	locs, err := FetchLocations(context.Background(), srv.Client(), false)
	if err != nil {
		t.Fatal(err)
	}
	tpl := template()
	if !IsWindscribeConfig(tpl) {
		t.Fatal("template should be detected as Windscribe")
	}
	free, err := Expand(tpl, locs, false)
	if err != nil || len(free) != 1 {
		t.Fatalf("free expand: %d %v", len(free), err)
	}
	n := free[0]
	if n.Server != "atl-156-wg.whiskergalaxy.com" || n.WireGuard.PublicKey != "ciOW8sri5RR+ulCmENWpg5TVUFPz1URqHRk9zEYrYHg=" ||
		n.WireGuard.PrivateKey != "priv" || n.WireGuard.PreSharedKey != "psk" || n.Port != 443 || !strings.Contains(n.Name, "Atlanta") {
		t.Fatalf("bad node %+v %+v", n, n.WireGuard)
	}
	all, _ := Expand(tpl, locs, true)
	if len(all) != 3 {
		t.Fatalf("pro expand = %d, want 3", len(all))
	}
	if tpl.WireGuard.PublicKey != "old" {
		t.Fatal("template must not be mutated")
	}
}

// Live check of the public list; opt-in.
func TestLivePublicList(t *testing.T) {
	if os.Getenv("EASYVPN_LIVE") != "1" {
		t.Skip("set EASYVPN_LIVE=1")
	}
	ListURL = "https://assets.windscribe.com/serverlist/mob-v2"
	locs, err := FetchLocations(context.Background(), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	free, err := Expand(template(), locs, false)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("%d locations, %d free WireGuard nodes, e.g. %s", len(locs), len(free), free[0].Name)
}
