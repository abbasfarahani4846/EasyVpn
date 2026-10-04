# EASY hooks

All custom features live under `lib/easy/<feature>/`. The only edits to upstream
files are the lines below, each marked `EASY-HOOK`. After merging `upstream`,
run `grep -rn EASY-HOOK lib` and check each one still compiles.

| File | Hook | Feature |
|------|------|---------|
| `lib/views/profiles/add.dart` | import + `ListItem` "Single config" | single_config |
| `lib/views/tools.dart` | import + `...easySettingItems` in the settings list | entry_server, country_bypass |
| `lib/providers/actions/setup.dart` | `EasyConfig.apply(rawConfig)` before the profile task | entry_server, country_bypass |
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

New features that only change the generated config go through `lib/easy/easy_config.dart`;
new Tools entries go into `lib/easy/easy_tools.dart`. Neither needs another upstream hook.

## Updating from upstream

```
git fetch upstream
git merge upstream/main
git submodule update --init
```
