#!/bin/bash
# Build Deep End.app, install it to ~/Applications, and relaunch it.
#   ./build.sh            build + install + launch
#   ./build.sh --no-install   just build into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="Deep End.app"
OUT="build/$APP"

swift build -c release

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp .build/release/DeepWorkTimer "$OUT/Contents/MacOS/DeepWorkTimer"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT" >/dev/null

echo "Built $OUT"

# The Focus helper is its own app so its Full Disk Access grant survives
# rebuilds of the main app. Only replace the installed copy when it changed.
HELPER="Deep Work Focus.app"
HELPER_OUT="build/$HELPER"
rm -rf "$HELPER_OUT"
mkdir -p "$HELPER_OUT/Contents/MacOS"
cp .build/release/DeepWorkFocus "$HELPER_OUT/Contents/MacOS/DeepWorkFocus"
cp Resources/FocusHelper-Info.plist "$HELPER_OUT/Contents/Info.plist"
# Fingerprint of the helper's source: its binary isn't byte-for-byte repeatable
# across builds, and reinstalling it would cost its Full Disk Access grant.
mkdir -p "$HELPER_OUT/Contents/Resources"
cat Sources/DeepWorkFocus/*.swift Resources/FocusHelper-Info.plist | shasum -a 256 | cut -d' ' -f1 > "$HELPER_OUT/Contents/Resources/build-id"
codesign --force --sign - "$HELPER_OUT" >/dev/null

if [[ "${1:-}" == "--no-install" ]]; then exit 0; fi

pkill -x DeepWorkTimer 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/$APP"
# The app was called Deep Work Timer before; remove that copy so only one runs.
rm -rf "$HOME/Applications/Deep Work Timer.app"
ditto "$OUT" "$HOME/Applications/$APP"
if ! cmp -s "$HELPER_OUT/Contents/Resources/build-id" "$HOME/Applications/$HELPER/Contents/Resources/build-id"; then
  rm -rf "$HOME/Applications/$HELPER"
  ditto "$HELPER_OUT" "$HOME/Applications/$HELPER"
  echo "Installed ~/Applications/$HELPER (grant it Full Disk Access in System Settings if asked)"
fi
open "$HOME/Applications/$APP"
echo "Installed and launched ~/Applications/$APP"
