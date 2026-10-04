# EASY hooks

All custom features live under `lib/easy/<feature>/`. The only edits to upstream
files are the lines below, each marked `EASY-HOOK`. After merging `upstream`,
run `grep -rn EASY-HOOK lib` and check each one still compiles.

| File | Hook | Feature |
|------|------|---------|
| `lib/views/profiles/add.dart` | import + `ListItem` "Single config" | single_config |
| `lib/views/tools.dart` | import + `EasyEntryServerItem()` in settings list | entry_server |
| `lib/providers/actions/setup.dart` | `EntryServerStore.applyStored(rawConfig)` before the profile task | entry_server |
| `lib/providers/action.dart` | import for the line above (`setup.dart` is a `part of`) | entry_server |

## Features

- `single_config`: paste a share link (vless, vmess, trojan, ss, hysteria2,
  tuic, anytls) or Clash YAML; it is validated by the core and merged into a
  profile labelled `Default`, created on first use.

- `entry_server`: pick one server as the first hop; every other proxy (and every
  proxy-provider, via `override`) gets `dialer-proxy: <entry>`, so connections
  and delay tests both go through it. Stored in SharedPreferences
  (`easy.entry_server`) as a full proxy map so it survives profile switches.

## Updating from upstream

```
git fetch upstream
git merge upstream/main
git submodule update --init
```
