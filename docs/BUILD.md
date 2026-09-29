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
