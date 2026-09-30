package config

import (
	"strings"
	"testing"
)

// The same provider node in the three formats a panel serves depending on
// the User-Agent must parse to the same functional node.
const clashSample = `
proxies:
  - name: "🇺🇸 USA AI"
    type: vless
    server: uvk.example.ir
    port: 1001
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
    udp: true
    tls: true
    servername: sslcert.example.ir
    network: xhttp
    xhttp-opts:
      path: /
      host: myket.ir
      mode: stream-up
      x-padding-bytes: 100-1000
      x-padding-obfs-mode: true
  - name: "🇩🇪 DE mlkem http"
    type: vless
    server: de.example.ir
    port: 33017
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
    encryption: mlkem768x25519plus.native.0rtt.KEY
    network: http
    http-opts:
      path: ["/"]
      Host: testspeed.example.ir
`

const xraySample = `[{"remarks":"🇺🇸 USA AI","outbounds":[
 {"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"uvk.example.ir","port":1001,
   "users":[{"id":"b831381d-6324-4d53-ad4f-8cda48b30811","encryption":"none"}]}]},
  "streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"serverName":"sslcert.example.ir"},
   "xhttpSettings":{"mode":"stream-up","path":"/","host":"myket.ir","extra":{"xPaddingBytes":"100-1000","xPaddingObfsMode":true}}}},
 {"protocol":"freedom","tag":"DIRECT"}]},
 {"remarks":"🇩🇪 DE ws","outbounds":[
 {"protocol":"vless","tag":"proxy","settings":{"vnext":[{"address":"cdn.example.ir","port":8080,
   "users":[{"id":"b831381d-6324-4d53-ad4f-8cda48b30811","encryption":"none"}]}]},
  "streamSettings":{"network":"ws","wsSettings":{"host":"front.example.ir","path":"/ws"}}}]}]`

const uriSample = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@uvk.example.ir:1001?encryption=none&security=tls&type=xhttp&path=%2F&host=myket.ir&mode=stream-up&extra=%7B%22xPaddingBytes%22%3A%22100-1000%22%2C%22xPaddingObfsMode%22%3Atrue%7D&sni=sslcert.example.ir#%F0%9F%87%BA%F0%9F%87%B8%20USA%20AI"

func TestSameNodeAcrossClashXrayURI(t *testing.T) {
	p := NewParser()
	c, err := p.ParseContent(clashSample)
	if err != nil || len(c) != 2 {
		t.Fatalf("clash: %v %d", err, len(c))
	}
	x, err := p.ParseContent(xraySample)
	if err != nil || len(x) != 2 {
		t.Fatalf("xray: %v %d", err, len(x))
	}
	u, err := p.ParseContent(uriSample)
	if err != nil || len(u) != 1 {
		t.Fatalf("uri: %v", err)
	}
	for _, n := range []struct {
		src  string
		name string
		tr   string
		mode string
		host string
		ex   string
	}{
		{"clash", c[0].Name, c[0].Transport.Type, c[0].Transport.Mode, c[0].Transport.Host, c[0].Transport.Extra},
		{"xray", x[0].Name, x[0].Transport.Type, x[0].Transport.Mode, x[0].Transport.Host, x[0].Transport.Extra},
		{"uri", u[0].Name, u[0].Transport.Type, u[0].Transport.Mode, u[0].Transport.Host, u[0].Transport.Extra},
	} {
		if n.name != "🇺🇸 USA AI" || n.tr != "xhttp" || n.mode != "stream-up" || n.host != "myket.ir" ||
			!strings.Contains(n.ex, `"xPaddingObfsMode":true`) || !strings.Contains(n.ex, `"xPaddingBytes":"100-1000"`) {
			t.Errorf("%s: name=%q tr=%s mode=%s host=%s extra=%s", n.src, n.name, n.tr, n.mode, n.host, n.ex)
		}
	}
	// mihomo network:http = TCP + HTTP header camouflage, plus ML-KEM.
	if c[1].Transport.Type != "tcp-http" || c[1].Transport.Host != "testspeed.example.ir" || c[1].Encryption == "" {
		t.Errorf("clash http/mlkem: %+v enc=%q", c[1].Transport, c[1].Encryption)
	}
	// Xray wsSettings.host (new field) must not be lost.
	if x[1].Transport.Host != "front.example.ir" || x[1].Name != "🇩🇪 DE ws" {
		t.Errorf("xray ws host: %+v name=%q", x[1].Transport, x[1].Name)
	}
}
