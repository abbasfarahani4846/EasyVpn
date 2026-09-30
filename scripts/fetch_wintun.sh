#!/usr/bin/env bash
# Downloads wintun.dll (amd64) from wintun.net into third_party/wintun/. Wintun is
# distributed under its own license (prebuilt binary, redistribution permitted).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p third_party/wintun
VER="${WINTUN_VERSION:-0.14.1}"
curl -fsSL -o /tmp/wintun.zip "https://www.wintun.net/builds/wintun-${VER}.zip"
unzip -o -j /tmp/wintun.zip "wintun/bin/amd64/wintun.dll" -d third_party/wintun/
echo "wintun.dll ready in third_party/wintun/"
test -f third_party/wintun/wintun.dll || { echo "wintun.dll missing after extraction" >&2; exit 1; }
