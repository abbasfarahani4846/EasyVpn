package router

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/sagernet/sing-box/option"
)

func fakeSets(t *testing.T, tags ...string) string {
	dir := t.TempDir()
	for _, tag := range tags {
		if err := os.WriteFile(filepath.Join(dir, tag+".srs"), []byte("SRS\x01payload"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func actions(rules []option.Rule) []string {
	var out []string
	for _, r := range rules {
		a := r.DefaultOptions.Action
		if a == "route" {
			a += ":" + r.DefaultOptions.RouteOptions.Outbound
		}
		out = append(out, a)
	}
	return out
}

func TestIranRuleOrder(t *testing.T) {
	m := Default()
	m.RuleSetDir = fakeSets(t, "geosite-ads-all", "geosite-malware", "geosite-ir", "geoip-ir")
	got := actions(BuildRouteRules(m))
	// sniff, hijack-dns, reject(block), direct(LAN), route(proxy override), direct(.ir), direct(sets)
	want := []string{"sniff", "hijack-dns", "reject", "route:direct", "route:proxy", "route:direct", "route:direct"}
	if len(got) != len(want) {
		t.Fatalf("got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("pos %d: got %v want %v", i, got, want)
		}
	}
	// WhatsApp override must come BEFORE the country-direct rules.
	rules := BuildRouteRules(m)
	if len(rules[4].DefaultOptions.DomainSuffix) == 0 || rules[4].DefaultOptions.RouteOptions.Outbound != "proxy" {
		t.Fatalf("service override must be proxy-forced at position 4: %+v", rules[4])
	}
}

func TestMissingRuleSetsAreNeverReferenced(t *testing.T) {
	m := Default()
	m.RuleSetDir = t.TempDir() // empty: nothing downloaded yet
	for _, r := range BuildRouteRules(m) {
		if len(r.DefaultOptions.RuleSet) > 0 {
			t.Fatalf("rule references a rule-set that does not exist: %+v", r.DefaultOptions.RuleSet)
		}
	}
	if len(BuildRuleSets(m)) != 0 {
		t.Fatal("no rule-set may be declared without a file")
	}
	// .ir suffix direct rule still works without any download.
	found := false
	for _, r := range BuildRouteRules(m) {
		for _, s := range r.DefaultOptions.DomainSuffix {
			if s == ".ir" && r.DefaultOptions.RouteOptions.Outbound == "direct" {
				found = true
			}
		}
	}
	if !found {
		t.Fatal("expected .ir direct rule as offline fallback")
	}
}

func TestModes(t *testing.T) {
	m := Default()
	m.Mode = ModeBypassProxy
	if RouteFinal(m) != "direct" {
		t.Fatal("bypass_proxy final must be direct")
	}
	m.Mode = ModeGlobalProxy
	if RouteFinal(m) != "proxy" {
		t.Fatal("global final must be proxy")
	}
	m.RuleSetDir = fakeSets(t, "geosite-ir", "geoip-ir")
	for _, r := range BuildRouteRules(m) {
		for _, s := range r.DefaultOptions.DomainSuffix {
			if s == ".ir" {
				t.Fatal("global mode must not bypass the local country")
			}
		}
	}
}

func TestDNSSchema(t *testing.T) {
	m := Default()
	m.FakeIPEnabled = true
	m.RemoteDNS = "tls://1.1.1.1"
	m.LocalDNS = "udp://78.157.42.100"
	m.RuleSetDir = fakeSets(t, "geosite-ir")
	d := BuildDNSOptions(m)
	types := map[string]string{}
	for _, s := range d.Servers {
		types[s.Tag] = s.Type
	}
	if types[DNSRemoteTag] != "tls" || types[DNSLocalTag] != "udp" || types[DNSFakeIPTag] != "fakeip" {
		t.Fatalf("unexpected servers: %v", types)
	}
	if d.Final != DNSRemoteTag {
		t.Fatal("final must be remote")
	}
	// fakeip rule is last so domestic/proxy-forced domains resolve first
	last := d.Rules[len(d.Rules)-1].DefaultOptions.RouteOptions.Server
	if last != DNSFakeIPTag {
		t.Fatalf("last DNS rule should target fakeip, got %s", last)
	}
}
