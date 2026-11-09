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
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
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

INSTALLED="$HOME/Applications/$APP"
EXECUTABLE="$INSTALLED/Contents/MacOS/DeepWorkTimer"
running_pid() { pgrep -f "^$EXECUTABLE" | head -1 || true; }
OLD_PID=$(running_pid)

# Swap the new bundle in. A running copy carries on with the old code until it relaunches.
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED.new"
ditto "$OUT" "$INSTALLED.new"
rm -rf "$INSTALLED"
mv "$INSTALLED.new" "$INSTALLED"
# The app was called Deep Work Timer before; remove that copy so only one runs.
rm -rf "$HOME/Applications/Deep Work Timer.app"

if ! cmp -s "$HELPER_OUT/Contents/Resources/build-id" "$HOME/Applications/$HELPER/Contents/Resources/build-id"; then
  rm -rf "$HOME/Applications/$HELPER"
  ditto "$HELPER_OUT" "$HOME/Applications/$HELPER"
  echo "Installed ~/Applications/$HELPER (grant it Full Disk Access in System Settings if asked)"
fi

if [[ -z "$OLD_PID" ]]; then
  open "$INSTALLED"
  echo "Installed and launched $INSTALLED"
  exit 0
fi

# Hand the running session over to the new build: the app saves its timer,
# quits without undoing blocking or Focus, and reopens itself (see Relaunch.swift).
# A signal reaches exactly that process; a deepwork:// link could start a second copy.
kill -USR1 "$OLD_PID" 2>/dev/null || true
NEW_PID=""
for _ in $(seq 50); do
  if ! kill -0 "$OLD_PID" 2>/dev/null; then
    NEW_PID=$(running_pid)
    [[ -n "$NEW_PID" ]] && break
  fi
  sleep 0.2
done
if [[ -n "$NEW_PID" ]]; then
  echo "Updated $INSTALLED in place; a running session carries on"
  exit 0
fi

if ! kill -0 "$OLD_PID" 2>/dev/null; then
  # It quit but didn't reopen (a build from before the signal existed). The timer
  # is saved on every change, so opening it again carries the session on.
  open "$INSTALLED"
  echo "Updated $INSTALLED; reopened it and the session carries on"
  exit 0
fi

echo "The running app didn't respond; restarting it (a running session ends)"
kill "$OLD_PID" 2>/dev/null || true
sleep 1
open "$INSTALLED"
