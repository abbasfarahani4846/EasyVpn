# EasyVPN v2 plan: all-in-one, one-button

Goal: one app for every kind of connection (V2Ray/Xray family, Hysteria/TUIC, WireGuard,
OpenVPN, SSH, WARP, Windscribe account servers), covering the whole device. The default UX is one big
button. Everything advanced (chains, per-app, routing, cores) is available but hidden
behind "Advanced".

Status legend: [x] done in this branch · [~] in progress · [ ] planned

---

## 1. Auto-update from GitHub Releases (open source → GitHub is the update server)

* Build identity: CI passes `--dart-define=BUILD_LABEL=<label>` (`1.2.3` or `nightly-<sha7>`),
  `BUILD_CHANNEL=stable|nightly`; local builds report `dev` and never auto-update.
* Core `pkg/update`:
  * `Check(channel, current, platform, arch)` → GitHub REST
    `GET /repos/abbasfarahani4846/EasyVpn/releases` (direct, then through the running proxy — same
    policy as subscriptions). Stable = newest non-prerelease `v*`; nightly = the `nightly` pre-release.
    The label is derived from asset names (`EasyVPN-<label>-<platform>…`), which is robust for the
    rolling nightly whose tag never changes.
  * Picks the right asset: `android-arm64-v8a.apk` / `android-x86_64.apk`, `windows-x64(-portable).zip`,
    `linux-x64.tar.gz` / `.deb`, `macos-arm64.zip`.
  * `Download(url, sha256)` streams to the cache dir, verifies against `SHA256SUMS.txt`
    (mandatory; a mismatch deletes the file), emits progress events.
* Apply (Dart/native):
  * Android: `REQUEST_INSTALL_PACKAGES` + FileProvider → system installer (same signing key required).
  * Windows/Linux zip/tar: write a tiny updater script that waits for the app PID, swaps files next to
    the executable (keeps `portable` + `data/`), relaunches. `.deb` → open with the system installer.
  * macOS: unzip to a temp dir and reveal/replace `easyvpn.app` (unsigned builds need user approval).
* UI: Settings ▸ Updates (channel, auto-check daily, "check now"); a non-blocking banner on Home.

## 2. Distinct look (Windscribe / NordVPN-class, not "stock Flutter Material")

* New **Home** (simple mode, default): full-bleed gradient header that changes hue with state
  (disconnected slate → connecting amber pulse → connected teal/green), large custom-painted power
  orb with animated rings, current location card (flag, city, protocol chip, signal bars), one-tap
  "Fastest" / "Favorites" chips, compact stats row. No app bar and no Material look.
* **Location picker**: a full-height sheet grouped by country, with flags, signal bars instead of
  raw ms, favorites star, search, and "Fastest" at the top. Windscribe-style. Works for 5,000+ nodes
  (lazy list, keyset paging already in the repository).
* Custom design tokens (radius, glass surfaces, gradients) in `lib/theme/brand.dart`; the existing theme
  engine stays for users who want to customize.
* "Advanced" drawer: Proxies (full table), Profiles, Routing, Chains, Logs, Settings.

## 3. Windscribe servers (your account + the free locations)

Windscribe's official clients are open source (GPL): `Windscribe/wsnet`, `Desktop-App`, `Android-App`.
Endpoints used (all against `https://api.windscribe.com`, `assets.windscribe.com` for lists):

| step | request | auth |
|---|---|---|
| login | `POST /Session` `username, password, 2fa_code, session_type_id` | none → `session_auth_hash` |
| server list | `GET assets…/serverlist/mob-v2/{0\|1}/{rev}` (`1` = pro) → `data[].groups[].{city,wg_pubkey,nodes[].{hostname,ip,ip2,ip3}}`, `pro` flags | none |
| WG key | `POST /WgConfigs/init` `wg_pubkey, device_id` → `PresharedKey, AllowedIPs` | bearer |
| WG connect | `POST /WgConfigs/connect` `wg_pubkey, hostname, device_id` → `Address, DNS` | bearer |
| OpenVPN/IKEv2 creds | `GET /ServerCredentials?type=openvpn\|ikev2` | bearer |

Plan:
* Core `pkg/providers/windscribe`: login (2FA, captcha surfaced as an error the UI can explain), fetch list,
  generate one Curve25519 key per device, `init` once, `connect` per location, and emit
  WireGuard `ProxyNode`s (endpoint = `ip3:443`, peer = group `wg_pubkey`, PSK, address, DNS). Free
  accounts get only `pro=0` groups.
* The account is stored as a profile of type `windscribe` (credentials/hash sealed with the existing
  AES-GCM store) and refreshes like a subscription. The UI lives in Profiles ▸ Add ▸ Windscribe account.
* Fallback that always works: Windscribe's website "Config Generator" WireGuard/OpenVPN files →
  existing `.conf`/`.ovpn` import.
* Caveats: this uses the user's own account with the same API as the official client; the API may
  change or require captcha. We never share or bundle credentials.

## 4. Chains: proxy-in-proxy, WARP, WARP-in-WARP, "exit via WARP"

* Engine `StartParams.Chain []ProxyNode`: hops dialed **before** the active node
  (app → hop1 → hop2 → active node → internet). sing-box `detour` links the outbounds; an Xray-sidecar
  node joins the chain by dialing through sing-box's loopback bypass inbound routed to the last hop.
* **WARP** (`pkg/warp`): register a free WARP device (Cloudflare client API, the same flow as wgcf),
  producing a WireGuard node (with `reserved` bytes). Optional WARP+ license key.
* Presets in the UI (Advanced ▸ Chain):
  * *Exit via WARP*: current node → WARP (the destination sees a Cloudflare IP, which helps with services
    that block Iranian or datacenter IPs, the "sanctions" use case).
  * *WARP in WARP*: WARP → WARP (two independent devices).
  * *Custom*: any nodes in any order (SSH → VLESS → WARP …).
* Route-level: rule outbound "chain" so only selected domains (e.g. sanctioned sites) use the chain.

## 5. Shortcuts everywhere

* Android: home-screen **widget** (status + toggle + current location), launcher **app shortcuts**
  (Connect/Disconnect, Fastest), Quick Settings tile (exists), notification actions (Disconnect exists;
  add "Switch to fastest"), "Always-on VPN" compatible start from the tile or widget without opening UI.
* Desktop: tray (exists) + connect/disconnect/fastest/exit-via-WARP items, a status-colored tray icon,
  global hotkey (Ctrl+Alt+V), `easyvpn --toggle|--connect|--disconnect` CLI that talks to the running
  instance (single instance), and an optional launch-at-login entry.

## 6. More connection types (all-in-one)

* Already: VLESS/VMess/Trojan/SS/SS2022/Hysteria2/TUIC/AnyTLS/WireGuard/OpenVPN/SSH/SOCKS/HTTP + Xray-only
  (XHTTP, ML-KEM, TCP-header).
* Add: IKEv2 (native OS on mobile/desktop; later), AmneziaWG via Xray/awg core (later), Tor (`tor` outbound;
  later), NaiveProxy, ShadowTLS (sing-box has these; parser/UI only).
* MLVPN-style multi-link (bonding several uplinks) is a research item. sing-box has no bonding; the
  practical equivalent is `urltest`/fallback groups plus per-app routing. True bonding needs a server
  component (MLVPN/`glorytun`), so it is out of scope for a client-only app.

## Order of work

1. [~] Core: chains (detour) + WARP registration + WARP node, with tests.
2. [~] Core: update checker/downloader with SHA256 verification, with tests (httptest).
3. [~] Core: Windscribe provider, with tests against a fake API (httptest). A live test needs the user's account.
4. [ ] UI: new Home + location picker + brand tokens; Advanced drawer.
5. [ ] UI: Updates settings/banner; Windscribe account dialog; Chain page.
6. [ ] Android: widget, app shortcuts, install-update flow; Desktop: hotkey, CLI toggle, single instance.
7. [ ] CI: dart-defines for build label/channel; APK signing key is stable across releases (needed for updates).
