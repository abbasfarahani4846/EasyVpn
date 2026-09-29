#!/usr/bin/env bash
# Builds the macOS app, bundles the Go core and (optionally) signs it.
# Usage: scripts/package_macos.sh [--sign "Developer ID Application: NAME (TEAMID)"]
set -euo pipefail
cd "$(dirname "$0")/.."
make -C core darwin-proc
flutter build macos --release
APP="build/macos/Build/Products/Release/easyvpn.app"
cp bin/easycoreproc-darwin-arm64 "$APP/Contents/MacOS/easycoreproc"
chmod +x "$APP/Contents/MacOS/easycoreproc"
if [[ "${1:-}" == "--sign" ]]; then
  codesign --force --options runtime --entitlements macos/Runner/Release.entitlements \
    --sign "$2" "$APP/Contents/MacOS/easycoreproc"
  codesign --force --deep --options runtime --entitlements macos/Runner/Release.entitlements \
    --sign "$2" "$APP"
fi
echo "Built $APP"
