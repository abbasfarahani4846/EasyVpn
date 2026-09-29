# EasyVPN — Master Implementation Prompt & Engineering Plan

> **Version:** 3.0 (research-verified and repo-verified, 2026-09-29)
> **Audience:** A self-contained instruction set for an autonomous AI engineer (or human team) implementing EasyVPN. Follow it sequentially. Where this document and your assumptions disagree, **this document wins**. Where this document is marked **VERIFY**, confirm the fact against the primary source before building on it (Appendix D lists sources).
> **Working directory:** repository root of this checkout. A Go core (`core/`) and Flutter app (`lib/`) are already scaffolded — **Appendix C is the authoritative description of what exists vs. what is a stub.** Do not rebuild what works; fix what is listed in Phase 0.

---

## 1. MISSION

Build **EasyVPN**: a production-grade, ultra-high-performance, cross-platform **VPN and proxy client** for Android, iOS, Windows, macOS and Linux. The quality bar is **Hiddify Next** and **FlClash**; in performance-sensitive areas (startup time, 10,000+ node handling, jank-free UI under live traffic) it must **exceed** them.

Hard requirements:

1. **Flutter UI + Go core.** All networking lives in Go (or in OS VPN APIs where unavoidable — IKEv2); Flutter never touches sockets.
2. **Multi-core, extensible architecture.** The primary engine is an embedded **sing-box** core. A `CoreAdapter` interface plus a **capability model** (§3.4) lets additional engines plug in without touching UI code: mihomo, Xray-core, platform IKEv2, and cores added later.
3. **Broad protocol coverage:** VLESS (Reality/Vision/XHTTP), VMess, Trojan, Shadowsocks(2022), Hysteria2, TUIC v5, WireGuard/AmneziaWG, **OpenVPN**, AnyTLS, ShadowTLS, IKEv2, and more later.
4. **Country-aware smart routing** (Iran first-class) with rule-sets that the app itself downloads and refreshes from verified GitHub sources, chosen by the user's detected/selected country.
5. **Import/Export/Backup** of configs, subscriptions, rules and settings in universal formats.
6. **Blazing performance.** Cold start < 2 s, connect < 1.5 s after core start, 10k nodes imported and searchable with zero dropped frames, ping of 5,000 nodes < 30 s.
7. **Deep UI customization** and a professional, Hiddify-grade routing/options surface.

---

## 2. VERIFIED TECHNOLOGY STACK (use exactly these)

| Layer | Technology | Version (verified 2026-09-29) | Notes |
|---|---|---|---|
| UI | Flutter (stable) | **3.47** / Dart **3.13** (released 2026-08-12) | Impeller is the default renderer on Windows/macOS/Linux. Build hooks ("native assets") are stable since 3.38 — optional path for bundling the Go library (§9) |
| State | flutter_riverpod | **3.0.x** (3.0.3 current) | Repo pins 2.6.1 → migrate (Phase 0) |
| DB | drift (+ `sqlite3_flutter_libs`) | 2.x, WAL mode, FTS5 | Replaces `shared_preferences` for structured data |
| FFI | `dart:ffi` + `package:ffi` | `NativeCallable.listener` for async callbacks | Android uses MethodChannel→JNI bridge (§4) |
| Core engine #1 | **sing-box** (Go module import) | **1.14.2 stable** (2026-09-24). `core/go.mod` already pins it | **Never depend on 1.15.0-alpha/beta builds.** Requires **Go ≥ 1.25** (repo: 1.25.5) |
| Core engine #2 (P2) | mihomo (Clash.Meta) | **v1.19.31** (2026-09-14) | Brings AmneziaWG v3.x, OpenVPN, ShadowQUIC/RestLS, ZeroTier/EasyTier |
| Core engine #3 (P1) | Xray-core | latest stable **VERIFY** (XHTTP wire format changed in Xray 26.9.x) | Needed for `xhttp` transport and VLESS `mlkem768x25519plus` encryption, which mainline sing-box lacks (§2.2) |
| Language core | Go | **1.25.x** | Already set |
| Android bridge | `c-shared` `.so` + Kotlin JNI module (or `gomobile bind` AAR) | — | FlClash pattern: the Android native module owns the library |
| TUN | VpnService (Android), NetworkExtension (iOS/macOS), Wintun (Windows), system TUN (Linux) | — | fd handed to sing-box via `tun.file_descriptor` / libbox platform interface |
| Rules (Iran) | `Chocolate4U/Iran-sing-box-rules` (`.srs`), `Chocolate4U/Iran-v2ray-rules` (`.dat`/`.mmdb`) | rolling, auto-built | Appendix A. Note the maintainer name: **Chocolate4U** (the older `FDeghy/Iran-v2ray-rules` is the ancestor; `bootmortis/iran-hosted-domains` is an upstream data source, not what the client downloads) |
| Rules (global) | `MetaCubeX/meta-rules-dat`, `Loyalsoldier/v2ray-rules-dat`, `v2fly/domain-list-community` | rolling | Appendix A |

### 2.1 Protocol matrix

P0 = MVP blocker · P1 = next release · P2 = backlog · P3 = opportunistic.

| Protocol | Pri | Implementation |
|---|---|---|
| VLESS (+Reality, Vision) | P0 | sing-box outbound |
| VMess, Trojan, Shadowsocks (incl. SS-2022) | P0 | sing-box |
| Hysteria2, TUIC v5 | P0 | sing-box (build tag `with_quic`) |
| WireGuard | P0 | sing-box **endpoint** (`wireguard`) |
| **OpenVPN client** | **P1** | sing-box **native endpoint `openvpn-client`** (added in **1.14.0**; `sing-openvpn` is already in `go.mod`). TLS mode + static-key mode, tls-auth/tls-crypt/tls-crypt-v2, data-ciphers, compression, pull-filters. **No external OpenVPN binary, no OpenVPN3, no CGO.** Import `.ovpn` files via the mapping in §5-F5 |
| AnyTLS, ShadowTLS v3, Naive, SSH, SOCKS/HTTP | P1 | sing-box |
| VLESS **XHTTP** transport, VLESS **mlkem** encryption | P1 | **Not in mainline sing-box** (only forks such as `sing-box-lx`, `sing-box-extended`). Implement `XrayAdapter` (Hiddify did the same in v2.0.5). Until then the parser must flag these nodes `unsupported_by_core:xhttp` — **never silently drop or mis-build them** |
| OpenConnect (AnyConnect/GlobalProtect/Fortinet/F5/Pulse/Juniper) | P2 | sing-box endpoint `openconnect` (1.14.0) |
| **AmneziaWG** v3.x | P2 | **mihomo adapter** (v1.19.30+). Mainline sing-box lacks it (PR #2670 open at time of writing, **VERIFY**) |
| **IKEv2/IPsec** | P2 | **Not via the Go core.** Platform adapter (`PlatformVpnAdapter`) behind `CoreAdapter`: Android `Ikev2VpnProfile`/IPsec library (API 30+), iOS/macOS `NEVPNProtocolIKEv2`, Windows built-in RAS IKEv2, Linux strongSwan/NetworkManager. Supports PSK, EAP-MSCHAPv2 and certificates |
| mihomo engine as a whole (Clash-only features) | P2 | second `CoreAdapter` |
| MASQUE, Tailscale, Snell, ZeroTier, EasyTier, Mieru | P3 | sing-box/mihomo when stable. MASQUE appeared in sing-box **1.15 alphas** — do not build on it until 1.15 stable |

### 2.2 Censorship reality (design input, not a guarantee)

Community/vendor reports (low-reliability sources — **VERIFY** in the field) say that in Iran in 2026 **VLESS+Reality and Hysteria2 work**, while **plain WireGuard and OpenVPN are detected and blocked**; AmneziaWG (obfuscated WireGuard) was developed in response to Russian blocking. Therefore:

- Default protocol ordering for `country=ir` in auto-select: Reality/Vision → Hysteria2/TUIC → Trojan/VLESS-WS/gRPC/XHTTP → AnyTLS/ShadowTLS → WireGuard/AmneziaWG → OpenVPN.
- OpenVPN/WireGuard stay fully supported (users bring their own servers) but are never preferred by auto-select in restrictive countries.
- Ship TLS anti-DPI options (Hiddify "TLS tricks"): ClientHello **fragmentation** (size/sleep ranges), **padding**, **mixed-case SNI**, plus optional uTLS fingerprint and ECH. Region=Iran enables fragmentation by default.

---

## 3. ARCHITECTURE OVERVIEW

```
┌────────────────────────────────────────────────────────────────────┐
│                        Flutter (Dart, 5 platforms)                 │
│  features/{dashboard,proxies,subscription,routing,settings,logs}  │
│  core/{providers(Riverpod 3), database(Drift), theme, i18n}        │
└──────────────┬─────────────────────────────────────────────────────┘
               │  CoreBridge (single facade, platform-routed)
   ┌───────────┴─────────────┬──────────────────────┬────────────────┐
   │ Android                 │ Desktop (Win/Mac/Lin)│ iOS            │
   │ MethodChannel →         │ authenticated local  │ App Groups +   │
   │ Kotlin CoreModule →     │ IPC (UDS / named     │ NE PacketTunnel│
   │ libeasycore.so (JNI)    │ pipe) to core child  │ process, core  │
   │ (in-process c-shared)   │ process + optional   │ static-linked  │
   │                         │ privileged helper    │ in extension   │
   └───────────┬─────────────┴──────────┬───────────┴───────┬────────┘
               │        same JSON protocol envelope          │
┌──────────────┴────────────────────────┴───────────────────┴────────┐
│                        Go Core (libeasycore)                       │
│  cmd/libeasycore  → exported C symbols                             │
│  cmd/easycoreproc → desktop process-mode RPC server                │
│  pkg/engine   → lifecycle FSM, core registry + capability routing  │
│  pkg/adapter  → singboxAdapter (P0), xrayAdapter (P1),             │
│                 mihomoAdapter (P2), platformVpnAdapter/IKEv2 (P2)  │
│  pkg/config   → universal parser (URI/base64/Clash/sb JSON/Xray    │
│                 JSON/SIP008/.ovpn/wg-quick) → ProxyNode            │
│  pkg/router   → country profiles, rule compiler (sing-box route+dns)│
│  pkg/rulesync → registry, downloader, validator, scheduler (NEW)   │
│  pkg/pinger   → bounded goroutine pool, TCP + URL tests            │
│  pkg/stats    → per-connection + global counters, speed calc       │
│  pkg/subs     → subscription fetch/refresh scheduler (NEW)         │
│  pkg/geoip    → country detection (NEW)                            │
│  pkg/transport→ event bus (priority+bulk), batching, framed IPC    │
└────────────────────────────────────────────────────────────────────┘
```

### 3.1 Core embedding rules (critical — do not deviate)

- **Import sing-box as a Go module** (`github.com/sagernet/sing-box`). Never vendor, never shell out to a `sing-box` binary. Build `option.Options` programmatically from the internal `ProxyNode` + routing model, then `box.New(...)` → `Start()` / `Close()` (this is what `core/pkg/adapter/adapter.go` already does).
- All protocol support comes from the embedded cores. Do **not** implement any protocol from scratch (IKEv2 is the only exception, and it delegates to OS APIs).
- Generate the core config **in Go**. Dart never sees sing-box JSON (it only exports it on request).
- **Build tags are mandatory.** The Makefile must pass an explicit `-tags` list. Start from `with_quic,with_utls,with_wireguard,with_gvisor,with_clash_api,with_ech` (Hiddify's set, plus what sing-box 1.14 needs for OpenVPN/AnyTLS/etc.) and **VERIFY against the 1.14.2 `include` package** — a missing tag silently removes a protocol at runtime ("unknown outbound type"). Add a CI test that starts a box with one outbound of every P0/P1 type and fails if any type is unregistered.
- **sing-box 1.14 deprecations you must not use** (removed in 1.16/1.17): legacy DNS address-filter fields (`ip_cidr`/`ip_is_private` without `match_response`), legacy DNS `strategy` rule action, `independent_cache`, `store_rdrc`, Hysteria v1 tuning fields, **`download_detour` on remote rule-sets**, and the TUN `stack` option. Emit the new DNS rule schema (`evaluate` action + `match_response`). Rule-set merge semantics changed in 1.14 (merged matching only for single `default` rules) — golden-test every generated `route` block against real 1.14.2.

### 3.2 Licensing & distribution compliance (non-negotiable)

- sing-box is **GPL-3.0** (with linking exceptions for specific components). The Go core is therefore GPL-affecting: keep `core/` open, add `LICENSE` + `NOTICE` (currently missing).
- Store builds: follow Hiddify's precedent of a "Play flavor" if policy review demands it; App Store builds must not bundle interpreters (no Lua/JS-based cores).
- MaxMind GeoLite2 (if used) requires CC BY-SA attribution: ship an attribution screen and source links.

### 3.3 IPC protocol (Android, desktop and iOS share the envelope)

- Method call: `{"id":"<ulid>","method":"Start","args":{...}}` → `{"id":"<ulid>","result":{...},"error":"..."}`.
- Events (core → Dart): `state`, `log`, `delay`, `stats`, `ruleSync`, `subSync`, `crash`.
- **Never embed pre-serialized JSON strings inside args** — use structured JSON values (FlClash lesson).
- Go event queues: a **priority queue** (state/delay/geo/ruleSync) and a **bulk queue** (log/traffic), 256 entries each; a full queue evicts its own oldest; **core work never blocks on event delivery**. (`core/pkg/transport/bus.go` implements the base — extend, don't rewrite.)
- Batching: flush at 32 messages or every **16 ms**; priority first, but guarantee one bulk slot after 8 priority messages (starvation guard).
- `stats` events: at most **4 Hz** (250 ms aggregate) with totals + speeds; logs are level-filtered in Go.
- Desktop process mode: replace stdin/stdout with an **authenticated UDS (macOS/Linux) / named pipe (Windows)**: random per-launch token, verify peer PID matches the launched process, loopback/pipe ACL to current user only. Keep stdio only for `--debug`.

### 3.4 Multi-core selection & capability model

Each `ProxyNode` carries `requires: []Capability` computed by the parser (e.g. `xhttp`, `mlkem`, `awg`, `openvpn`, `ikev2`, `reality`). Each `CoreAdapter` exposes `Capabilities()`. The engine:

1. Chooses the adapter whose capabilities ⊇ node.requires (prefer sing-box; then xray; then mihomo; then platform).
2. If none is available, returns a typed error `unsupported_by_core:<cap>`; the UI shows a "needs core X — enable in Settings ▸ Cores" chip. Never silently mis-build.
3. Only **one tunnel core runs at a time**. Node switch across different cores = stop + start behind the same UI state (no state flap visible to the user beyond `connecting`).

Extend `CoreAdapter` (currently `Name/Start/Stop/SwitchNode/UrlTest/Running` in `core/pkg/adapter/adapter.go:49-58`) with `Capabilities()`, `Stats()` and `Version()`.

### 3.5 Lifecycle ownership (FlClash lessons, mandatory)

- One Dart facade: `CoreBridge.start/restart/stop/close`; `close()` is terminal.
- Flutter is **optimistic**; the native layer (service/process owner) is **authoritative**. Identity checks discard obsolete requests; a revision counter coalesces overlapping restarts.
- Unexpected core death → `crash` event → recovery UI; never remain "connected" on a dead core. **When the native library is missing, the app must show "core unavailable", not a fake "connected"** (the current stub fallback lies — Phase 0).
- Windows: verify named-pipe peer PID; one core instance at a time; stale leases block new starts until cleaned.

---

## 4. PLATFORM INTEGRATION MATRIX

| Concern | Android | Windows | macOS | Linux | iOS |
|---|---|---|---|---|---|
| Core mode | in-process `.so` via JNI | child process + named pipe | child process + UDS | child process + UDS | static in PacketTunnel ext. |
| TUN | VpnService fd → core | Wintun (bundled, UAC flow) | NE PacketTunnel fd | /dev/net/tun (CAP_NET_ADMIN) | NE fd |
| System proxy | n/a | WinINET per-user | networksetup | gsettings (best effort) | NE proxy settings |
| Auto-start | boot receiver + Always-on VPN | Run key / Task Scheduler | SMAppService | autostart .desktop | Connect On Demand |
| Tray | n/a | tray_manager, close→tray | menu-bar extra | AppIndicator | n/a |
| Quick tile | TileService | — | — | — | — |
| Split tunneling | per-app allow/disallow | process-name rules | process rules (limits) | best effort | per-app (managed) |
| QR import | camera (`mobile_scanner`) | file/image decode | same | same | camera |
| Privileged ops | system dialog | UAC → optional helper service | auth prompt → helper | pkexec | none |

**Android (P0):** Kotlin `CoreModule` owns `libeasycore.so`. `VpnService.Builder.establish()` fd goes to the core (copy Hiddify's `AndroidVpnService` approach); `protect()` must be callable from Go for every outbound socket; handle `onRevoke()` → full stop. Manifest additions (currently absent): `INTERNET`, `FOREGROUND_SERVICE` (+ `_SPECIAL_USE`/connectedDevice type as required by target SDK), `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `<service android:permission="android.permission.BIND_VPN_SERVICE">`, TileService. Replace `com.example.easyvpn` with the real application id.

**iOS/macOS (P2, after Android/desktop):** core statically linked in a PacketTunnel provider; App Group shared container; macOS sandbox entitlements must add `com.apple.security.network.client` (missing today).

**Desktop:** the build must bundle `easycoreproc` (and Wintun on Windows) into the runner output — currently nothing copies them.

---

## 5. FUNCTIONAL SPECIFICATIONS

### F1. Universal config & subscription engine (P0)

- **Parse** (Go, streaming where possible). `core/pkg/config/parser.go` and `xray.go` already handle: JSON auto-detect → Clash YAML → base64 (2 layers) → URI lines; vless, vmess, trojan, ss (SIP002), hysteria2, tuic, socks, http(s), wireguard; Xray client-config JSON arrays and sing-box outbound arrays. **Add:** SIP008 JSON, `.ovpn` and `wg-quick .conf` files, `anytls://`, `ssh://`, `naive+https://`, and Clash `proxies:` entries for `anytls`, `hysteria2`, `tuic`, `wireguard`.
- **Fidelity rule:** every field a builder needs must survive parse → store → start. Parse `xhttp` (path, host, mode, `extra` JSON), VLESS `encryption` (mlkem), `flow`, Reality (`pbk`, `sid`, `spx`), `fp`, `alpn`, `ech`, mux. If the active core cannot honor a field, set `requires` (§3.4) — do not drop it.
- **Subscriptions:** per-profile name, URL, refresh interval, UA override, "fetch via proxy if direct fails" (log both attempts), parse `subscription-userinfo` (traffic/expiry) and `profile-update-interval` headers, dedupe by `(protocol,server,port,credentials)` and mark duplicates. Each refresh emits `subSync{added,removed,failed}`; N consecutive failures flag the profile in UI.
- Node IDs are stable content hashes so favorites/aliases survive re-import (already in `protocol/types.go`).
- **Sample data:** `sub_dart.txt` (base64 vless list, 7/17 use `xhttp`, many use `mlkem` encryption), `sub_sample.json` (17 Xray configs), `sub_singbox.json` (reference target output). Move them into `test/fixtures/` **sanitized** (replace UUIDs/keys) and use them as parser golden tests.

### F2. Node management at 10k+ scale (P0)

- **Storage:** Drift/SQLite (WAL). Table `nodes`: `id, profile_id, name, protocol, server, port, latency, alive, is_favorite, group_tag, requires, raw_json, created_at`. Indexes: `(profile_id, latency)`, `(protocol)`, `(server)`; **FTS5** over `(name, server)`.
- **Secrets** (uuid/password/private keys) live in `flutter_secure_storage`, referenced by id from `raw_json`; never plaintext in Drift or logs.
- Import 10k nodes: parse in a Go call / Dart isolate (never on the UI isolate), single transaction, progress every 1k, budget < 5 s.
- **UI:** `ListView.builder` (or `super_sliver_list`), keyset pagination (never `OFFSET`), 150 ms debounced FTS search, group tabs, sort by latency/name, favorites-first. No `FutureBuilder` per row.
- **Pinger (Go):** bounded worker pool (default 50, cap 128, configurable), 3 s per node, modes **TCP** and **URL test** through the node (`http://cp.cloudflare.com/generate_204` / `connectivitycheck.gstatic.com/generate_204`). Progress in ≥100 ms batches, never one event per node. **The current URL mode falls back to TCP when no dialer is wired — wire it** to a temporary per-node sing-box outbound or a shared `urltest` group.
- Background re-check of `alive=false` nodes every 30 min while connected (cheap TCP only).

### F3. Country-aware routing + rule-set engine (P0)

**Country detection (Go `pkg/geoip`)** on first run and on locale/SIM change: Android SIM/locale → OS locale + timezone → optional MMDB lookup of the direct egress IP → **manual override always wins**; emit the result so the UI can confirm ("We detected Iran — change?").

**Rule-set manager (Go `pkg/rulesync`, new):**
- Ships a registry (`assets/rules/registry.json`, schema in Appendix A). Each rule-set: `tag, category(country|ads|security|service|geo), format(srs|dat|mmdb), urls[] (primary + mirrors), sha256?, refresh_hours, min_singbox, verified_at`.
- **The app downloads; sing-box only reads local files.** Because `download_detour` is deprecated (§3.1), generate `type:"local"` rule-sets pointing at the cache dir. Download flow: try mirrors in order (GitHub raw → jsDelivr → testingcf.jsdelivr → user mirrors); on failure **retry through the active proxy** (loopback mixed inbound) — mandatory in Iran; validate (size cap 32 MB, `.srs` magic `SRS` + version byte, `.dat` protobuf sanity, optional SHA-256), then **atomic rename**; schedule refresh (default 24 h, exponential backoff, jitter); conditional requests (`ETag`/`If-Modified-Since`).
- Bundle a **baseline snapshot** of the Iran set in app assets so first launch works with no network (Iranian users often cannot reach GitHub before connecting).
- Users can add **custom rule-set URLs** (`.srs`/`.dat`, or `geosite:`/`geoip:` names for `.dat` mode) and manual rules.
- Rule-set sync status (timestamp, size, source used, next refresh) is shown on the Routing page. **Replace the fake `Future.delayed` sync in `routing_page.dart:49-55` with real `SyncRuleSets` calls.**

**Routing presets:**

| # | Preset | Behavior |
|---|---|---|
| 1 | `bypass_local_country` (default for detected country) | ads/malware blocked; LAN + local-country domains/IPs direct; everything else proxy |
| 2 | `bypass_lan_only` | LAN direct; rest proxy (no ads block) |
| 3 | `global_proxy` | all via tunnel except LAN |
| 4 | `bypass_proxy` (inverted) | proxy only selected apps/domains; rest direct |
| 5 | `custom` | user rule table |

> Names above are canonical (`core/pkg/router/model.go:17-20`). The Dart UI currently uses `bypass_local_lan` / `block_ads_only` — rename Dart to match (Phase 0).

**Rule order (fixed, documented in the UI):**
1. `hijack-dns` + sniff (always first).
2. Ads / malware / phishing / cryptominer **block** (toggles).
3. LAN / private ranges → direct.
4. **Service overrides** — an explicit list forced to **proxy** even when a country rule would match them (e.g. WhatsApp, Telegram, Google/YouTube endpoints hosted on Iranian-classified CDNs) and a list forced **direct** (domestic banks/government/payment). *Rationale: Hiddify issues #1065/#1066 show "Region: Iran" direct rules breaking WhatsApp and misclassifying Iranian apps.* Keep the lists editable and shipped in the registry.
5. Local-country rule-sets (`geosite-ir`, `geoip-ir`) → direct.
6. Custom user rules (`domain`, `domain_suffix`, `domain_keyword`, `ip_cidr`, `port`, `process_name`, `package_name`, `rule_set` → `direct|proxy|block`).
7. Final → proxy (or per mode).

Emit **only `rule_set` references**; legacy `geosite`/`geoip` fields no longer exist. Every referenced tag must be declared: **fix the current bug where non-IR countries reference undeclared `geosite-<cc>`/`geoip-<cc>` tags (box creation fails).** Compile rules only for countries present in the registry; unknown country ⇒ `global_proxy` with a UI notice.

**Per-country pack: Iran defaults** — block ads on; bypass LAN on; `geosite-ir`+`geoip-ir` direct; TLS fragment on; per-app bypass suggestion list for Android (Iranian banking/marketplace apps, user-editable); DNS split (below). Also expose Hiddify-style options: region selector, block-ads, bypass-LAN, TLS tricks, mux, ECH, fake-IP, IPv6 mode, connection test URL, DNS servers.

**DNS (P0):** per-country profile — domestic domains → local/DoH resolver, foreign → proxied DoH (e.g. `https://1.1.1.1/dns-query`), **FakeIP in TUN mode**, all DNS through the core (no leaks), DNS rules mirror route rules using the 1.14 schema. DNS servers are user-editable.

### F4. Core lifecycle & connection UX (P0)

- States: `disconnected → connecting → connected → disconnecting → disconnected | error(reason)`; the Go state machine is authoritative (wire the currently no-op `StateHook`).
- **Connect < 1.5 s** on warm cache: pre-warm rule-sets/DNS at app start, compile config off the critical path.
- **Selector-outbound design:** the tunnel runs `selector("proxy") → {node outbounds…}` plus `urltest("auto")`. **Node switch = selector hot-swap via the core API — no tunnel teardown** (today `SwitchNode` always errors and restarts: `adapter.go:153-157`). Node switch < 300 ms, no state flap. For 10k nodes only the active node + top-N (default 50) are materialized as outbounds; others are compiled on demand.
- **TUN is real:** `Engine.StartWithNode` currently discards `tunEnabled` (`engine.go:123`). Implement TUN inbound (fd handoff on mobile, Wintun/system TUN on desktop) and system-proxy mode.
- Real stats: fill `upBps/downBps` (sing-box traffic manager) — `GetStats` currently returns zeros.
- **Connection mode (user-selectable, FlClash-style):** `mode ∈ {tun, system_proxy, both}` plus an optional `proxy_only` (local mixed port only, no OS changes).
  - `tun` — TUN inbound captures all traffic; system proxy untouched. Needs VpnService (Android) / Wintun+elevation (Windows) / NE (macOS/iOS) / CAP_NET_ADMIN (Linux).
  - `system_proxy` — no TUN, no elevation. Core listens on the mixed inbound (`127.0.0.1:<port>`, local auth per §7) and the app sets the OS proxy (WinINET / `networksetup` / gsettings). **Not available on Android/iOS** (hide the option there; mobile is always `tun`, with optional `proxy_only` for advanced users).
  - `both` — TUN + system proxy together (apps that honor the system proxy skip TUN overhead; everything else is still captured). Keep the mixed inbound and TUN inbound in one core instance; TUN must exclude the core's own traffic (auto-route with `route_exclude`/`protect`) to avoid loops.
  - Rules: the mode is stored in settings and passed in `Start{mode}`; the generated config emits inbounds accordingly (`tun-in` and/or `mixed-in`). **Switching mode while connected = rebuild inbounds only (core restart), never leaving stale system-proxy or TUN state.** On disconnect, crash or app exit the app **always restores the previous OS proxy settings** (persist the prior value before overriding; restore on next launch if a crash left it set).
  - UI: a segmented control on the Dashboard (TUN | Proxy | Both) plus details in Settings (mixed port, allow-LAN, bypass list for system proxy, TUN MTU/auto-route/strict-route/IPv6, per-app split). Show a clear permission/elevation prompt when the chosen mode needs it and a graceful fallback message if denied.
  - Tray menu (desktop) and Android Quick Tile expose the same mode switch.
- Auto-failover (opt-in): on N consecutive URL-test failures switch to best node in the same profile.
- Reconnect on resume (desktop), network change (Android `ConnectivityManager`), VPN revoke.

### F5. Import / Export / Backup (P0)

- **Import paths:** paste, file (`.yaml/.json/.txt/.conf/.ovpn`), URL/subscription, QR (camera + image file), drag-drop (desktop), deep links `easyvpn://import?url=…`, `sing-box://import-remote-profile?url=…`, `clash://install-config?url=…`, `hiddify://import/<url>`, and `vless://…` style intents.
- **`.ovpn` → `openvpn-client` mapping** (Go, in `pkg/config/ovpn.go`): `remote host port [proto]` → `servers[]` (`server`,`server_port`,`network`); `proto udp|tcp` → `network`; `<ca>/<cert>/<key>` or `ca/cert/key` files → `tls.certificate` / `client_certificate` / `client_key` (inline PEM arrays); `tls-auth`/`tls-crypt`/`tls-crypt-v2` + `key-direction` → `tls.control_wrap{type,key,direction}`; `cipher`/`data-ciphers`/`data-ciphers-fallback` → `cipher`/`data_ciphers`/`data_ciphers_fallback`; `auth` → `auth`; `auth-user-pass` → `username`/`password` (prompt user, store in secure storage); `comp-lzo`/`compress` → `compression_lzo`/`compression`; `redirect-gateway` → `redirect_gateway`+flags; `route`/`pull-filter`/`route-nopull` → `routes`/`pull_filters`/`route_no_pull`; `remote-cert-tls server` → `tls.remote_certificate_tls`; `verify-x509-name` → `tls.server_name`(+`_type`); `mssfix`/`fragment`/`ping-restart`/`reneg-sec` → matching fields. Unmapped directives → warnings list, never silent. Static-key mode is legacy: warn.
- **`wg-quick` `.conf`** → sing-box `wireguard` endpoint (Interface/Peers, `AllowedIPs`, `PersistentKeepalive`, `MTU`; AmneziaWG `Jc/Jmin/Jmax/S1/S2/H1–H4` → `requires: awg`).
- **Export:** single node (URI), selection, whole profile → **Clash YAML**, **sing-box JSON**, or **URI list**; share sheet/save dialog. QR generation for single nodes.
- **Full backup (encrypted):** AES-256-GCM, key from passphrase via **Argon2id**; container = zipped JSON (settings, profiles, nodes, custom rules, rule-set registry overrides, favorites, service overrides); restore validates schema version and migrates; optional weekly local auto-backup.
- **Settings export/import** as plain JSON (secrets excluded) for support/debug.

### F6. UI/UX (P0 unless starred ★ = P1)

- **Dashboard:** animated connect ring (state-colored), current node+profile, live down/up speeds (60 s rolling chart, 4 Hz), session totals, active-node latency badge, real exit-IP/country lookup (through the tunnel — **not** the current name-substring guess), quick preset switcher.
- **Proxies:** virtualized list, group tabs, search, sort, "ping all / ping visible" with progress, per-node menu (favorite, rename, copy URI, test URL, export, QR), badge for `requires` capability.
- **Subscriptions:** profile cards (node count, last refresh, traffic/expiry bar, auto-refresh toggle), add-sheet (URL/paste/file/QR), refresh-now, error banners.
- **Routing:** country selector (flag + auto-detect chip), preset radio-cards, rule-set list with status/refresh, service-override editor, custom rules editor (type → matcher → outbound, drag-reorder), DNS section, TLS-tricks section.
- **Settings:** appearance, cores (enable/disable sing-box/xray/mihomo, versions), core options (log level, mux, sniff, MTU, allow-LAN, ports, local auth), TUN/system-proxy, auto-start, tray behavior, backup/restore, language, about (GPL + GeoLite2 attribution).
- **Theme engine ("highly customizable"):** light/dark/system, **AMOLED true-black**, Material You dynamic color (Android 12+), custom accent picker + per-feature accents, font scale 0.85–1.3, density (compact/comfortable), optional Fluent/Cupertino-flavored controls on desktop/macOS, layout options (bottom bar/rail/side drawer), configurable dashboard widgets ★.
- **i18n:** ICU messages via `intl` + ARB; **`fa` and `en` complete at P0**, RTL verified, Jalali date option ★.
- **Desktop tray:** connect/disconnect, last-profile submenu, quick node switch (top 10 by latency), open dashboard, quit.
- **Android:** Quick Settings tile, persistent notification with actions, boot auto-connect, per-app tunneling UI, Always-on VPN compatibility.
- **Onboarding ★:** first-run country pick, recommended preset, optional sample subscription.

### F7. Logging & diagnostics (P0)

Ring buffer (10k entries) in Go, level-filtered, batched to Dart; log page with level filter/search/copy/share; one-tap **diagnostics bundle** (sanitized config, last 500 log lines, rule-sync status, core versions, platform info; regex-strip UUIDs, passwords, private keys). A debug screen can dump the exact generated core config, validated before `Start`.

### F8. Core management & auto-select ★ (P1)

- Settings ▸ Cores lists installed adapters + versions; the user can disable one.
- **Auto-select** picks the best node per region hint (§2.2 protocol ordering + URL-test latency), with a "prefer protocol" override.
- Xray/mihomo cores are bundled as **library imports** (preferred) or, if licensing/size forces it, as a signed sidecar binary launched by the desktop helper — never downloaded unsigned at runtime.

---

## 6. PERFORMANCE BUDGETS (acceptance-tested, not aspirational)

| Metric | Budget |
|---|---|
| Flutter cold start → interactive dashboard | < 2.0 s (release, mid-range device) |
| Core `Start()` → `connected` (warm rules) | < 1.5 s |
| Import 10,000 nodes (already fetched) | < 5 s; 0 dropped frames > 32 ms |
| Ping 5,000 nodes (TCP, 50 workers) | < 30 s; UI stays 60/120 fps |
| Search across 10k nodes | first results < 50 ms |
| Node switch while connected | < 300 ms, no teardown |
| Traffic stats overhead | 0 per-packet allocations in Dart; Go-side aggregation only |
| Memory, idle connected (10k nodes) | core ≤ 120 MB, Dart heap ≤ 150 MB |
| Desktop core process ready-for-RPC | < 500 ms |

Techniques (mandatory): FTS5 + keyset pagination; parsing/inserting in a Go call or a Dart isolate (`Isolate.run`/`compute`); materialize only active + top-N nodes into the running core; 4 Hz stats; batched events (§3.3); no synchronous FFI on the UI isolate (**the current `easy_core_ffi.dart` calls the core synchronously on the UI isolate — move to a long-lived worker isolate with `NativeCallable.listener` for events**); worker pool 50→128; jsDelivr/conditional-GET to shrink rule updates.

Enforce with `flutter test --profile` frame-timing tests, Go `-bench` for parser/pinger, and a CI job failing on > 20 % regression.

---

## 7. SECURITY & PRIVACY REQUIREMENTS

- Secrets in `flutter_secure_storage` (Keychain/Keystore/DPAPI/libsecret); never in Drift plaintext or logs; redaction regexes for UUID/private-key/base64 credentials in diagnostics.
- Loopback listeners bind `127.0.0.1` only. **Local mixed-port auth (user/pass) ON by default** when `allow-lan=false` (FlClash issue #1934: any local app can otherwise ride the proxy). Debug controller ports require a token.
- All downloads over HTTPS, size-capped (32 MB), magic-byte validated, written to a sandboxed cache then atomically swapped; verify hashes where the publisher provides them.
- No telemetry by default; crash reporting strictly opt-in.
- Never route loopback/private ranges through the proxy by default; refuse rules that would route the IPC channel through the tunnel (SSRF/loop guard).
- **Repo hygiene:** no real UUIDs/keys in the repository (the three root sample files currently contain some — sanitize and move to `test/fixtures/`; consider the exposed values burned).

---

## 8. TESTING & ACCEPTANCE

- **Go unit:** parser fixtures per URI flavor (Reality, ss2022, hysteria2+obfs, xhttp, mlkem), `.ovpn`/`wg-quick` mapping fixtures, YAML/JSON mapping, router/DNS **golden outputs per preset per country**, pinger under fake dialer, **outbound-type registration test** (§3.1). `core/pkg/router` and `core/pkg/engine` currently have **no tests** — add.
- **Go integration:** local echo + SOCKS server; full path through the adapter (`live_test.go` is the base); rule-set download against a local file server incl. proxy-fallback path; selector hot-swap without dropping a live connection.
- **Flutter:** Riverpod provider tests, goldens for dashboard states (disconnected/connecting/connected/error/core-missing), theme snapshots (light/dark/AMOLED/fa-RTL), Dart↔Go **contract round-trip test** (same JSON fixtures decoded on both sides).
- **Perf:** §6 budgets in CI where feasible.
- **Manual matrix per release** (`/docs/QA_MATRIX.md`): Android API 24 & 34 (per-app VPN, revoke, always-on), Windows 10/11 (UAC, Wintun), macOS (notarized, NE), Ubuntu 22.04 (TUN perms), iOS 15+.

**Global Definition of Done (every phase):** compiles for all 5 targets; zero analyzer warnings; unit tests green; no TODO without issue link; new strings via i18n; docs updated; no secrets committed.

---

## 9. REPOSITORY LAYOUT (target state)

```
EasyVPN/
├── core/                          # Go module (GPL-3.0)
│   ├── cmd/libeasycore/           # exported C symbols
│   ├── cmd/easycoreproc/          # desktop process-mode RPC server (UDS/pipe, token auth)
│   ├── cmd/easycore-helper/       # optional privileged helper (desktop)
│   ├── pkg/{adapter,config,engine,router,rulesync,pinger,stats,subs,geoip,transport,protocol}
│   ├── go.mod (go 1.25.x, sing-box v1.14.x)
│   └── Makefile                   # explicit -tags; targets: c-shared (win/linux/darwin/android arm64+amd64), AAR, XCFramework, process binaries
├── android/app/src/main/kotlin/…/CoreModule.kt + VpnService
├── ios/Runner + PacketTunnelExtension        (P2)
├── lib/
│   ├── core/{bridge,database,providers,theme,i18n,security}
│   ├── features/{dashboard,proxies,subscription,routing,settings,logs,onboarding}
│   └── main.dart
├── assets/rules/registry.json + assets/rules/baseline/*.srs   # the assets/ dir is declared in pubspec but MISSING today — create it
├── test/fixtures/                 # sanitized sample subscriptions
├── docs/{MASTER_PROMPT.md,QA_MATRIX.md,LICENSES.md}
├── .github/workflows/             # CI (missing today)
├── LICENSE, NOTICE
└── pubspec.yaml
```

Native-library bundling: keep per-platform build scripts (Makefile → `bin/` → runner bundle) as the baseline; evaluating Flutter/Dart **build hooks** to drive the Go build is optional and must not block Phase 1–5.

---

## 10. IMPLEMENTATION ROADMAP (execute in order; each phase ends with its checklist)

### Phase 0 — Repair & foundations (≈1 week) — **do this first**

Each item lists its acceptance check.

1. **Single schema source of truth.** `core/pkg/protocol/types.go` defines `ProxyNode`; mirror it in Dart (`lib/core/models`) **including all builder-required fields** (uuid, tls, reality, transport incl. xhttp, flow, encryption, alpn, …). Fix `TestBatchPing` arity/result shape (Go: 2 args → `{"results":[…]}`; Dart binds 1 and decodes a list) and routing-mode naming. ✅ Contract round-trip test green on both sides; real `startProxy` no longer fails with "missing uuid".
2. **Honest failure modes.** Remove the stub-success fallback in `easy_core_ffi.dart`; show "core unavailable". Fix `activeNodeProvider` (`null as dynamic`, `app_providers.dart:122`). Remove fake IP-info. ✅ Widget test for core-missing state.
3. **Build correctness.** Explicit `-tags` in `core/Makefile` (§3.1); add Android amd64 + AAR targets; outbound-registration CI test. Create `assets/` (+`assets/rules/`) or remove from pubspec. ✅ `go test ./...` + `flutter analyze` + `flutter test` green in CI.
4. **Dependency migration.** `pubspec.yaml`: riverpod ^3, drift(+dev), flutter_secure_storage, mobile_scanner, app_links, tray_manager, window_manager, dynamic_color, super_sliver_list; drop unused (`share_plus`/`file_picker` only if truly unused; keep if F5 needs them). Bump `share_plus`/`file_picker` to current. ✅ App boots.
5. **Fix known Go bugs:** undeclared country rule-set tags; `RouteFinal` per mode; first-URL-only rule-sets (superseded by rulesync); wire `StateHook`; fill speeds in stats. ✅ Router golden tests for IR/CN/RU/global.
6. **Repo hygiene:** sanitize + move sample files to `test/fixtures/`; add `LICENSE`/`NOTICE`, a real `README.md`, `.github/workflows` (go test, flutter analyze/test, cross-compile matrix); change Android application id; add Android manifest permissions/service stubs. ✅ CI green; no secrets (`grep` for the old UUID returns nothing).

### Phase 1 — Go core spine (1–1.5 weeks)
1. Extend `CoreAdapter` (§3.4); implement **selector + urltest** config, real TUN inbound plumbing (fd/`file_descriptor`), real traffic stats, hot `SwitchNode`.
2. Builders for AnyTLS, ShadowTLS, Naive, SSH, **`openvpn-client`** and mux/fragment/ECH/uTLS options; capability computation for `xhttp`/`mlkem`/`awg`.
3. Parser additions (`.ovpn`, `wg-quick`, SIP008, anytls/ssh/naive).
4. Pinger URL-mode wired through the core; batched progress.
5. Connection modes (§F4): inbound generation for `tun` / `system_proxy` / `both` / `proxy_only`.
6. Desktop IPC: authenticated UDS/pipe with `Start/Stop/SwitchNode/GetStats/ParseContent/PingBatch/FetchSubscription/SyncRuleSets/SetRouting`.
✅ `go test ./...` green incl. fixtures; local echo round-trips via TUN-less mixed inbound; hot switch keeps a live connection; OpenVPN endpoint config passes `box` validation on a fixture `.ovpn`.

### Phase 2 — Dart bridge + storage (1 week)
1. `CoreBridge` facade: worker-isolate FFI (desktop) / MethodChannel→JNI (Android); `NativeCallable.listener` events.
2. Drift schema (profiles, nodes, settings, custom_rules, service_overrides, ruleset_status, logs) with WAL, indexes, FTS5; repositories with keyset pagination; secure-storage for secrets.
3. Riverpod 3 providers: settings, profiles, nodes(paged/filtered), connection state, stats stream, rulesync status.
✅ 10k synthetic nodes import < 5 s; paged list holds 60 fps in integration test; provider tests green.

### Phase 3 — Routing & rule-set sync (1 week)
1. `pkg/geoip` detection + manual override; `pkg/rulesync` (registry, mirrors, proxy-fallback, validation, atomic swap, scheduler, baseline snapshot).
2. Router compiler: 5 presets × countries, service overrides, TLS tricks, 1.14 DNS schema, FakeIP.
3. Routing UI (real sync, status, custom rules, overrides).
✅ Under the IR preset: `google.com`→proxy, `digikala.com` and an IR IP→direct, `ads.example`→block, `web.whatsapp.com`→proxy (service override); verified by an integration test through the local core with a local rule-set server.

### Phase 4 — Android (1–1.5 weeks)
CoreModule (JNI), VpnService + fd handoff + `protect()`, foreground notification with actions, TileService, boot receiver, per-app mode, revoke handling, crash/recovery paths.
✅ QA matrix rows pass on API 24 & 34 emulators + one device; connect < 1.5 s; switch < 300 ms.

### Phase 5 — Desktop (1–1.5 weeks)
Process-mode core + privileged helper (one-time elevation, Wintun install), system proxy (WinINET/networksetup/gsettings) with save/restore of prior OS proxy state and crash-recovery, all four connection modes, tray mode switch, auto-start, close-to-tray, TUN permission flows; bundle core binaries in runners.
✅ Each mode works and cleans up (proxy restored after disconnect/kill -9 + relaunch); Windows UAC once; macOS dev-signed run + notarization script; Ubuntu TUN perms documented + graceful error.

### Phase 6 — Feature completion (1–1.5 weeks)
Subscription scheduler + health, export (YAML/JSON/URI), encrypted backup/restore, deep links, QR (camera + file), logs page + diagnostics bundle, theme engine, onboarding, i18n fa/en + RTL pass.
✅ E2E: import sub URL → ping → connect → switch → export → backup → wipe → restore → reconnect.

### Phase 7 — Xray adapter & advanced protocols (1–1.5 weeks)
`XrayAdapter` (XHTTP, mlkem encryption) with capability routing; F8 core management/auto-select. **First VERIFY** whether the mainline sing-box release current at that time gained XHTTP; if so, prefer it over a second core.
✅ All 17 fixture nodes in `sub_dart.txt`/`sub_sample.json` build and connect to a local test server (or report a typed `unsupported_by_core` error).

### Phase 8 — Performance & hardening (1 week)
Enforce §6 budgets in CI; memory profile the 10k-node flow; security review vs §7; redaction + loop-guard + local-auth tests.

### Phase 9 — Extensions (backlog, in order)
iOS PacketTunnel app → mihomo adapter (AmneziaWG, ShadowQUIC…) → IKEv2 platform adapters → OpenConnect → load-balance groups → plugin registry for community cores (Hiddify-style extensions) → MASQUE/Tailscale after their stable release.

---

## 11. EXPLICIT NON-GOALS (do not build now)

- No server/panel component, no user accounts, no billing.
- No self-implemented crypto or protocol stacks beyond what the embedded cores provide.
- No Electron/web UI, no Flutter web target.
- No auto-update framework in P0 (store-distributed; document the manual desktop update path).
- No IPv6-only edge cases beyond core defaults (document as a limitation).

---

## 12. WHEN IN DOUBT (decision rules for the implementing AI)

1. Native library first, process second, external binary last. Never shell out where a library call exists.
2. Anything that can run in Go, runs in Go. Dart = UI + storage + orchestration.
3. Never block the UI isolate; never push per-packet or per-node events to Dart (batch).
4. Every external fetch has: mirror list, timeout, size cap, validation, and a "through proxy" fallback.
5. Every generated core config is dumpable (debug screen) and validated by the core before `Start`; show the **exact** error, not "failed".
6. Preserve user data across upgrades: DB migrations, content-hash node IDs, schema-versioned backups.
7. Never silently drop or mis-build an unsupported field — surface a typed capability error (§3.4).
8. Never rely on deprecated sing-box options (§3.1) or on pre-release cores.
9. Unsure about a fact? It is either marked **VERIFY** (check Appendix D sources) or you must check the primary source before coding.
10. Refactor the existing skeleton freely, but keep the `features/<name>/<name>_page.dart` naming and existing provider names to limit churn.

---

## Appendix A — Verified rule-set registry (seed `assets/rules/registry.json`)

All URLs below returned HTTP 200/206 on 2026-09-29. Prefer `.srs` (sing-box ≥ 1.8). Mirrors are mandatory entries because `raw.githubusercontent.com` is throttled/blocked in some regions. Default `refresh_hours: 24`, `format: "srs"`.

**Iran (`ir`)** — repo `Chocolate4U/Iran-sing-box-rules`, branch `rule-set`, raw base `https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/`, jsDelivr base `https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-sing-box-rules@rule-set/`:

| tag | file | category |
|---|---|---|
| `geosite-ir` | `geosite-ir.srs` (non-`.ir` Iranian domains; `.ir` TLD is matched separately by suffix rule) | country |
| `geoip-ir` | `geoip-ir.srs` (Iranian IPs, CDNs, hosting) | country |
| `geosite-ads-all` | `geosite-category-ads-all.srs` | ads |
| `geosite-malware` / `geosite-phishing` / `geosite-cryptominers` | same-named `.srs` | security |
| `geoip-malware` / `geoip-phishing` | same-named `.srs` | security |
| service sets (optional) | `geoip-telegram.srs`, `geoip-google.srs`, `geoip-cloudflare.srs`, … , `geosite-social.srs`, `geosite-nsfw.srs` | service |

Same maintainer, other formats: `Chocolate4U/Iran-v2ray-rules` branch `release` (`geoip.dat`, `geosite.dat`, `-lite` variants, `security.dat`, `security-ip.dat`, `Country.mmdb`, `Country-lite.mmdb`, `Security-IP.mmdb`, `Services.mmdb`; jsDelivr `…/gh/Chocolate4U/Iran-v2ray-rules@release/…`) and `Chocolate4U/Iran-clash-rules` (mihomo `.mrs`, for the mihomo adapter).

**Global ads/privacy & generic geo** — `MetaCubeX/meta-rules-dat`: branch `sing` (sing-box `.srs`, e.g. `sing/geo/geosite/category-ads-all.srs`, `sing/geo/geosite/cn.srs`, `sing/geo/geoip/cn.srs`), branch `meta` (mihomo `.mrs`), releases at `https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/<file>`; mirrors `https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/…` and `https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/…`. Also `Loyalsoldier/v2ray-rules-dat` (`…/release/geosite.dat`, `geoip.dat`) and `v2fly/domain-list-community` for `.dat` mode.

**China (`cn`)** — `MetaCubeX/meta-rules-dat` `geosite-cn`, `geoip-cn` (paths above).

**Russia (`ru`)** — `runetfreedom/russia-v2ray-rules-dat` (releases `latest/download/geosite.dat|geoip.dat`, rebuilt every 6 h; contains `ru-blocked`, `ru-available-only-inside`, ads) and `runetfreedom/russia-blocked-geosite` (`.srs` + `.txt`). Community `.srs` conversions exist (`JaJaBiX/russia-v2ray-rules-srs`) — **VERIFY** before use.

**Other maintained sets worth registering as optional:** `KaringX/karing-ruleset` (branch `sing`), `razaxq/dns-blocklists-sing-box` (HaGeZi/OISD ad-blocklists as `.srs`).

**Iran-hosted fallback mirror (**UNVERIFIED file layout**):** the CensorDB site (`https://censordb.mahsanet.com/`) is reachable (HTTP 200) and is described as an open database of blocked domains, but **no stable `.srs`/`.dat` download URLs could be confirmed**. Ship its registry entry **disabled**, with `verified_at: null`; enable only after confirming the URL layout and license.

**Registry schema (exact):**
```json
{
  "version": 2,
  "countries": {
    "ir": {
      "presets": {
        "bypass_local_country": {
          "block": ["geosite-ads-all", "geosite-malware", "geosite-phishing", "geoip-malware", "geoip-phishing"],
          "direct": ["geosite-ir", "geoip-ir"],
          "proxy_overrides": ["geoip-telegram"],
          "tls_tricks": {"fragment": true}
        }
      },
      "service_overrides": {
        "proxy":  [{"domain_suffix": ["whatsapp.com", "whatsapp.net"]}],
        "direct": []
      },
      "rule_sets": [
        {
          "tag": "geosite-ir", "category": "country", "format": "srs", "refresh_hours": 24,
          "min_singbox": "1.8.0", "verified_at": "2026-09-29", "sha256": null,
          "urls": [
            "https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-ir.srs",
            "https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-sing-box-rules@rule-set/geosite-ir.srs"
          ]
        }
      ]
    }
  },
  "global": { "rule_sets": [] }
}
```

**How to add a country:** (1) find a maintained `.srs` source, (2) verify URLs return 200 and start with the `.srs` magic, (3) add `rule_sets` + a preset entry + optional `service_overrides`, (4) add router golden tests, (5) add a country flag + localized name. No Go code change is needed for a data-only country pack.

## Appendix B — Exported core commands (v1, JSON envelope per §3.3)

| Method | Args → Result | Notes |
|---|---|---|
| `Init` | `{cacheDir}` → `{version, cores:[{name,version,capabilities}]}` | idempotent |
| `Start` | `{nodeId, presetId, mode:"tun"\|"system_proxy"\|"both"\|"proxy_only", customRules?, tun:{mtu,autoRoute,strictRoute,perApp?}, systemProxy:{bypass[],port}, dns:{…}, tlsTricks:{…}}` → `{session}` | compile, validate, start |
| `Stop` | `{}` → `{}` | graceful; flush stats |
| `SwitchNode` | `{nodeId}` → `{}` | selector hot-swap; cross-core = restart |
| `PingBatch` | `{nodes:[id…], mode:"tcp"\|"url", workers}` → streamed `delay` events | throttled |
| `ParseContent` | `{content, format:"auto"}` → `{nodes:[Node…], warnings[]}` | import preview; supports `.ovpn`/`wg-quick` |
| `FetchSubscription` | `{url, ua?, viaProxy?}` → `{nodes, added, removed, failed, userinfo?}` | dedup + health |
| `SetRouting` | `{country, presetId, customRules, ruleSets:[tag…], serviceOverrides}` → `{configSnapshotId}` | hot-apply where possible |
| `SyncRuleSets` | `{tags?}` → streamed `ruleSync` events | mirrors + proxy fallback |
| `DetectCountry` | `{}` → `{country, source, confidence}` | |
| `GetStats` | `{}` → `{upBps,downBps,totals,conns}` | pull fallback |
| `SetLogLevel` / `ExportConfig` | … | `ExportConfig` → `{format:"clash"\|"singbox"\|"uri", payload}` |

Events: `state{from,to,reason?}`, `stats{…}` (4 Hz), `delay{nodeId,ms,mode}` (batched), `log{level,msg,ts}` (batched), `ruleSync{tag,status,bytes,source,err?}`, `subSync{profileId,added,removed,failed}`, `crash{reason,stack}`.

> Current C exports (`core/cmd/libeasycore/main.go`): `InitCore, RegisterEventCallback, StartProxy, StopProxy, SwitchProxy, GetStatsJSON, ParseSubscription, TestBatchPing(nodesJSON, mode), SetCountry, SetRoutingMode, SetLocalPort, SetRoutingModel, FreeString`. Keep them working while migrating to the envelope above (a thin `Call(method, argsJSON)` export is acceptable). Desktop `easycoreproc` currently exposes `GetState, Start, Stop, ParseContent, PingBatch, SetRoutingModel, SetRouting` over stdio.

## Appendix C — Current repository state (verified by code inspection on 2026-09-29; nothing was built or run)

**Real and working (build on it):**
- `core/` — module `easyvpn/core`, Go 1.25.5, `sagernet/sing-box v1.14.2` (`go.mod:7`); indirect deps already include `sing-openvpn`, `sing-openconnect`, `sing-anytls`, `sing-shadowtls`, `sing-snell`, `sing-quic`, `sing-tun`, wintun, gVisor. No mihomo/xray dependency.
- `pkg/protocol/types.go` — `ProxyNode` with content-hash IDs; `ProtoOpenVPN` constant (`:25`, `:180`) but no mapping.
- `pkg/config/parser.go` (802 lines) + `xray.go` (478 lines) — multi-format parser (see F1).
- `pkg/adapter/adapter.go` — `CoreAdapter` + `SingBoxAdapter` running a real `box.New`/`Start`/`Close`, mixed inbound on `127.0.0.1:2080`, 250 ms stats loop, `UrlTest`. `build_outbound.go` maps vless/vmess/trojan/shadowsocks/socks/http/hysteria2/tuic + WireGuard endpoint.
- `pkg/router/{model,compile}.go` — presets, sniff/hijack-dns, ads/tracker reject, LAN direct, country rule-sets (remote `.srs`), custom rules.
- `pkg/engine/engine.go` (state machine), `pkg/pinger/pinger.go` (TCP worker pool), `pkg/transport/bus.go` (priority+bulk queues), `pkg/stats/stats.go` (unused).
- `cmd/libeasycore` (c-shared) and `cmd/easycoreproc` (stdio JSON-RPC). Go tests exist for adapter, boxjson, helpers, schema, live path, parser, pinger, bus.
- `lib/` (~2,400 lines): Riverpod 2.6 app shell with 5 pages (dashboard, proxies, subscription, routing, settings), theme, `shared_preferences` storage.

**Stubs / defects (Phase 0 and later phases fix these):**

| # | Defect | Where |
|---|---|---|
| 1 | Dart↔Go `TestBatchPing` arity/shape mismatch | `lib/core/ffi/easy_core_ffi.dart` vs `core/cmd/libeasycore/main.go` |
| 2 | Routing-mode names differ (`bypass_local_lan`/`block_ads_only` vs `bypass_local_country`/`bypass_lan_only`/`global_proxy`/`custom`) | `lib/features/routing/routing_page.dart` vs `core/pkg/router/model.go:17-20` |
| 3 | Dart `ProxyNodeModel` keeps only id/name/type/server/port/latency/raw_config → Go builders fail ("vless: missing uuid") | `lib/core/models/models.dart` |
| 4 | `Engine.StartWithNode` discards TUN flag | `core/pkg/engine/engine.go:123` |
| 5 | `SwitchNode` always errors → restart | `core/pkg/adapter/adapter.go:153` |
| 6 | Stats have no speeds; `GetStats` returns zeros; `StateHook` no-op | `adapter.go`, `engine.go` |
| 7 | `RouteFinal` always `proxy` | `core/pkg/router/compile.go:120` |
| 8 | Non-IR countries reference undeclared rule-set tags → box creation fails; only `urls[0]` used, mirrors ignored | `core/pkg/router/compile.go:~159` |
| 9 | `xhttp` transport silently dropped; VLESS `encryption` (mlkem) never passed; AnyTLS/ShadowTLS/Naive/SSH/OpenVPN unmapped | `core/pkg/adapter/build_outbound.go` |
| 10 | Makefile passes no `-tags` | `core/Makefile` |
| 11 | Fake rule sync (`Future.delayed`) | `lib/features/routing/routing_page.dart:49-55` |
| 12 | Stub FFI returns fake success → UI shows "connected" without a core; sync FFI on UI isolate; no event callback binding | `lib/core/ffi/easy_core_ffi.dart` |
| 13 | `null as dynamic` crash; fake IP-info from node name | `lib/core/providers/app_providers.dart:122` |
| 14 | `assets/` + `assets/rules/` declared but missing; unused deps; `flutter_localizations` declared, no ARB | `pubspec.yaml` |
| 15 | Android manifest lacks INTERNET/VpnService/foreground service/boot/tile; app id `com.example.easyvpn`; debug signing on release | `android/…` |
| 16 | iOS/macOS: no PacketTunnel/App Group; macOS sandbox lacks `network.client` | `ios/`, `macos/` |
| 17 | Windows/Linux runners don't bundle core/Wintun/`easycoreproc`; no tray/system-proxy/UAC | `windows/`, `linux/` |
| 18 | No CI, no LICENSE/NOTICE, README is the Flutter default | repo root |
| 19 | Sample files at repo root contain real-looking UUID/keys | `sub_dart.txt`, `sub_sample.json`, `sub_singbox.json` |
| 20 | No tests for `pkg/router`, `pkg/engine`; only one Dart widget test | `core/pkg`, `test/` |

Missing entirely: Drift/SQLite + FTS, secure storage, downloader/registry/scheduler for rule-sets, country detection, custom-rules and DNS UI, per-app split tunneling, SIP008, `.ovpn`/`wg-quick` import, file/QR/deep-link import, export, encrypted backup, logs/connections pages, onboarding, i18n/RTL, tray/window management, theme engine beyond dark/light+accent, mihomo/Xray/IKEv2 adapters.

## Appendix D — Verified facts, sources, and VERIFY-before-use list

**Facts verified online (2026-09-29):**
- sing-box 1.14.2 stable (2026-09-24); 1.15.0-alpha.x in progress; 1.14.0 release notes (OpenVPN client/server, OpenConnect, Snell, L3 forwarding/bridge, gRPC API + dashboard, DNS `evaluate`, Go 1.25 required) — https://github.com/SagerNet/sing-box/releases , https://github.com/SagerNet/sing-box/releases/tag/v1.14.0 , https://sing-box.sagernet.org/changelog/
- sing-box `openvpn-client` endpoint schema (introduced 1.14.0; `on_demand` in 1.15.0) — https://sing-box.sagernet.org/configuration/endpoint/openvpn-client/
- mihomo v1.19.29–1.19.31 (AmneziaWG v3.x, OpenVPN tls-crypt-v2, ShadowQUIC/RestLS, ZeroTier/EasyTier) — https://github.com/MetaCubeX/mihomo/releases
- Flutter 3.47 / Dart 3.13 (Impeller default on desktop; released 2026-08-12), build hooks stable since 3.38 — https://flutter.dev/blog/whats-new-in-flutter-3-47 , https://flutter.dev/blog/announcing-flutter-3-38-dart-3-10-building-the-future-of-apps
- flutter_riverpod 3.0.3 — https://pub.dev/packages/flutter_riverpod
- Hiddify architecture (Flutter + Riverpod + Drift; sing-box core with gRPC/FFI; region presets; TLS tricks; Xray backend in v2.0.5) — https://github.com/hiddify/hiddify-app , https://github.com/hiddify/hiddify-core , https://hiddify.com/manager/basic-concepts-and-troubleshooting/How-the-TLS-Trick-works-and-its-usage/ ; region issues https://github.com/hiddify/hiddify-app/issues/1065 , https://github.com/hiddify/hiddify-app/issues/1066
- FlClash (Flutter + mihomo) — https://github.com/chen08209/FlClash
- Rule sources — https://github.com/Chocolate4U/Iran-sing-box-rules , https://github.com/Chocolate4U/Iran-v2ray-rules , https://github.com/Chocolate4U/Iran-clash-rules , https://github.com/MetaCubeX/meta-rules-dat , https://github.com/runetfreedom/russia-v2ray-rules-dat , https://github.com/runetfreedom/russia-blocked-geosite , https://github.com/Loyalsoldier/v2ray-rules-dat
- AmneziaWG status in sing-box — https://github.com/SagerNet/sing-box/pull/2670 ; forks https://github.com/Leadaxe/sing-box-lx
- Censorship protocol reports (vendor blogs, low reliability) — e.g. https://v2route.com/blog/hysteria2-vs-vless-reality-iran , https://securityledger.com/2026/05/raccoonline-report-vless-and-p2p-architecture-defeat-irans-2026-machine-learning-dpi/

**VERIFY before use:**
1. Exact `-tags` set for sing-box 1.14.2 (`include` package) — build a box with one outbound/endpoint of each supported type.
2. Whether mainline sing-box has gained `xhttp`/VLESS-mlkem at implementation time (conflicting reports; the 1.14.x docs do not list them).
3. AmneziaWG in mainline sing-box (PR #2670) vs mihomo-only.
4. MASQUE stability (appears only in 1.15 alphas).
5. CensorDB download URL layout and license (Appendix A).
6. Xray-core version compatible with server-side deployments (XHTTP wire-format change in 26.9.x).
7. Iran protocol-effectiveness claims (§2.2) — treat as hints.
8. Flutter 3.47 patch level and package versions (`drift`, `mobile_scanner`, `tray_manager`, `app_links`) at implementation time.
