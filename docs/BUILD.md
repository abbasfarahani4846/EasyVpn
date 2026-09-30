# Building EasyVPN

Requirements: Go 1.26+, Flutter 3.47+, a C toolchain (only for the c-shared library), platform SDKs.

## 1. Go core
```
make -C core test            # vet + all tests with the mandatory build tags
make -C core linux-proc      # ../bin/easycoreproc-linux-amd64   (also windows-proc, darwin-proc)
make -C core lib-linux       # ../bin/libeasycore.so             (FFI library; needs gcc)
make -C core lib-android NDK_BIN=<ndk>/toolchains/llvm/prebuilt/<host>/bin API=24
```
`TAGS` in `core/Makefile` is mandatory: without it sing-box drops uTLS/QUIC/WireGuard/OpenVPN at runtime.

## 2. App
```
flutter pub get
flutter analyze && flutter test        # integration tests need bin/ from step 1
flutter build linux|windows|macos|apk --release
```
* **Linux**: `sudo apt install libgtk-3-dev libsecret-1-dev libayatana-appindicator3-dev`. TUN mode needs
  `sudo setcap cap_net_admin,cap_net_bind_service+ep <bundle>/easycoreproc` or running the app as root.
* **Windows**: `scripts/fetch_wintun.sh` downloads `wintun.dll`; TUN needs "Run as administrator" (the app offers a relaunch).
* **macOS**: `scripts/package_macos.sh [--sign "Developer ID Application: …"]` bundles and signs the core.
* **Android**: the core is loaded as `jniLibs/<abi>/libeasycore.so`; TUN uses `VpnService` (fd handed to the core).
  Release signing: create `android/key.properties`.
* **iOS**: not implemented (needs a NetworkExtension PacketTunnel target).

## Runtime layout
Desktop: the app spawns `easycoreproc` (loopback TCP + per-launch token). Android: FFI into `libeasycore.so`.

## Releases (GitHub Actions)
`.github/workflows/release.yml` builds Linux (tar.gz + .deb), Windows (zip), macOS (zip), Android (arm64 + x86_64 APKs) and the raw Go cores,
then publishes them with `SHA256SUMS.txt` as a GitHub Release.

* **Stable**: `git tag v1.0.0 && git push origin v1.0.0` (version must be `x.y.z`).
* **Nightly**: every push to `main` replaces the pre-release tagged `nightly`.
* **Manual**: Actions → Release → Run workflow (optionally enter a version).

Optional secrets (without them builds are unsigned / debug-signed):
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`;
`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`.
