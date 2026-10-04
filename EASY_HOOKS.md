# EASY hooks

All custom features live under `lib/easy/<feature>/`. The only edits to upstream
files are the lines below, each marked `EASY-HOOK`. After merging `upstream`,
run `grep -rn EASY-HOOK lib` and check each one still compiles.

| File | Hook | Feature |
|------|------|---------|
| `lib/views/profiles/add.dart` | import + `...easyAddProfileItems(context)` in the Add profile list (single config, WARP, Psiphon) | single_config, warp, psiphon |
| `lib/views/tools.dart` | import + `...easySettingItems` in the settings list | entry_server, country_bypass |
| `lib/providers/actions/setup.dart` | `EasyConfig.apply(rawConfig)` before the profile task; `EasyConfig.onRunning(running)` at the top of `setRunning` | entry_server, country_bypass, psiphon |
| `lib/views/proxies/card.dart` | import + `EasyProxyPicker.tryPick` at the top of `selectGroupProxy` (lets the Proxies page act as a server chooser) | entry_server |
| `lib/views/dashboard/dashboard.dart` | import + `EasyDashboardTop(child: ...)` around the grid (chain route card) | entry_server |
| `lib/providers/action.dart` | import for the line above (`setup.dart` is a `part of`) | entry_server, country_bypass |

## Features

- `single_config`: paste a share link (vless, vmess, trojan, ss, hysteria2,
  tuic, anytls) or Clash YAML; it is validated by the core and merged into a
  profile labelled `Default`, created on first use.

- `entry_server`: pick one server (from the real Proxies page, via `EasyProxyPicker`) as the first hop, with a route card on the dashboard (You -> entry -> server -> Internet); every other proxy (and every
  proxy-provider, via `override`) gets `dialer-proxy: <entry>`, so connections
  and delay tests both go through it. Stored in SharedPreferences
  (`easy.entry_server`) as a full proxy map so it survives profile switches.

- `country_bypass`: pick a country; its IP and domain lists are added as mihomo
  `rule-providers` (format `mrs`, refreshed every 24 h by the core, manual "Update now"
  via `updateExternalProvider`) with `DIRECT` rules put ahead of the profile's rules.
  Sources: MetaCubeX/meta-rules-dat (IPs for all countries, China and Russia domains) and
  Chocolate4U/Iran-clash-rules (Iran domains and CIDRs); jsDelivr mirror toggle.

- `warp`: the WARP item in Add profile registers an anonymous Cloudflare WARP device
  (X25519 key pair made in Dart, `lib/easy/warp/x25519.dart`) and stores a mihomo `wireguard`
  proxy in its own selected `WARP` profile. Needs access to api.cloudflareclient.com (blocked in some networks;
  works through an active proxy). No upstream hook.

- `psiphon`: one tap in Add profile creates and selects a `Psiphon` profile (an Auto node plus one node per
  egress country, all on 127.0.0.1:20830) and connects. The official Psiphon core
  (`easy_bin/psiphon/psiphon-tunnel-core-i686.exe`, not committed) runs in the background: it starts when a
  profile containing the node is connected (the connect waits for the tunnel) and stops on disconnect.
  Picking a country node restarts it with that `EgressRegion` (tap observed in `EasyProxyPicker.tryPick`).
  A ladder of methods (A fronted/CDN, D all direct, C in-proxy) is tried in order; the winner is remembered
  per network (interface + /24 fingerprint), refreshed on every connect, and the ladder restarts when the
  network changes or the tunnel drops. A server list downloaded once ships beside the core in
  `easy_bin/psiphon/seed/` and is copied into the data dir on first run. Windows only for now.

New features that only change the generated config go through `lib/easy/easy_config.dart`;
new Tools entries go into `lib/easy/easy_tools.dart`. Neither needs another upstream hook.

## Updating from upstream

```
git fetch upstream
git merge upstream/main
git submodule update --init
```
