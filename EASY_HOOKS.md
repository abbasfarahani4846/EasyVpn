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
| `lib/views/dashboard/dashboard.dart` | import + `EasyDashboardTop(child: ...)` around the grid (applies the minimal layout once) | home |
| `lib/enum/enum.dart` | `easyConnect`, `easyRoute` appended to `DashboardWidget` | home, entry_server |
| `lib/views/dashboard/widget_registry.dart` | import + two `switch` cases returning `easyConnectItem` / `easyRouteItem` | home, entry_server |
| `lib/models/generated/config.g.dart` | two lines in `_$DashboardWidgetEnumMap` (generated) | home, entry_server |
| `lib/providers/action.dart` | import for the line above (`setup.dart` is a `part of`) | entry_server, country_bypass |

## Features

- `single_config`: paste a share link (vless, vmess, trojan, ss, hysteria2,
  tuic, anytls) or Clash YAML; it is validated by the core and merged into a
  profile labelled `Default`, created on first use.

- `entry_server`: pick one server from every profile (grouped by profile, searchable; `lib/easy/servers/`) as the
  first hop. Every other remote proxy and proxy-provider gets `dialer-proxy: <entry>` (local proxies such as
  Psiphon are skipped). The entry also gets a local socks listener (127.0.0.1:20840) pinned to it, which
  Psiphon uses as its `UpstreamProxyURL`, so Psiphon reaches its servers through the entry. The choice is
  stored as a full proxy map and survives profile switches. The home screen shows the route.

- `home`: two real dashboard widgets, so FlClash's own edit mode moves, removes and re-adds them:
  `easyConnect` (big connect button that says "Connected" only after an end-to-end check: IP through the
  core's mixed port vs the system's own IP vs the IP before connecting; status lines incl. Psiphon progress;
  a not-connected prompt after 12 s, 30 s for Psiphon, with keep-waiting / disconnect) and `easyRoute`
  (You -> entry -> server -> Internet). `EasyDashboardTop` applies a minimal layout ONCE (connect, IP card,
  TUN, system proxy, outbound mode, route); after that the layout is the user's.
  After merging upstream, regenerate with `dart run build_runner build --delete-conflicting-outputs`
  (all targets: a `--build-filter` run deletes the other generated files).

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
  A ladder of methods (A fronted/CDN, D all direct, C in-proxy) is tried in order with short budgets that grow each pass (8 s, 15 s, then 25-40 s); the winner is remembered
  per network (interface + /24 fingerprint), refreshed on every connect, and the ladder restarts when the
  network changes or the tunnel drops. The Psiphon process is sent DIRECT by a `PROCESS-NAME` rule (needs `find-process-mode: always`, set when Psiphon is added or connected) so TUN does not feed its traffic back into itself. Diagnostics go to `psiphon.log` in its data dir. A server list downloaded once ships beside the core in
  `easy_bin/psiphon/seed/` and is copied into the data dir on first run. Windows only for now.

New features that only change the generated config go through `lib/easy/easy_config.dart`;
new Tools entries go into `lib/easy/easy_tools.dart`. Neither needs another upstream hook.

## Updating from upstream

```
git fetch upstream
git merge upstream/main
git submodule update --init
```
