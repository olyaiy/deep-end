#!/bin/bash
# Build Deep Work Timer.app, install it to ~/Applications, and relaunch it.
#   ./build.sh            build + install + launch
#   ./build.sh --no-install   just build into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="Deep Work Timer.app"
OUT="build/$APP"

swift build -c release

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp .build/release/DeepWorkTimer "$OUT/Contents/MacOS/DeepWorkTimer"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT" >/dev/null

echo "Built $OUT"

if [[ "${1:-}" == "--no-install" ]]; then exit 0; fi

pkill -x DeepWorkTimer 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/$APP"
ditto "$OUT" "$HOME/Applications/$APP"
open "$HOME/Applications/$APP"
echo "Installed and launched ~/Applications/$APP"
