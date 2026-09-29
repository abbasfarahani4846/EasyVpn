# EasyVPN — Master Implementation Prompt & Engineering Plan

> **Version:** 2.0 (research-verified, 2026-09-29)
> **Audience:** This document is a self-contained instruction set for an autonomous AI engineer (or human team) implementing EasyVPN. Follow it sequentially. Where this document and your assumptions disagree, **this document wins**.
> **Working directory:** repository root of this checkout (Flutter app + `core/` Go engine already scaffolded — see Appendix C for the current state and migration checklist).

---

## 1. MISSION

Build **EasyVPN**: a production-grade, ultra-high-performance, cross-platform **VPN and proxy client** for Android, iOS, Windows, macOS, and Linux — the quality bar is **Hiddify Next** and **FlClash**, and in performance-sensitive areas (startup time, 10,000+ node handling, jank-free UI under live traffic) it must **exceed** them.

Hard requirements:

1. **Flutter UI + Go core.** All networking lives in Go; Flutter never touches sockets.
2. **Multi-core, extensible architecture.** The primary engine is an embedded **sing-box** core. A `CoreAdapter` interface must make it trivial to plug in additional engines later (mihomo, Xray-core, native OpenVPN, IKEv2 via platform APIs).
3. **Country-aware smart routing** with auto-downloaded, auto-updated rule-sets from verified GitHub sources (Iran first-class: domestic direct, foreign proxied, ads blocked).
4. **Import/Export/Backup** for configs and settings in universal formats.
5. **Blazing performance.** Cold app start < 2 s, connect < 1.5 s after core start, 10k nodes imported and searchable without a single dropped frame, ping of 5,000 nodes < 30 s.

---

## 2. VERIFIED TECHNOLOGY STACK (use exactly these)

| Layer | Technology | Version (verified) | Notes |
|---|---|---|---|
| UI | Flutter (stable) | **3.47.x** (Impeller enabled on desktop by default) | Dart 3.x |
| State | flutter_riverpod | **3.x** (stable since 2025-09) | Current scaffold pins 2.5.1 → migrate (Appendix C) |
| DB | drift (+ `sqlite3_flutter_libs`) | 2.x, WAL mode | Replaces `shared_preferences` for structured data |
| FFI | dart:ffi + package:ffi | NativeCallable.listener (Dart ≥ 3.1) for async callbacks | Android uses MethodChannel→JNI bridge instead (§4.3) |
| Core engine | sing-box (Go library import) | **1.13.x** line (stable; ≥ 1.12 required) | OpenVPN client endpoint ✅, AnyTLS ✅, MASQUE ✅ (1.13) |
| Language core | Go | **1.25.x** | `go.mod` currently pins 1.22 → bump |
| Android bridge | gomobile bind (`-bind AAR`) or FFI `c-shared` + JNI Kotlin module | — | FlClash pattern: Android native module owns the library |
| TUN drivers | VpnService (Android), NetworkExtension (iOS/macOS), Wintun (Windows), system TUN (Linux) | — | fd passed to sing-box via libbox PlatformInterface / `tun.file_descriptor` |
| Rules (Iran) | Chocolate4U/Iran-sing-box-rules | `.srs` binary rule-sets | Verified URLs in Appendix A |
| Rules (global) | MetaCubeX/meta-rules-dat, v2fly/domain-list-community | `.srs` / `.dat` | Appendix A |
| Optional mirror (Iran-hosted, works without VPN) | CensorDB (mahsanet) `.srs`/`.dat` mirrors | — | Configurable user mirror list; GitHub raw is throttled in Iran |

**Protocol matrix (what the app must support out of the box):**

| Protocol | Status | Implementation |
|---|---|---|
| VLESS (+Reality, Vision, XTLS) | P0 | sing-box outbound |
| VMess | P0 | sing-box |
| Trojan / Trojan-Go | P0 | sing-box |
| Shadowsocks (incl. 2022 ciphers) | P0 | sing-box |
| Hysteria2 / TUIC v5 | P0 | sing-box |
| WireGuard | P0 | sing-box (wireguard-go) |
| AnyTLS, ShadowTLS v3, Naive, SSH, SOCKS/HTTP | P1 | sing-box |
| OpenVPN (client) | P1 | sing-box **native OpenVPN endpoint** (1.12+); no external binary needed |
| Mieru, SUSanic, etc. | P2 | sing-box if available |
| IKEv2/IPsec | P2 | **Not via Go core** — platform APIs (iOS/macOS `NEVPNManager`, Android StrongSwan integration or external client). Wrap behind `CoreAdapter`. |
| mihomo (Clash.Meta) engine | P2 | second `CoreAdapter` (mihomo ~v1.19.x) |

P0 = MVP blocker, P1 = next release, P2 = backlog/extension.

---

## 3. ARCHITECTURE OVERVIEW

```
┌────────────────────────────────────────────────────────────────────┐
│                        Flutter (Dart, 3 platforms)                 │
│  features/{dashboard,proxies,subscription,routing,settings,logs}   │
│  core/{providers(Riverpod 3), database(Drift), theme, i18n}        │
└──────────────┬─────────────────────────────────────────────────────┘
               │  CoreBridge (single facade, platform-routed)
   ┌───────────┴─────────────┬──────────────────────┬────────────────┐
   │ Android                 │ Desktop (Win/Mac/Lin)│ iOS            │
   │ MethodChannel →         │ JSON-RPC over local  │ App Groups +   │
   │ Kotlin CoreModule →     │ IPC (UDS / named     │ NE PacketTunnel│
   │ libeasycore.so (JNI)    │ pipe) to core child  │ process, core  │
   │ (in-process c-shared)   │ process (CGO_ENABLED │ static-linked  │
   │                         │ =0) + optional       │ in extension   │
   │                         │ privileged helper    │                │
   └───────────┬─────────────┴──────────┬───────────┴───────┬────────┘
               │        same JSON protocol envelope          │
┌──────────────┴────────────────────────┴───────────────────┴────────┐
│                        Go Core (libeasycore)                       │
│  cmd/libeasycore  → exported C symbols / RPC handlers              │
│  pkg/engine       → lifecycle FSM, CoreAdapter registry            │
│  pkg/adapter      → singboxAdapter (P0), mihomoAdapter, openvpn…   │
│  pkg/config       → universal parser: URIs, Clash YAML, sb JSON,   │
│                     base64 subs, SIP008 → internal Node model      │
│  pkg/router       → country profiles, rule-set compiler (srs/dat), │
│                     download_detour-aware rule sync                │
│  pkg/pinger       → bounded goroutine pool, TCP + URL (HTTP) tests │
│  pkg/stats        → per-connection + global counters, speed calc   │
│  pkg/subs         → subscription fetch/refresh scheduler           │
│  pkg/geoip        → country detection (locale/TZ/MMDB)             │
└────────────────────────────────────────────────────────────────────┘
```

### 3.1 Core embedding rules (critical — do not deviate)

- **Import sing-box as a Go module dependency** (`github.com/sagernet/sing-box`). Never fork, never vendor, never shell out to an `sing-box` binary. Construct options programmatically from our internal model and run `box.New(...)` → `Box.Start()` / `Box.Close()`.
- All protocol support comes from sing-box. Do **not** implement any protocol from scratch.
- Generate sing-box config **in Go** from our unified `Node` + routing model. Dart never sees sing-box JSON (it only exports it on request).

### 3.2 Licensing & distribution compliance (non-negotiable)

- sing-box is **GPL-3.0** (with an SPDX linking exception for Apache-2.0/MIT code in source form). This makes the Go core effectively GPL. Document it, keep `core/` open, and add LICENSE files.
- For **Google Play** builds: follow Hiddify's precedent — build a "Play flavor" that **removes/stubs interpreter-type functionality** if required by policy review (Apple guideline 3.3.2 analog: App Store builds must not bundle interpreters; sing-box is fine, but future adapters like Lua/JS-based cores are not).
- Never ship MaxMind GeoLite2 without honoring CC BY-SA attribution (ship attribution screen + source links).

### 3.3 IPC protocol (both Android and desktop use the same envelope)

- Method call: `{"id":"<ulid>","method":"Start","args":{...}}` → response `{"id":"<ulid>","result":{...},"error":"..."}`.
- Events (core → Dart): `state`, `log`, `delay`, `stats`, `ruleSync`, `crash`.
- **Never embed pre-serialized JSON strings inside args** — use structured JSON values (FlClash lesson).
- Event queues in Go: two bounded queues (256 each): a **priority queue** (state/delay/geo) and a **bulk queue** (log/traffic). Full queue evicts its own oldest; **core work must never block on event delivery**.
- Batching: flush at 32 messages or every **16 ms**; prioritize priority events but guarantee one bulk slot after 8 priority messages (starvation guard).
- Traffic `stats` events: push at most **4 Hz** (250 ms aggregates) with bytes/totals/speed; logs are level-filtered at the Go side.

### 3.4 Lifecycle ownership (FlClash lessons, mandatory)

- One shared facade in Dart: `CoreBridge.start/restart/stop/close`. `close()` is terminal.
- Flutter stays **optimistic**; the native layer (service/process owner) is **authoritative**. Identity checks discard obsolete requests; a revision counter coalesces overlapping restarts.
- Unexpected core death → emit `crash` event → Dart shows recovery UI; never leave "connected" state on a dead core.
- Windows: verify named-pipe peer PID matches the launched process PID; one core instance at a time; stale leases block new starts until cleaned.

---

## 4. PLATFORM INTEGRATION MATRIX

| Concern | Android | Windows | macOS | Linux | iOS |
|---|---|---|---|---|---|
| Core mode | in-process `.so` via JNI module | child process + named pipe | child process + UDS | child process + UDS | static-linked in PacketTunnel extension |
| TUN | VpnService fd → core | Wintun (bundled, admin elevation flow) | NE PacketTunnel fd | /dev/net/tun (CAP_NET_ADMIN) | NE fd |
| System proxy | n/a (TUN covers) | WinINET per-user + auth option | networksetup (manual instructions UI) | GNOME/KDE gsettings (best effort) | NE proxy settings |
| Auto-start | boot receiver + Always-on VPN support | registry Run key / Task Scheduler | SMAppService | autostart .desktop | n/a (Connect On Demand) |
| Tray | n/a | tray_manager + window close→tray | MenuBar extras | AppIndicator/Tray | n/a |
| Quick tile / Shortcuts | TileService ✅ | — | — | — | — |
| Split tunneling | per-app allow/disallow (VpnService Builder) | process-name rules via sing-box | process rules (sudo/helper limits) | cgroup/nft best-effort | per-app (managed) |
| QR import | camera (mobile_scanner) | file picker + image decode | same | same | camera |
| Privileged ops | system dialog | UAC elevation → optional helper service | auth prompt → helper | pkexec prompt | none needed |

**Android specifics (P0):** Kotlin `CoreModule` owns `libeasycore.so` (gomobile bind or `c-shared` + manual JNI). `VpnService.Builder.establish()` fd is passed to the core via libbox `PlatformInterface` (`TunInterface`) — copy the approach of Hiddify's `AndroidVpnService`. `protect()` must be callable from Go for every outbound socket fd. Handle `onRevoke()` → full stop.

**iOS specifics (P1, after Android/desktop):** core statically linked into the PacketTunnel Provider; UI talks via App Groups + a thin XPC wrapper; export/import and QR scanning live in the main app. Respect Apple 3.3.2 (no remote interpreters).

---

## 5. FUNCTIONAL SPECIFICATIONS

### F1. Universal config & subscription engine (P0)

- **Parse** (Go side, streaming where possible):
  - Raw URIs: `vless://`, `vmess://` (base64 JSON body), `trojan://`, `ss://` (SIP002 + legacy base64), `hysteria2://|hy2://`, `tuic://`, `wireguard://`, `socks://`, `http(s)://`.
  - Multi-link payloads: plain text, one URI per line; **Base64 whole-document** (detect + decode, recursive up to 2 layers).
  - Clash / mihomo YAML `proxies:` (map to internal Node; ignore unknown fields with warning).
  - sing-box JSON outbounds array; **SIP008** subscription JSON.
- **Subscriptions:** profiles with name, URL, auto-refresh interval (per-profile), user-agent override, `fetch via proxy if direct fails` (both attempts logged). Deduplicate by server:port:protocol:uuid and mark duplicates.
- **Health:** each refresh reports added/removed/failed counts as an event; a profile that fails N consecutive refreshes is flagged in UI.
- Node uniqueness key + stable IDs (content hash) so favorites/aliases survive re-import.

### F2. Node management at 10k+ scale (P0)

- **Storage:** Drift/SQLite (WAL). Table `nodes`: `id, profile_id, name, protocol, server, port, latency, alive, is_favorite, group_tag, raw_json, created_at`. Indexes on `(profile_id, latency)`, `(protocol)`, `(server)`; FTS5 index on `(name, server)` for instant search.
- Import 10k nodes: parse + insert in one Go/Dart transaction, progress events every 1k. Budget: < 5 s total.
- **UI:** `ListView.builder` (or `super_sliver_list`) + `Autocomplete`-style debounced search (150 ms) over FTS; group tabs by profile/group_tag; sorting by latency/name; favorites-first option. **No `FutureBuilder` per row.**
- **Pinger (Go):** bounded worker pool (default 50, cap 128, configurable), per-node timeout 3 s, two modes: TCP handshake RTT and real **URL test** (`GET http://cp.cloudflare.com/generate_204` through the node, HTTP status/time based). Progress events throttled to ≥ 100 ms batches. **Never** send one event per node.
- "Alive" maintenance: background re-check of alive=false nodes every 30 min while connected (cheap TCP only).

### F3. Country-aware routing + rule-set engine (P0)

- **Country detection (Go, on first run + on SIM/locale change):** Android SIM/locale → locale + timezone fallback → optional MMDB lookup of the direct egress IP → manual override stored in settings. Exposed as an event so UI can confirm.
- **Rule-set manager (Go):**
  - Ships a registry (JSON) of verified sources per country/category (Appendix A). Each entry: `tag, category(country|ads|privacy|geo), format(srs|dat), urls[](primary+mirrors incl. jsDelivr), sha256?, refresh_hours`.
  - Downloads to cache dir, validates (magic bytes for `.srs`), atomic swap, schedules refresh (default 24 h, backoff on failure), honors `download_detour`: **if direct download fails, retry through the active proxy** (mandatory for Iran).
  - User can add **custom rule-set URLs** (any `.srs`/`.dat` or `geosite:category` name) and custom manual rules.
- **Routing modes (presets):**
  1. `Bypass LAN & Local Country` — domestic direct, ads block on, rest proxy. **Default for detected country.**
  2. `Bypass Mainland Only` (CN/RU/IR style) — like 1 but without ads blocking.
  3. `Global Proxy` — everything through tunnel except LAN.
  4. `Bypass Proxy` (inverted: proxy only selected apps/domains).
  5. `Custom` — user rule table (domain_suffix / domain_keyword / ip_cidr / port / process_name / package_name / rule_set refs → direct|proxy|block).
- Rule order (fixed, documented in UI): ads-block → LAN → local-country direct → custom → final. The generated sing-box `route` block uses **rule_set references only** (no legacy geosite/geoip fields — those are removed in 1.12+).
- Rule-set sync status (timestamp, size, next refresh) surfaced in Routing page.
- **DNS (P0):** default profile per country: local DoH for domestic, proxied DoH for foreign, FakeIP enabled for TUN mode; anti-leak: all DNS through core; block-quic9 style ad DNS optional. Include `dns.rules` mirroring route rules (domestic domains → local DNS).

### F4. Core lifecycle & connection UX (P0)

- States: `disconnected → connecting → connected → disconnecting → disconnected | error(reason)`. State machine in Go is authoritative; Dart mirrors.
- **Connect < 1.5 s** after core start on a warm cache: pre-warm rule-sets/DNS at app start, compile sing-box config off the critical path, reuse Box where safe (node switch = rebuild config if topology changed, else hot-swap selector outbound — prefer selector-outbound design so switching nodes never tears down the tunnel).
- Node switching while connected: < 300 ms, no state flapping to `connecting`.
- Auto-failover option: on N consecutive URL-test failures, switch to best-latency node in the same profile (opt-in).
- Reconnect handling: system resume (desktop wake), network change (Android `ConnectivityManager`), VPN revoke.

### F5. Import / Export / Backup (P0)

- Import paths: paste, file (`.yaml/.json/.txt/.conf`), URL/subscription, QR (camera + image file), deep link `easyvpn://import?url=<...>` and `sn://`-style sing-box share links; drag-drop on desktop.
- Export: single node (URI), selection, whole profile → **Clash YAML**, **sing-box JSON**, or **URI list**; share sheet/save dialog.
- **Full backup (encrypted):** AES-256-GCM, key derived from passphrase with Argon2id; container = JSON (settings, profiles, custom rules, rule-set registry, favorites) zipped. Restore validates schema version and migrates. Auto-backup option (weekly, local only).
- Settings export/import as plain JSON (unencrypted) for support/debug.

### F6. UI/UX (P0 for listed, P1 for starred)

- **Dashboard:** big connect FAB with animated ring (state-colored), current node + profile, live down/up speed (chart 60 s rolling), session totals, latency badge of active node. Speeds update at 4 Hz from `stats` events.
- **Proxies:** virtualized list, group tabs, search, sort, "ping all / ping visible" with progress, per-node menu (favorite, rename, copy URI, test URL, export).
- **Subscriptions:** profile cards (name, node count, last refresh, auto-refresh toggle), add-sheet (URL/paste/file/QR), refresh-now, error banners.
- **Routing:** country selector (flag + auto-detect chip), mode presets as radio cards, rule-set registry list with status/refresh, custom rules editor (add row: type → matcher → outbound, drag to reorder), DNS section.
- **Settings:** appearance (theme engine below), core (log level, mux, sniff, mtu, allow-lan, ports), TUN/system-proxy toggles, auto-start, tray behavior, backup/restore, language, about (attribution screen for GeoLite2/CC-BY-SA + GPL notice).
- **Theme engine (starred "highly customizable"):** light/dark/system, **AMOLED true-black**, Material You dynamic color (Android 12+), custom accent (color picker) + optional per-feature accent, font scale 0.85–1.3, compact/comfortable density, optional Fluent/Cupertino-flavored controls on desktop/macOS.
- **i18n:** ICU messages, `fa` and `en` complete at P0, RTL-verified; plurals via `intl`.
- **Desktop tray:** connect/disconnect, last profile submenu, node quick-switch (top 10 by latency), open dashboard, quit.
- **Android:** Quick Settings tile, notification with persistent status + actions (connect/disconnect/switch), boot auto-connect option, per-app tunneling UI, "Always-on VPN" compatible.
- **Onboarding (P1):** first-run country pick + recommended preset + optional sample subscription.

### F7. Logging & diagnostics (P0)

- Ring buffer (10k entries) in Go, level-filtered, shipped to Dart in batches; log page with level filter + search + copy/share; crash breadcrumbs.
- One-tap **diagnostics bundle**: sanitized config, last 500 log lines, rule-sync status, core version, platform info (no secrets: strip UUIDs/passwords via regex).

---

## 6. PERFORMANCE BUDGETS (acceptance-tested, not aspirational)

| Metric | Budget |
|---|---|
| Flutter cold start → interactive dashboard | < 2.0 s (release, mid-range device) |
| Core `Start()` → `connected` event (warm rules) | < 1.5 s |
| Import 10,000 nodes (network already fetched) | < 5 s, UI jank: 0 dropped frames > 32 ms |
| Ping 5,000 nodes (TCP mode, 50 workers) | < 30 s; UI stays 60/120 fps |
| Search across 10k nodes | first results < 50 ms |
| Node switch while connected | < 300 ms |
| Traffic stats overhead | 0 allocations in Dart per packet — Go-side aggregation only |
| Memory, idle connected (10k nodes) | core ≤ 120 MB, Dart heap ≤ 150 MB |
| Desktop binary startup (core process mode) | core ready-for-RPC < 500 ms |

Enforce with: `flutter test --profile` golden perf tests, Go benchmarks (`go test -bench`) for parser/pinger, and a CI job that fails on regression > 20%.

---

## 7. SECURITY & PRIVACY REQUIREMENTS

- Secrets (UUIDs, passwords, private keys) stored in `flutter_secure_storage` (Keychain/Keystore/DPAPI/libsecret) — never in Drift plaintext, never in logs; diagnostics redaction regexes for UUID/private-key/base64-creds.
- Local RPC/loopback listeners: bind 127.0.0.1 only; if any controller port is exposed (debug builds), require token auth. FlClash incident #1934 (local apps can ride an unauthenticated proxy) is a known design hazard: ship the **local auth (user/pass on mixed port)** option ON by default in `allow-lan=false` builds.
- All downloads (rule-sets, subs) over HTTPS, size-capped (e.g., 32 MB), content-type-agnostic but magic-byte-validated, extracted/loaded in a sandboxed dir; update packages signature-checked where the source publishes hashes.
- No telemetry by default. Crash reporting strictly opt-in.
- Private-IP/localhost traffic never routed through proxy by default (prevents SSRF-style loops); core must refuse rules that route the IPC channel itself through the tunnel.

---

## 8. TESTING & ACCEPTANCE

- **Go unit tests:** parser fixtures per URI flavor (real-world samples incl. Reality, ss2022, hysteria2 with obfs), YAML/JSON mapping, rule compiler golden outputs, pinger pool under fake dialer.
- **Go integration:** spin a local echo SOCKS/HTTP server; assert full traffic path via mixed-in; rule-set fetch against local file server incl. `download_detour` fallback.
- **Flutter unit/widget:** Riverpod providers logic, golden tests for dashboard states (disconnected/connecting/connected/error), theme engine snapshots (light/dark/AMOLED/fa-RTL).
- **Perf tests:** §6 budgets as automated CI checks where feasible (parser/pinger benches; Flutter frame stats from integration test on Android emulator).
- **Manual matrix per release:** Android (API 24+, per-app VPN, revoke, always-on), Windows 10/11 (UAC elevation, Wintun install/uninstall), macOS (notarized, NE), Ubuntu 22.04 (TUN perms), iOS 15+ (NE) — device-file checklist in `/docs/QA_MATRIX.md`.

**Global Definition of Done (applies to every phase):** code compiles for all 5 targets with zero analyzer warnings; unit tests green; no TODOs without issue links; new user-facing strings via i18n; docs updated; no secrets committed.

---

## 9. REPOSITORY LAYOUT (target state)

```
EasyVPN/
├── core/                          # Go module (GPL-3.0 notice)
│   ├── cmd/libeasycore/           # exported C symbols + JSON-RPC server (desktop)
│   ├── cmd/easycore-helper/       # optional privileged helper (desktop)
│   ├── pkg/
│   │   ├── adapter/               # CoreAdapter interface + singboxAdapter (P0), mihomo/openvpn (P2)
│   │   ├── config/                # parser: URIs/YAML/JSON/SIP008 → Node; node hashing/dedup
│   │   ├── engine/                # lifecycle FSM, selector-outbound node switching
│   │   ├── router/                # routing modes, rule compiler (srs/dat refs), custom rules
│   │   ├── rulesync/              # registry, downloader (detour-aware), validator, scheduler
│   │   ├── pinger/                # worker pool, TCP + URL test
│   │   ├── stats/                 # counters, 4 Hz aggregator
│   │   ├── subs/                  # subscription fetch/refresh/dedup
│   │   ├── geoip/                 # country detection
│   │   └── transport/             # event queues, batching, framed IPC (pipe/UDS)
│   ├── go.mod (go 1.25)
│   └── Makefile                   # per-OS targets: c-shared, AAR, XCFramework, process binary
├── android/app/src/main/kotlin/…/CoreModule.kt   # JNI bridge + VpnService
├── ios/Runner + PacketTunnelExtension (P1)
├── lib/
│   ├── core/
│   │   ├── bridge/                # CoreBridge facade, platform impls (ffi/android-channel/rpc)
│   │   ├── database/              # Drift schema, DAOs, migrations (WAL)
│   │   ├── providers/             # Riverpod 3 (codegen)
│   │   ├── theme/                 # theme engine (AMOLED, accents, density)
│   │   ├── i18n/                  # arb files (en, fa)
│   │   └── security/              # secure storage, redaction, backup crypto
│   ├── features/{dashboard,proxies,subscription,routing,settings,logs,onboarding}
│   └── main.dart
├── assets/rules/registry.json     # default rule-set registry (Appendix A URLs)
├── docs/ (this file, QA_MATRIX.md, LICENSES.md)
└── pubspec.yaml
```

---

## 10. IMPLEMENTATION ROADMAP (execute in order; each phase ends with its checklist)

### Phase 0 — Foundations (½ week)
1. Bump `core/go.mod` to Go 1.25; add sing-box dependency (1.13.x).
2. Migrate `pubspec.yaml`: riverpod ^3, drift, flutter_secure_storage, app_links, mobile_scanner, tray_manager, window_manager, dynamic_color, super_sliver_list (or confirm ListView.builder approach), intl.
3. Define the **internal Node model** (Go + Dart parity, content-hash IDs) and the **IPC envelope** (§3.3) as the single source of truth (`core/pkg/protocol/types.go` mirrored by `lib/core/bridge/messages.dart`).
✅ Checklist: models compile both sides; JSON round-trip test green; CI skeleton (GitHub Actions matrix) runs `go test` + `flutter analyze/test`.

### Phase 1 — Go core spine (1–1.5 weeks)
1. `CoreAdapter` interface (`Start/Stop/SwitchNode/UrlTest/Stats`) + `singboxAdapter` running a real `box.Box` (mixed-in listener mode first, no TUN).
2. Config parser (all URI flavors + base64 + Clash YAML + sb JSON + SIP008) with fixtures.
3. Pinger worker pool (TCP + URL test) with batched progress.
4. Stats aggregator (4 Hz) + ring-buffer logger + event queue/batcher (§3.3).
5. Exported C symbols (`InitCore, Start, Stop, SwitchNode, PingBatch, ParseContent, SetRouting, GetStats, SetLogListener…`) and framed IPC server (named pipe/UDS) for desktop process mode.
✅ Checklist: `go test ./...` green incl. parser fixtures; a local echo server round-trips through the sing-box adapter; `make core-windows/darwin/linux/android` produce artifacts.

### Phase 2 — Dart bridge + storage (1 week)
1. `CoreBridge` facade: FFI impl (desktop) + MethodChannel→JNI impl (Android); async calls off UI isolate; `NativeCallable.listener` for events (desktop) / EventChannel batches (Android).
2. Drift schema (profiles, nodes, settings, custom_rules, ruleset_status, logs) with WAL + indexes + FTS5; repositories with pagination.
3. Riverpod 3 providers: settings, profiles, nodes(paged, filtered), connection state, stats stream, rulesync status.
✅ Checklist: import 10k synthetic nodes < 5 s; paged list scrolls at 60 fps in integration test; app runs with stub core when library missing (graceful demo mode).

### Phase 3 — Routing & rule-sync engine (1 week)
1. Country auto-detection + manual override.
2. `assets/rules/registry.json` with Appendix A entries; downloader (mirrors, sha256 when available, magic-byte validation, atomic swap, `download_detour` via proxy), scheduler with backoff.
3. Rule compiler → sing-box `route`+`dns` blocks for all 5 presets + custom rules; golden tests per preset per country.
✅ Checklist: with IR preset, `google.com` → proxy, `digikala.com`/IR IP → direct, `ads.example` → block (verified by integration test through local core).

### Phase 4 — Mobile platform integration (1–1.5 weeks)
1. Android: Kotlin CoreModule (JNI), VpnService + fd handoff, protect() hook, notification, TileService, boot receiver, per-app mode, revoke handling.
2. Error/recovery paths (§3.4) incl. process-crash event.
✅ Checklist: manual QA matrix rows for Android pass on API 24 & 34 emulators + one physical device; connect < 1.5 s; node switch < 300 ms.

### Phase 5 — Desktop platform integration (1–1.5 weeks)
1. Process-mode core (CGO_ENABLED=0 binary) + named pipe/UDS RPC + privileged helper (elevate once, own the core child, Wintun install).
2. System proxy (WinINET/networksetup/gsettings), tray (connect/quit/quick node), auto-start, close-to-tray, TUN permission flows.
✅ Checklist: Windows UAC flow one-time; macOS unsigned-dev run + notarization script stub; Ubuntu TUN perms documented + graceful error.

### Phase 6 — Feature completion (1–1.5 weeks)
1. Subscription scheduler + health; export (YAML/JSON/URI); encrypted backup/restore; deep links; QR (camera + file).
2. Logs page + diagnostics bundle; onboarding; i18n completion (fa/en, RTL pass).
✅ Checklist: E2E test — import sub URL → ping → connect → switch node → export → backup → wipe → restore → reconnect.

### Phase 7 — Performance & hardening (1 week)
1. Enforce §6 budgets (CI benches); fix regressions; memory profiling of 10k-node flows.
2. Security review vs §7; redaction tests; loopback-auth default; SSRF-loop guard tests.

### Phase 8 — Extensions (backlog, in priority order)
iOS PacketTunnel app → mihomo adapter → Xray-core adapter → IKEv2 platform integration → auto-failover & load-balance groups → plugin registry for community cores.

---

## 11. EXPLICIT NON-GOALS (do not build now)

- No server/panel component, no user accounts, no billing.
- No self-implemented crypto or protocol stacks in Go beyond what sing-box provides.
- No Electron/web UI, no Flutter web target.
- No auto-update framework in P0 (store-distributed; document manual update path for desktop).
- No IPv6-only edge cases beyond sing-box defaults (document as limitation).

---

## 12. WHEN IN DOUBT (decision rules for the implementing AI)

1. Native-lib first, process second, external binary last. Never shell out where a library call exists.
2. Any feature that can run in Go, runs in Go. Dart = UI + storage + orchestration only.
3. Never block the UI isolate; never push per-packet/per-node events to Dart (batch instead).
4. Every external fetch must have: mirror list, timeout, size cap, validation, and a "through proxy" fallback.
5. Every generated sing-box config must be dumpable (debug screen) and validated by `box` before `Start` — show the exact error, not "failed".
6. Preserve user data across upgrades: DB migrations + content-hash node IDs + schema-versioned backups.
7. The current skeleton (Appendix C) is a starting point — refactor freely, but keep the existing provider/feature names to limit churn.

---

## Appendix A — Verified rule-set registry (seed `assets/rules/registry.json`)

> Prefer `.srs` binary rule-sets (sing-box ≥ 1.8). jsDelivr mirrors are mandatory entries (GitHub raw is throttled in some regions). All entries: `refresh_hours: 24`, `format: "srs"`, `category` as shown.

**Iran (country: `ir`)** — source: `Chocolate4U/Iran-sing-box-rules`:
- `https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-ir.srs` (mirror: `https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-sing-box-rules@rule-set/geosite-ir.srs`) — tag `geosite-ir`
- `.../rule-set/geoip-ir.srs` (same repo/branch) — tag `geoip-ir` (includes Iranian CDNs: ArvanCloud, Derak, IranServer, ParsPack + messengers)
- `.../rule-set/geosite-category-ads-all.srs` — tag `geosite-ads-all` (Persian+foreign ads, low false positives)
- `.../rule-set/geosite-malware.srs`, `.../geosite-phishing.srs`, `.../geosite-cryptominers.srs`, `.../geoip-malware.srs`, `.../geoip-phishing.srs` — security set
- Extra categories available same branch: `geosite-social`, `geosite-nsfw`, `geosite-ads` (Persian-only), `geoip-cloudflare|google|telegram|...` for service-specific routing.

**Global ads/privacy** — `MetaCubeX/meta-rules-dat` (branch `sing`):
- `https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs` — tag `geosite-ads-all-global`
- `https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/microsoft@cn.srs` etc. as needed (CN-style service rules for future country packs)

**General geo** — `v2fly/domain-list-community` (via sing-geosite rule-set branch) for `geosite:cn`, `geosite:category-games@cn`, etc.; and `Loyalsoldier/v2ray-rules-dat` (`https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/...`) when `.dat` mode is needed for legacy adapters.

**Russia (future pack, pattern for adding countries)** — `runetfreedom/russia-v2ray-rules-dat` (auto-updated `.dat` + sing-box srs under `release/`).

**China (future pack)** — `MetaCubeX/meta-rules-dat` `geosite:cn`, `geoip:cn` (srs under `sing/geo/...`).

**Iran-hosted fallback mirror (works without VPN inside Iran; user-configurable):** CensorDB daily-built `.srs`/`.dat` mirrors (`censordb.mahsanet.com`, Iran-hosted by design). Ship disabled by default; enable per user choice.

**Registry schema (exact):**
```json
{
  "version": 1,
  "countries": {
    "ir": {
      "presets": {
        "bypass_local": ["geosite-ads-all","geosite-ads-all-global","geosite-ir","geoip-ir"],
        "block": ["block"]
      },
      "rule_sets": [
        {"tag":"geosite-ir","category":"country","urls":["https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-ir.srs","https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-sing-box-rules@rule-set/geosite-ir.srs"]}
      ]
    }
  },
  "global": {
    "rule_sets": [
      {"tag":"geosite-ads-all-global","category":"ads","urls":["https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs","https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/category-ads-all.srs"]}
    ]
  }
}
```

## Appendix B — Exported core commands (v1, JSON envelope per §3.3)

| Method | Args → Result | Notes |
|---|---|---|
| `Init` | `{cacheDir}` → `{version, singboxVersion}` | idempotent |
| `Start` | `{nodeId, presetId, customRules?, tun:{enabled, mtu, perApp?}, dns:{...}}` → `{session}` | compiles config; validates; starts Box |
| `Stop` | `{}` → `{}` | graceful; flushes stats |
| `SwitchNode` | `{nodeId}` → `{}` | selector hot-swap path |
| `PingBatch` | `{nodes:[id…], mode:"tcp"|"url", workers}` → streamed `delay` events | throttled batches |
| `ParseContent` | `{content, format:"auto"}` → `{nodes:[Node…], warnings[]}` | also used for import preview |
| `FetchSubscription` | `{url, ua?, viaProxy?}` → `{nodes, added, removed, failed}` | dedup + health |
| `SetRouting` | `{country, presetId, customRules, ruleSets:[tag…]}` → `{configSnapshotId}` | hot-apply where possible |
| `SyncRuleSets` | `{tags?}` → streamed `ruleSync` events | mirror+detour logic |
| `GetStats` | `{}` → `{upBps,downBps,totals,conns}` | pull fallback for events |
| `SetLogLevel` / `ExportConfig` | … | `ExportConfig` → `{format:"clash"|"singbox"|"uri", payload}` |

Events: `state{from,to,reason?}`, `stats{...}` (4 Hz), `delay{nodeId,ms,mode}` (batched), `log{level,msg,ts}` (batched), `ruleSync{tag,status,bytes,err?}`, `crash{reason,stack}`.

## Appendix C — Current skeleton state & migration checklist (verified by code inspection)

Present today: Flutter app (`lib/`) with Riverpod 2-style providers, direct `dart:ffi` bridge (`EasyCoreFFI`, fallback stub mode), 5 feature pages (dashboard/proxies/subscription/routing/settings), Drift-less `StorageService`; Go `core/` with engine (sing-box config builder stub — `_ = fullConfig`), parser, pinger, router, stats, C-entry stubs; `go.mod` pins Go 1.22, no dependencies yet.

Migrate per this plan:
1. `go.mod`: bump 1.25; add sing-box, quic-go transitively, gomobile (android only), yaml.v3.
2. Replace engine stub with `singboxAdapter` (Phase 1.1); keep existing `ParseSubscription` API surface but route through new parser.
3. FFI: keep desktop FFI path; add Android MethodChannel bridge; move all event delivery to batched `NativeCallable.listener` (currently none exist).
4. `pubspec.yaml`: riverpod ^3 (+ codegen), drift (+drift_dev/build_runner), flutter_secure_storage, mobile_scanner, app_links, tray_manager, window_manager, dynamic_color, super_sliver_list, intl (bump ≥ 0.20); drop `shared_preferences` for structured data (keep for trivial flags if convenient).
5. Keep file/feature naming (`features/<name>/<name>_page.dart`) — extend, don't rename.
```
