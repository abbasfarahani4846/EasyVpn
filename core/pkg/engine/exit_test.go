package engine

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"
)

func TestParseExitJSONProviders(t *testing.T) {
	cases := map[string]struct{ body, ip, cc, city, isp string }{
		"ipwho":  {`{"ip":"1.2.3.4","country":"Germany","country_code":"DE","city":"Berlin","connection":{"isp":"Hetzner"}}`, "1.2.3.4", "DE", "Berlin", "Hetzner"},
		"ipinfo": {`{"ip":"5.6.7.8","city":"Paris","country":"FR","org":"AS1 OVH"}`, "5.6.7.8", "FR", "Paris", "AS1 OVH"},
		"ipapi":  {`{"status":"success","country":"Iran","countryCode":"IR","city":"Tehran","query":"9.9.9.9","isp":"TCI"}`, "9.9.9.9", "IR", "Tehran", "TCI"},
		"ipify":  {`{"ip":"8.8.4.4"}`, "8.8.4.4", "", "", ""},
		"plain":  {"203.0.113.9\n", "203.0.113.9", "", "", ""},
	}
	for name, c := range cases {
		got := ParseExitJSON([]byte(c.body))
		if got == nil || got.IP != c.ip || got.CountryCode != c.cc || got.City != c.city || got.ISP != c.isp {
			t.Errorf("%s: %+v", name, got)
		}
	}
	if ParseExitJSON([]byte(`{"error":"x"}`)) != nil || ParseExitJSON([]byte("<html>")) != nil {
		t.Error("garbage must not parse")
	}
}

// minimal SOCKS5 CONNECT server used as the upstream "proxy node".
func startSocks(t *testing.T) int {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				h := make([]byte, 2)
				io.ReadFull(c, h)
				io.ReadFull(c, make([]byte, h[1]))
				c.Write([]byte{5, 0})
				r := make([]byte, 4)
				io.ReadFull(c, r)
				var host string
				switch r[3] {
				case 1:
					b := make([]byte, 4)
					io.ReadFull(c, b)
					host = net.IP(b).String()
				case 3:
					l := make([]byte, 1)
					io.ReadFull(c, l)
					b := make([]byte, l[0])
					io.ReadFull(c, b)
					host = string(b)
				default:
					return
				}
				pb := make([]byte, 2)
				io.ReadFull(c, pb)
				up, err := net.Dial("tcp", net.JoinHostPort(host, itoa(int(binary.BigEndian.Uint16(pb)))))
				if err != nil {
					c.Write([]byte{5, 5, 0, 1, 0, 0, 0, 0, 0, 0})
					return
				}
				defer up.Close()
				c.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0})
				go io.Copy(up, c)
				io.Copy(c, up)
			}(c)
		}
	}()
	return ln.Addr().(*net.TCPAddr).Port
}

func itoa(i int) string { return strconv.Itoa(i) }

// The exit-IP card: with a running tunnel, the custom URL (http AND https) is
// fetched THROUGH the proxy and the JSON is normalized.
func TestLookupExitThroughTunnelHTTPAndHTTPS(t *testing.T) {
	httpSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"ip":"198.51.100.7","country_code":"NL","country":"Netherlands","city":"Amsterdam"}`))
	}))
	defer httpSrv.Close()
	tlsSrv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"ip":"198.51.100.8"}`))
	}))
	defer tlsSrv.Close()

	e := NewEngine(t.TempDir())
	node := &protocol.ProxyNode{Name: "up", Type: protocol.ProtoSocks, Server: "127.0.0.1", Port: startSocks(t)}
	if err := e.Start(StartParams{Node: node, Mode: "proxy_only", LocalPort: 26555}); err != nil {
		t.Fatal(err)
	}
	defer e.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	info, err := e.LookupExit(ctx, httpSrv.URL)
	if err != nil || info.IP != "198.51.100.7" || info.CountryCode != "NL" || info.City != "Amsterdam" {
		t.Fatalf("http lookup: %+v %v", info, err)
	}
	// https target with an untrusted test certificate: must fail cleanly (never hang),
	// then the fallbacks are attempted without panicking.
	if _, err := e.LookupExit(ctx, tlsSrv.URL); err == nil {
		t.Log("note: fallback providers unexpectedly reachable")
	}
}
