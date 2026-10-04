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
| `lib/providers/action.dart` | import for the line above (`setup.dart` is a `part of`) | entry_server, country_bypass |

## Features

- `single_config`: paste a share link (vless, vmess, trojan, ss, hysteria2,
  tuic, anytls) or Clash YAML; it is validated by the core and merged into a
  profile labelled `Default`, created on first use.

- `entry_server`: pick one server (from the real Proxies page, via `EasyProxyPicker`) as the first hop; every other proxy (and every
  proxy-provider, via `override`) gets `dialer-proxy: <entry>`, so connections
  and delay tests both go through it. Stored in SharedPreferences
  (`easy.entry_server`) as a full proxy map so it survives profile switches.

- `country_bypass`: pick a country; its IP and domain lists are added as mihomo
  `rule-providers` (format `mrs`, refreshed every 24 h by the core, manual "Update now"
  via `updateExternalProvider`) with `DIRECT` rules put ahead of the profile's rules.
  Sources: MetaCubeX/meta-rules-dat (IPs for all countries, China and Russia domains) and
  Chocolate4U/Iran-clash-rules (Iran domains and CIDRs); jsDelivr mirror toggle.

- `warp`: "Add" on the single-config page registers an anonymous Cloudflare WARP device
  (X25519 key pair made in Dart, `lib/easy/warp/x25519.dart`) and stores a mihomo `wireguard`
  proxy in the Default profile. Needs access to api.cloudflareclient.com (blocked in some networks;
  works through an active proxy). No upstream hook.

- `psiphon`: runs the official Psiphon core (`easy_bin/psiphon/psiphon-tunnel-core-i686.exe`, not
  committed) as a child process and walks a ladder of methods (A fronted/CDN, D all direct protocols,
  C in-proxy relay), remembering the winner. Psiphon fetches its own server list; local SOCKS5 on
  127.0.0.1:20830, added to the Default profile as a `socks5` node. Starts automatically when a profile
  containing that node is connected and stops on disconnect (`EasyConfig`). A server list downloaded
  once ships beside the core in `easy_bin/psiphon/seed/` and is copied into the data dir on first run.
  Windows only for now.

New features that only change the generated config go through `lib/easy/easy_config.dart`;
new Tools entries go into `lib/easy/easy_tools.dart`. Neither needs another upstream hook.

## Updating from upstream

```
git fetch upstream
git merge upstream/main
git submodule update --init
```
