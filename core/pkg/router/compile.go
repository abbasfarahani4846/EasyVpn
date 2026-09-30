// compile.go turns the router Model into sing-box option structures using
// only current (1.14) rule-action syntax: rule_set references (never legacy
// geoip/geosite fields), rule actions, and the new DNS server format.
//
// Rule-sets are downloaded by pkg/rulesync into Model.RuleSetDir and declared
// here as "local" sets (sing-box 1.14 deprecates remote download_detour). A
// tag is referenced only if its file exists, so a missing download degrades
// routing instead of failing box creation.
package router

import (
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	mDNS "github.com/miekg/dns"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
)

// Well-known rule-set tags (see rulesync registry).
var (
	blockAdTags       = []string{"geosite-ads-all", "geosite-ads-ir"}
	blockSecurityTags = []string{"geosite-malware", "geosite-phishing", "geosite-cryptominers", "geoip-malware", "geoip-phishing"}
)

// countryTLD maps a country code to the ccTLD that is always matched by suffix
// even when no rule-set could be downloaded.
var countryTLD = map[string]string{"ir": ".ir", "cn": ".cn", "ru": ".ru"}

// hasSet reports whether the rule-set file for tag exists in RuleSetDir.
func (m Model) hasSet(tag string) bool {
	if m.RuleSetDir == "" {
		return false
	}
	st, err := os.Stat(m.setPath(tag))
	return err == nil && !st.IsDir() && st.Size() > 0
}

func (m Model) setPath(tag string) string { return filepath.Join(m.RuleSetDir, tag+".srs") }

func (m Model) present(tags ...string) []string {
	var out []string
	for _, t := range tags {
		if m.hasSet(t) {
			out = append(out, t)
		}
	}
	return out
}

func (m Model) countryDirectSets() []string {
	c := strings.ToLower(m.Country)
	if c == "" {
		return nil
	}
	return m.present("geosite-"+c, "geoip-"+c)
}

func (m Model) usesCountry() bool {
	return m.Mode == ModeBypassLocalAndCountry && m.Country != ""
}

// BuildRouteRules compiles route rules in the documented fixed order:
// sniff -> hijack-dns -> block -> LAN direct -> service overrides ->
// local-country direct -> custom rules. The final outbound is RouteFinal.
func BuildRouteRules(m Model) []option.Rule {
	var rules []option.Rule

	rules = append(rules, rule(option.DefaultRule{
		RuleAction: option.RuleAction{Action: "sniff"},
	}))
	rules = append(rules, rule(option.DefaultRule{
		RawDefaultRule: option.RawDefaultRule{Protocol: []string{"dns"}},
		RuleAction:     option.RuleAction{Action: "hijack-dns"},
	}))

	// Block lists.
	var blockSets []string
	if m.BlockAds {
		blockSets = append(blockSets, m.present(blockAdTags...)...)
	}
	if m.BlockTrackers {
		blockSets = append(blockSets, m.present(blockSecurityTags...)...)
	}
	if len(blockSets) > 0 {
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{RuleSet: blockSets},
			RuleAction:     rejectAction(),
		}))
	}

	// LAN bypass.
	if m.BypassLAN {
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{IPIsPrivate: true},
			RuleAction:     routeAction(OutboundDirect),
		}))
	}

	// Service overrides beat the country rules (WhatsApp/Telegram must never be
	// classified as domestic by a broad geoip-ir set).
	if len(m.ServiceOverrides.Proxy) > 0 {
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{DomainSuffix: m.ServiceOverrides.Proxy},
			RuleAction:     routeAction(OutboundProxy),
		}))
	}
	if len(m.ServiceOverrides.Direct) > 0 {
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{DomainSuffix: m.ServiceOverrides.Direct},
			RuleAction:     routeAction(OutboundDirect),
		}))
	}

	// Local country direct.
	if m.usesCountry() {
		raw := option.RawDefaultRule{RuleSet: m.countryDirectSets()}
		if tld, ok := countryTLD[strings.ToLower(m.Country)]; ok {
			raw.DomainSuffix = []string{tld}
		}
		if len(raw.RuleSet) > 0 || len(raw.DomainSuffix) > 0 {
			// Domain suffix and rule-set are OR-combined by sing-box only inside
			// a logical rule; emit them as two rules to keep semantics explicit.
			if len(raw.DomainSuffix) > 0 {
				rules = append(rules, rule(option.DefaultRule{
					RawDefaultRule: option.RawDefaultRule{DomainSuffix: raw.DomainSuffix},
					RuleAction:     routeAction(OutboundDirect),
				}))
			}
			if len(raw.RuleSet) > 0 {
				rules = append(rules, rule(option.DefaultRule{
					RawDefaultRule: option.RawDefaultRule{RuleSet: raw.RuleSet},
					RuleAction:     routeAction(OutboundDirect),
				}))
			}
		}
	}

	// User custom rules, in editor order.
	for _, r := range m.CustomRules {
		raw := option.RawDefaultRule{}
		switch r.Kind {
		case KindDomainSuffix:
			raw.DomainSuffix = r.Values
		case KindDomainKeyword:
			raw.DomainKeyword = r.Values
		case KindIPCIDR:
			raw.IPCIDR = r.Values
		case KindPort:
			for _, v := range r.Values {
				if p := parseUint16(v); p > 0 {
					raw.Port = append(raw.Port, p)
				}
			}
		case KindProcessName:
			raw.ProcessName = r.Values
		case KindPackageName:
			raw.PackageName = r.Values
		case KindRuleSet:
			raw.RuleSet = m.present(r.Values...)
		}
		if rawRuleIsEmpty(&raw) {
			continue
		}
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: raw,
			RuleAction:     actionFor(r.Outbound),
		}))
	}
	return rules
}

func rule(d option.DefaultRule) option.Rule {
	return option.Rule{Type: C.RuleTypeDefault, DefaultOptions: d}
}

func routeAction(o Outbound) option.RuleAction {
	return option.RuleAction{
		Action:       "route",
		RouteOptions: option.RouteActionOptions{Outbound: string(o)},
	}
}

func actionFor(o Outbound) option.RuleAction {
	switch o {
	case OutboundBlock:
		return rejectAction()
	case OutboundDirect:
		return routeAction(OutboundDirect)
	default:
		return routeAction(OutboundProxy)
	}
}

// RouteFinal returns the final outbound tag for the routing mode.
func RouteFinal(m Model) string {
	if m.Mode == ModeBypassProxy {
		return string(OutboundDirect)
	}
	return string(OutboundProxy)
}

func rawRuleIsEmpty(r *option.RawDefaultRule) bool {
	return len(r.Domain) == 0 && len(r.DomainSuffix) == 0 && len(r.DomainKeyword) == 0 &&
		len(r.IPCIDR) == 0 && len(r.Port) == 0 && len(r.ProcessName) == 0 &&
		len(r.PackageName) == 0 && len(r.RuleSet) == 0
}

func parseUint16(s string) uint16 {
	n, err := strconv.ParseUint(s, 10, 16)
	if err != nil {
		return 0
	}
	return uint16(n)
}

// BuildRuleSets declares every rule-set present in RuleSetDir as a local
// binary rule-set. Unreferenced sets are harmless but skipped to keep the
// config small: only tags the compiled rules can reference are declared.
func BuildRuleSets(m Model) []option.RuleSet {
	seen := map[string]bool{}
	var sets []option.RuleSet
	add := func(tags ...string) {
		for _, tag := range tags {
			if seen[tag] || !m.hasSet(tag) {
				continue
			}
			seen[tag] = true
			sets = append(sets, option.RuleSet{
				Type:         "local",
				Tag:          []string{tag},
				Format:       "binary",
				LocalOptions: option.LocalRuleSet{Path: m.setPath(tag)},
			})
		}
	}
	if m.BlockAds {
		add(blockAdTags...)
	}
	if m.BlockTrackers {
		add(blockSecurityTags...)
	}
	if m.usesCountry() {
		add(m.countryDirectSets()...)
	}
	for _, r := range m.CustomRules {
		if r.Kind == KindRuleSet {
			add(r.Values...)
		}
	}
	return sets
}

// ---------------------------------------------------------------------------
// DNS
// ---------------------------------------------------------------------------

const (
	DNSRemoteTag = "dns-remote"
	DNSLocalTag  = "dns-local"
	DNSFakeIPTag = "dns-fakeip"
)

// BuildDNSOptions compiles the new-format DNS configuration: proxied DoH as
// final, local resolver for domestic domains, optional FakeIP (TUN mode).
func BuildDNSOptions(m Model) *option.DNSOptions {
	dns := &option.DNSOptions{
		RawDNSOptions: option.RawDNSOptions{
			Final: DNSRemoteTag,
			DNSClientOptions: option.DNSClientOptions{
				Strategy: option.DomainStrategy(C.DomainStrategyPreferIPv4),
			},
		},
	}
	dns.Servers = append(dns.Servers,
		parseDNSServer(DNSRemoteTag, orDefault(m.RemoteDNS, "https://1.1.1.1/dns-query"), string(OutboundProxy)),
		parseDNSServer(DNSLocalTag, m.LocalDNS, ""),
	)
	if m.FakeIPEnabled {
		v4 := badoption.Prefix(netip.MustParsePrefix("198.18.0.0/15"))
		v6 := badoption.Prefix(netip.MustParsePrefix("fc00::/18"))
		dns.Servers = append(dns.Servers, option.DNSServerOptions{
			Type:    "fakeip",
			Tag:     DNSFakeIPTag,
			Options: &option.FakeIPDNSServerOptions{Inet4Range: &v4, Inet6Range: &v6},
		})
	}

	dnsRule := func(raw option.RawDefaultDNSRule, server string) option.DNSRule {
		return option.DNSRule{
			Type: C.RuleTypeDefault,
			DefaultOptions: option.DefaultDNSRule{
				RawDefaultDNSRule: raw,
				DNSRuleAction: option.DNSRuleAction{
					Action:       "route",
					RouteOptions: option.DNSRouteActionOptions{Server: server},
				},
			},
		}
	}

	// Proxy-forced services always resolve remotely.
	if len(m.ServiceOverrides.Proxy) > 0 {
		dns.Rules = append(dns.Rules, dnsRule(option.RawDefaultDNSRule{DomainSuffix: m.ServiceOverrides.Proxy}, DNSRemoteTag))
	}
	if len(m.ServiceOverrides.Direct) > 0 {
		dns.Rules = append(dns.Rules, dnsRule(option.RawDefaultDNSRule{DomainSuffix: m.ServiceOverrides.Direct}, DNSLocalTag))
	}
	// Domestic domains resolve locally (Iranian CDN-friendly answers).
	if m.usesCountry() {
		if tld, ok := countryTLD[strings.ToLower(m.Country)]; ok {
			dns.Rules = append(dns.Rules, dnsRule(option.RawDefaultDNSRule{DomainSuffix: []string{tld}}, DNSLocalTag))
		}
		if sets := m.present("geosite-" + strings.ToLower(m.Country)); len(sets) > 0 {
			dns.Rules = append(dns.Rules, dnsRule(option.RawDefaultDNSRule{RuleSet: sets}, DNSLocalTag))
		}
	}
	if m.FakeIPEnabled {
		dns.Rules = append(dns.Rules, dnsRule(option.RawDefaultDNSRule{
			QueryType: []option.DNSQueryType{option.DNSQueryType(mDNS.TypeA), option.DNSQueryType(mDNS.TypeAAAA)},
		}, DNSFakeIPTag))
	}
	return dns
}

func orDefault(v, d string) string {
	if v == "" {
		return d
	}
	return v
}

// parseDNSServer converts "https://host[:port]/path", "tls://host[:port]",
// "udp://host[:port]", "tcp://host[:port]", "local" or a bare IP into a
// sing-box DNS server. detour is the outbound used to reach the server.
// ParseDNSServer is the exported form of parseDNSServer.
func ParseDNSServer(tag, addr, detour string) option.DNSServerOptions {
	return parseDNSServer(tag, addr, detour)
}

func parseDNSServer(tag, addr, detour string) option.DNSServerOptions {
	dialer := option.RawLocalDNSServerOptions{DialerOptions: option.DialerOptions{Detour: detour}}
	remote := func(host, port string, def uint16) option.RemoteDNSServerOptions {
		p := def
		if port != "" {
			if v, err := strconv.ParseUint(port, 10, 16); err == nil {
				p = uint16(v)
			}
		}
		return option.RemoteDNSServerOptions{
			RawLocalDNSServerOptions: dialer,
			DNSServerAddressOptions:  option.DNSServerAddressOptions{Server: host, ServerPort: p},
		}
	}
	if addr == "" || addr == "local" || addr == "system" {
		return option.DNSServerOptions{Type: "local", Tag: tag, Options: &option.LocalDNSServerOptions{RawLocalDNSServerOptions: dialer}}
	}
	if !strings.Contains(addr, "://") {
		addr = "udp://" + addr
	}
	u, err := url.Parse(addr)
	if err != nil || u.Hostname() == "" {
		return option.DNSServerOptions{Type: "local", Tag: tag, Options: &option.LocalDNSServerOptions{RawLocalDNSServerOptions: dialer}}
	}
	host, port := u.Hostname(), u.Port()
	switch u.Scheme {
	case "https", "h3":
		path := u.Path
		if path == "" {
			path = "/dns-query"
		}
		typ := "https"
		if u.Scheme == "h3" {
			typ = "h3"
		}
		return option.DNSServerOptions{Type: typ, Tag: tag, Options: &option.RemoteHTTPSDNSServerOptions{
			RemoteTLSDNSServerOptions: option.RemoteTLSDNSServerOptions{RemoteDNSServerOptions: remote(host, port, 443)},
			Path:                      path,
		}}
	case "tls":
		return option.DNSServerOptions{Type: "tls", Tag: tag, Options: &option.RemoteTLSDNSServerOptions{RemoteDNSServerOptions: remote(host, port, 853)}}
	case "tcp":
		return option.DNSServerOptions{Type: "tcp", Tag: tag, Options: &option.RemoteDNSServerOptions{RawLocalDNSServerOptions: remote(host, port, 53).RawLocalDNSServerOptions, DNSServerAddressOptions: remote(host, port, 53).DNSServerAddressOptions}}
	default:
		return option.DNSServerOptions{Type: "udp", Tag: tag, Options: &option.RemoteDNSServerOptions{RawLocalDNSServerOptions: remote(host, port, 53).RawLocalDNSServerOptions, DNSServerAddressOptions: remote(host, port, 53).DNSServerAddressOptions}}
	}
}

// rejectAction builds a reject rule action with an explicit method. The
// struct zero value (Method "") is only defaulted by sing-box's JSON decoder;
// used directly it panics ("unknown reject method") on the first blocked
// connection, which crashed the core in TUN mode.
func rejectAction() option.RuleAction {
	return option.RuleAction{
		Action:        C.RuleActionTypeReject,
		RejectOptions: option.RejectActionOptions{Method: C.RuleActionRejectMethodDefault},
	}
}
