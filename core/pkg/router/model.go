// Package router compiles the app's routing model into sing-box route and
// DNS options. It is engine-agnostic: adapter packages translate the rule
// list into engine-specific structures (currently sing-box rule actions).
package router

// Outbound is the symbolic destination of a rule.
type Outbound string

const (
	OutboundDirect Outbound = "direct"
	OutboundProxy  Outbound = "proxy"
	OutboundBlock  Outbound = "block"
)

// RoutingMode is a high-level preset the user picks in the UI.
type RoutingMode string

const (
	ModeBypassLocalAndCountry RoutingMode = "bypass_local_country"
	ModeBypassLANOnly         RoutingMode = "bypass_lan_only"
	ModeGlobalProxy           RoutingMode = "global_proxy"
	ModeCustom                RoutingMode = "custom"
)

// RuleKind identifies the matcher type of a custom rule.
type RuleKind string

const (
	KindDomainSuffix  RuleKind = "domain_suffix"
	KindDomainKeyword RuleKind = "domain_keyword"
	KindIPCIDR        RuleKind = "ip_cidr"
	KindPort          RuleKind = "port"
	KindProcessName   RuleKind = "process_name"
	KindPackageName   RuleKind = "package_name"
	KindRuleSet       RuleKind = "rule_set"
)

// Rule is one user-visible routing rule (custom rules editor row).
type Rule struct {
	Kind     RuleKind `json:"kind"`
	Values   []string `json:"values"`
	Outbound Outbound `json:"outbound"`
}

// RuleSetRef references a locally synced rule-set by tag (srs binary format).
type RuleSetRef struct {
	Tag              string   `json:"tag"`
	LocalPaths       []string `json:"local_paths,omitempty"` // resolved cache paths
	RemoteURLs       []string `json:"remote_urls,omitempty"`
	UpdateHours      int      `json:"update_hours,omitempty"`
	DownloadViaProxy bool     `json:"download_via_proxy,omitempty"`
}

// Model is the full routing configuration handed to the adapter.
type Model struct {
	Mode          RoutingMode  `json:"mode"`
	Country       string       `json:"country,omitempty"` // e.g. "IR"
	BlockAds      bool         `json:"block_ads"`
	BlockTrackers bool         `json:"block_trackers"`
	BypassLAN     bool         `json:"bypass_lan"`
	LocalRuleSets []string     `json:"local_rule_sets,omitempty"` // country geosite/geoip tags
	CustomRules   []Rule       `json:"custom_rules,omitempty"`
	RuleSets      []RuleSetRef `json:"rule_sets,omitempty"`
	RemoteDNS     string       `json:"remote_dns,omitempty"` // e.g. "https://8.8.8.8/dns-query"
	LocalDNS      string       `json:"local_dns,omitempty"`  // e.g. "udp://78.157.42.100" or "" (system)
	FakeIPEnabled bool         `json:"fakeip_enabled"`
	LogLevel      string       `json:"log_level,omitempty"`
}

// Default returns the default model (Iran bypass preset with ads blocking).
func Default() Model {
	return Model{
		Mode:          ModeBypassLocalAndCountry,
		Country:       "IR",
		BlockAds:      true,
		BlockTrackers: true,
		BypassLAN:     true,
		FakeIPEnabled: false,
		LogLevel:      "info",
	}
}
