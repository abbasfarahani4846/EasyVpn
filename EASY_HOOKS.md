# EASY hooks

All custom features live under `lib/easy/<feature>/`. The only edits to upstream
files are the lines below, each marked `EASY-HOOK`. After merging `upstream`,
run `grep -rn EASY-HOOK lib` and check each one still compiles.

| File | Hook | Feature |
|------|------|---------|
| `lib/views/profiles/add.dart` | import + `...easyAddProfileItems(context)` in the Add profile list (single config, WARP, Windscribe/OpenVPN/WireGuard files, Psiphon) | single_config, warp, windscribe, psiphon |
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

- `home`: two real dashboard widgets, so EasyVpn's own edit mode moves, removes and re-adds them:
  `easyConnect` (big connect button that says "Connected" only after an end-to-end check: IP through the
  core's mixed port vs the system's own IP vs the IP before connecting; status lines incl. Psiphon progress;
  a not-connected prompt after 12 s, 30 s for Psiphon, with keep-waiting / disconnect) and `easyRoute`
  (You -> entry -> server -> Internet). `EasyDashboardTop` applies a minimal layout ONCE (connect, IP card,
  TUN, system proxy, outbound mode, route); after that the layout is the user's.
  After merging upstream, regenerate with `dart run build_runner build --delete-conflicting-outputs`
  (all targets: a `--build-filter` run deletes the other generated files).

- `country_bypass`: pick a country; its IP and domain lists become mihomo `rule-providers` (format `mrs`) with `DIRECT` rules
  ahead of the profile's rules. The app downloads the lists itself into `easy_country/` (normal request, then straight to an
  address found over DNS-over-HTTPS, primary URL then jsDelivr mirror) and serves them to the core from `127.0.0.1:20841`,
  so the core's own fetch is instant: connecting never waits for the internet, and a list that is not available yet is simply
  left out until it is. (Before this, the core fetched from raw.githubusercontent.com itself; on a network that answers DNS for
  it with 10.10.34.x that blocked every new profile.) A seed copy can ship in `easy_bin/country/`; lists refresh after 24 h
  and on "Update now".
  Sources: MetaCubeX/meta-rules-dat (IPs for all countries, China and Russia domains) and Chocolate4U/Iran-clash-rules.

New features that only change the generated config go through `lib/easy/easy_config.dart`;
new Tools entries go into `lib/easy/easy_tools.dart`. Neither needs another upstream hook.

## Updating from upstream

```
git fetch upstream
git merge upstream/main
git submodule update --init
```
