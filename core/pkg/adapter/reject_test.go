package adapter

import (
	"context"
	"testing"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
)

// Regression: ad/tracker block rules were built with an empty reject method;
// sing-box panicked ("unknown reject method") on the first blocked connection
// in TUN mode. Every reject action must carry a valid method after the
// options pass through sing-box's decoder.
func TestRejectRulesHaveValidMethod(t *testing.T) {
	m := router.Default() // block ads + trackers on
	m.CustomRules = []router.Rule{{Kind: router.KindDomainSuffix, Values: []string{"ads.example"}, Outbound: router.OutboundBlock}}
	opts, _, err := buildOptionsWithTags(&StartRequest{Node: testSocksNode(), Routing: m, Mode: ModeProxyOnly, LocalPort: 2081})
	if err != nil {
		t.Fatal(err)
	}
	norm, err := normalizeOptions(include.Context(context.Background()), opts)
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, r := range norm.Route.Rules {
		a := r.DefaultOptions.RuleAction
		if a.Action == C.RuleActionTypeReject {
			n++
			switch a.RejectOptions.Method {
			case C.RuleActionRejectMethodDefault, C.RuleActionRejectMethodDrop, C.RuleActionRejectMethodReply:
			default:
				t.Fatalf("reject rule with invalid method %q", a.RejectOptions.Method)
			}
		}
	}
	if n == 0 {
		t.Fatal("expected at least one reject rule")
	}
}

func testSocksNode() *protocol.ProxyNode {
	return &protocol.ProxyNode{Name: "s", Type: protocol.ProtoSocks, Server: "127.0.0.1", Port: 1080}
}
