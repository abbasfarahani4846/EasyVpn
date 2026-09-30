# EasyVPN

Cross-platform proxy/VPN client: Flutter UI + Go core (sing-box, with an in-process Xray-core sidecar).
Android, Windows, macOS, Linux (iOS not yet).

* Protocols: VLESS (Reality/Vision/XHTTP/ML-KEM), VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard, OpenVPN,
  AnyTLS, SSH, SOCKS/HTTP.
* Connection modes: Tunnel (TUN), System proxy, Both, Local port.
* Country-aware routing with rule lists downloaded by the core (Iran, China, Russia packs; offline baseline bundled).
* Import: links, subscriptions (base64/Clash/sing-box/Xray JSON), `.ovpn`, `wg-quick`, QR, deep links.
  Export: links, Clash YAML, sing-box JSON. Encrypted backups (AES-256-GCM + Argon2id).
* Scales to 10k+ nodes (SQLite FTS5, keyset paging, chunked latency tests).

See `docs/MASTER_PROMPT.md` (architecture/spec) and `docs/BUILD.md` (build). License: GPL-3.0.
