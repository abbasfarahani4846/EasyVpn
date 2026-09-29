// compile.go turns the router Model into sing-box option structures using
// only current (1.12+) rule-action based syntax — no deprecated geoip/geosite
// outbound fields, no dns/block special outbounds.
package router

import (
	"strings"
	"time"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
)

// BuildRouteRules compiles route rules in fixed order:
// sniff -> hijack-dns -> ads/trackers block -> LAN direct -> local country
// direct -> custom rules. The final outbound is returned by RouteFinal.
func BuildRouteRules(m Model) []option.Rule {
	var rules []option.Rule

	// 1. Sniff TLS/HTTP/QUIC so domain rules work for raw-IP clients.
	rules = append(rules, rule(option.DefaultRule{
		RuleAction: option.RuleAction{Action: "sniff"},
	}))

	// 2. Hijack plain DNS toward the internal DNS module.
	rules = append(rules, rule(option.DefaultRule{
		RawDefaultRule: option.RawDefaultRule{Protocol: []string{"dns"}},
		RuleAction:     option.RuleAction{Action: "hijack-dns"},
	}))

	// 3. Ads / tracker / malware blocking via rule-sets.
	var blockSets []string
	if m.BlockAds {
		blockSets = append(blockSets, "geosite-ads-all", "geosite-ads-ir")
	}
	if m.BlockTrackers {
		blockSets = append(blockSets, "geosite-malware", "geosite-phishing")
	}
	if len(blockSets) > 0 {
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{RuleSet: blockSets},
			RuleAction:     option.RuleAction{Action: "reject"},
		}))
	}

	// 4. LAN bypass.
	if m.BypassLAN {
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{IPIsPrivate: true},
			RuleAction:     option.RuleAction{Action: "direct"},
		}))
	}

	// 5. Local country direct (domains + IPs via country rule-sets).
	if m.Mode == ModeBypassLocalAndCountry && m.Country != "" {
		country := strings.ToLower(m.Country)
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{
				RuleSet: []string{"geosite-" + country, "geoip-" + country},
			},
			RuleAction: option.RuleAction{Action: "direct"},
		}))
	}

	// 6. User custom rules, in editor order.
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
			raw.RuleSet = r.Values
		}
		if rawRuleIsEmpty(&raw) {
			continue
		}
		action := option.RuleAction{Action: actionFor(r.Outbound)}
		if action.Action == "route" {
			action.RouteOptions = option.RouteActionOptions{Outbound: string(OutboundProxy)}
		}
		rules = append(rules, rule(option.DefaultRule{
			RawDefaultRule: raw,
			RuleAction:     action,
		}))
	}
	return rules
}

func rule(d option.DefaultRule) option.Rule {
	return option.Rule{Type: C.RuleTypeDefault, DefaultOptions: d}
}

func actionFor(o Outbound) string {
	switch o {
	case OutboundBlock:
		return "reject"
	case OutboundDirect:
		return "direct"
	default:
		return "route"
	}
}

// RouteFinal returns the final outbound tag for the routing mode.
func RouteFinal(m Model) string {
	return string(OutboundProxy)
}

func rawRuleIsEmpty(r *option.RawDefaultRule) bool {
	return len(r.Domain) == 0 && len(r.DomainSuffix) == 0 && len(r.DomainKeyword) == 0 &&
		len(r.IPCIDR) == 0 && len(r.Port) == 0 && len(r.ProcessName) == 0 &&
		len(r.PackageName) == 0 && len(r.RuleSet) == 0
}

func parseUint16(s string) (v uint16) {
	var n uint64
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + uint64(c-'0')
		if n > 65535 {
			return 0
		}
	}
	return uint16(n)
}

// BuildRuleSets returns the remote rule-set declarations referenced by the
// compiled rules (srs binary format; primary raw URL + jsDelivr mirror).
func BuildRuleSets(m Model) []option.RuleSet {
	byTag := map[string]bool{}
	var sets []option.RuleSet
	add := func(tag string, urls []string) {
		if tag == "" || byTag[tag] || len(urls) == 0 {
			return
		}
		byTag[tag] = true
		sets = append(sets, option.RuleSet{
			Type:   "remote",
			Tag:    []string{tag},
			Format: "binary",
			RemoteOptions: option.RemoteRuleSet{
				URL:            urls[0],
				UpdateInterval: badoption.Duration(24 * time.Hour),
			},
		})
	}
	if m.BlockAds {
		add("geosite-ads-all", irRuleSetURLs("geosite-category-ads-all"))
		add("geosite-ads-ir", irRuleSetURLs("geosite-ads"))
	}
	if m.BlockTrackers {
		add("geosite-malware", irRuleSetURLs("geosite-malware"))
		add("geosite-phishing", irRuleSetURLs("geosite-phishing"))
	}
	if m.Country != "" {
		c := strings.ToLower(m.Country)
		if c == "ir" {
			add("geosite-ir", irRuleSetURLs("geosite-ir"))
			add("geoip-ir", irRuleSetURLs("geoip-ir"))
		}
	}
	return sets
}

// irRuleSetURLs returns verified Chocolate4U raw+jsDelivr URLs for a category.
func irRuleSetURLs(category string) []string {
	base := "https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/"
	mirror := "https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-sing-box-rules@rule-set/"
	return []string{base + category + ".srs", mirror + category + ".srs"}
}

// BuildDNSOptions compiles the new-format DNS configuration: remote DoH as
// final, system/local server for domestic domains (Iranian CDN-friendly IPs).
func BuildDNSOptions(m Model) *option.DNSOptions {
	dns := &option.DNSOptions{
		RawDNSOptions: option.RawDNSOptions{
			Final: "dns-remote",
			DNSClientOptions: option.DNSClientOptions{
				Strategy: option.DomainStrategy(C.DomainStrategyPreferIPv4),
			},
		},
	}
	dns.Servers = append(dns.Servers, option.DNSServerOptions{
		Type: "https",
		Tag:  "dns-remote",
		Options: &option.RemoteHTTPSDNSServerOptions{
			RemoteTLSDNSServerOptions: option.RemoteTLSDNSServerOptions{
				RemoteDNSServerOptions: option.RemoteDNSServerOptions{
					DNSServerAddressOptions: option.DNSServerAddressOptions{
						Server: "8.8.8.8", ServerPort: 443,
					},
				},
			},
			Path: "/dns-query",
		},
	})
	dns.Servers = append(dns.Servers, option.DNSServerOptions{
		Type:    "local",
		Tag:     "dns-local",
		Options: &option.LocalDNSServerOptions{},
	})

	// Domestic domains resolve via local DNS to get Iranian CDN IPs.
	if m.Country != "" {
		c := strings.ToLower(m.Country)
		dns.Rules = append(dns.Rules, option.DNSRule{
			Type: C.RuleTypeDefault,
			DefaultOptions: option.DefaultDNSRule{
				RawDefaultDNSRule: option.RawDefaultDNSRule{
					DomainSuffix: []string{".ir"},
					RuleSet:      []string{"geosite-" + c},
				},
				DNSRuleAction: option.DNSRuleAction{
					Action:       "route",
					RouteOptions: option.DNSRouteActionOptions{Server: "dns-local"},
				},
			},
		})
	}
	return dns
}
