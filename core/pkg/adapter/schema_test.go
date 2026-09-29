package adapter

import (
	"context"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"

	"github.com/sagernet/sing-box/include"
	singjson "github.com/sagernet/sing/common/json"
)

// marshalJSON serializes sing-box options the same way box.New would read
// them (context-aware, registry-backed), so tests catch schema mismatches.
func marshalJSON(v any) ([]byte, error) {
	return singjson.MarshalContext(include.Context(context.Background()), v)
}

func TestJSONRoundTripMatchesSingBoxSchema(t *testing.T) {
	node := sampleNode(protocol.ProtoVLESS)
	node.TLS.Reality = &protocol.Reality{Enabled: true, PublicKey: "PK123", ShortID: "abcd"}
	opts, err := BuildOptions(&StartRequest{Node: node, Routing: routerDefault()})
	if err != nil {
		t.Fatalf("BuildOptions: %v", err)
	}
	// A full round trip through sing-box's own strict JSON decoder catches
	// wrong field names/types that plain encoding/json would silently accept.
	b, err := marshalJSON(opts)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	roundTripped, err := decodeOptionsStrict(b)
	if err != nil {
		t.Fatalf("sing-box strict decode rejected our options: %v\njson: %s", err, b)
	}
	if roundTripped == nil {
		t.Fatalf("nil options after round trip")
	}
}

func TestTransportMappingWSAndGRPC(t *testing.T) {
	node := sampleNode(protocol.ProtoVLESS)
	node.Transport = &protocol.TransportConfig{Type: "ws", Path: "/wspath", Host: "cdn.example.com"}
	opts, err := BuildOptions(&StartRequest{Node: node, Routing: routerDefault()})
	if err != nil {
		t.Fatalf("ws: %v", err)
	}
	b, _ := marshalJSON(&opts)
	for _, want := range []string{`"type":"ws"`, `"path":"/wspath"`, `"Host":"cdn.example.com"`} {
		if !contains(string(b), want) {
			t.Fatalf("ws transport missing %s: %s", want, b)
		}
	}

	node.Transport = &protocol.TransportConfig{Type: "grpc", ServiceName: "grpcsvc"}
	opts, err = BuildOptions(&StartRequest{Node: node, Routing: routerDefault()})
	if err != nil {
		t.Fatalf("grpc: %v", err)
	}
	b, _ = marshalJSON(&opts)
	if !contains(string(b), `"service_name":"grpcsvc"`) {
		t.Fatalf("grpc transport missing service_name: %s", b)
	}
}

func TestHysteria2ObfsAndTUICFields(t *testing.T) {
	node := sampleNode(protocol.ProtoHysteria2)
	node.UUID = ""
	node.Hysteria2 = &protocol.Hysteria2Config{ObfsType: "salamander", ObfsPassword: "obfssecret"}
	b, err := BuildOptions(&StartRequest{Node: node, Routing: routerDefault()})
	if err != nil {
		t.Fatalf("BuildOptions: %v", err)
	}
	j, _ := marshalJSON(&b)
	if !contains(string(j), `"obfs"`) || !contains(string(j), "obfssecret") {
		t.Fatalf("hysteria2 obfs missing: %s", j)
	}

	tuic := sampleNode(protocol.ProtoTUIC)
	tuic.TUIC = &protocol.TUICConfig{CongestionControl: "bbr", UDPRelayMode: "native"}
	opts, err := BuildOptions(&StartRequest{Node: tuic, Routing: routerDefault()})
	if err != nil {
		t.Fatalf("tuic: %v", err)
	}
	j, _ = marshalJSON(&opts)
	for _, want := range []string{`"congestion_control":"bbr"`, `"udp_relay_mode":"native"`} {
		if !contains(string(j), want) {
			t.Fatalf("tuic missing %s: %s", want, j)
		}
	}
}

func TestRuleSetUpdateInterval(t *testing.T) {
	if d := time.Duration(24 * time.Hour); d <= 0 {
		t.Fatalf("bad duration")
	}
}
