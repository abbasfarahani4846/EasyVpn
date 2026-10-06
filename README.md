# EasyVpn

A simple, one-tap VPN client for **Windows, Android and Linux**, built on the
[mihomo](https://github.com/MetaCubeX/mihomo) proxy core and made for networks where
servers get blocked often. [فارسی](README_fa.md)

## Features

- **Paste anything.** Share links (`vless://`, `vmess://`, `trojan://`, `ss://`, `hy2://`,
  `tuic://`, `anytls://`), a subscription link, a Clash/mihomo YAML or a proxy JSON, and the
  servers are added. XHTTP links keep all their options (padding, XMUX, download settings).
- **Automatic port repair.** A server that does not answer on its own port is tested on a
  fallback port and fixed; one that answers on none is reported instead of left dead.
- **Country bypass.** Traffic to a country's own IP ranges and domains (Iran and many more)
  goes direct, with lists downloaded once and kept on the device.
- **One-tap connect** with a dashboard that shows the real outbound IP and the route in use.
- **Entry-server chain**, **Psiphon**, **Windscribe** and **WARP** helpers built in.
- **Updates inside the app.** The home page tells you when a new build exists and installs it.

## Download

Get the newest build from the [Releases](../../releases) page:

| Platform | File |
|---|---|
| Windows | `EasyVpn-windows-x64.zip` (unzip and run `FlClash.exe`) |
| Android | the `.apk` that matches your phone (`arm64-v8a` for most) |
| Linux | `EasyVpn-linux-x64.tar.gz` |

## Build

Needs Flutter 3.47.x, Go, Rust and the submodule:

```bash
git submodule update --init --recursive
flutter pub get
flutter build windows --release     # or: linux, or: dart setup.dart android
```

Pushes to this repository build all three platforms in GitHub Actions
(`.github/workflows/easy-build.yaml`); a `v*` tag turns the build into a release.

## License

GPL-3.0, see [LICENSE](LICENSE). Credits and third-party notices are in
[NOTICE-easy.md](NOTICE-easy.md).
