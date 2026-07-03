#!/bin/bash
# Build MeetingCaptions, sign with a STABLE identity (so the system-audio TCC
# grant survives rebuilds — ad-hoc signing changes the cdhash every build and
# silently voids the grant, giving silent/zero audio), install to a fixed path,
# and launch.
set -e
cd "$(dirname "$0")"

# Stable signing identity (has a Team ID → TCC pins to identifier+anchor, not cdhash).
SIGN_ID="Apple Development: Jiahao Zhang (NWJTN3DP9L)"
BUNDLE_ID="com.plus.meetingcaptions"
ENTITLEMENTS="$(pwd)/Sources/MeetingCaptions.entitlements"

echo "▶︎ Building…"
xcodebuild -project MeetingCaptions.xcodeproj \
  -scheme MeetingCaptions -configuration Debug \
  -derivedDataPath .build build \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP=".build/Build/Products/Debug/MeetingCaptions.app"
if [ ! -d "$APP" ]; then
  echo "✗ Build failed — app not found."; exit 1
fi

echo "▶︎ Re-signing with stable identity: $SIGN_ID"
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier "$BUNDLE_ID" \
  --sign "$SIGN_ID" "$APP"

# Verify the designated requirement is now cert-anchored (NOT a bare cdhash).
echo "▶︎ Designated requirement:"
codesign -d -r- "$APP" 2>&1 | grep -E "designated" || true

echo "▶︎ Installing to ~/Desktop/MeetingCaptions.app"
pkill -f "Desktop/MeetingCaptions.app" 2>/dev/null || true
sleep 1
rm -rf ~/Desktop/MeetingCaptions.app
cp -R "$APP" ~/Desktop/MeetingCaptions.app

# Make the local cloud credentials available at a stable runtime path.
if [ -f "$(pwd)/config.local.json" ]; then
  mkdir -p "$HOME/Library/Application Support/MeetingCaptions"
  cp "$(pwd)/config.local.json" "$HOME/Library/Application Support/MeetingCaptions/config.local.json"
fi

echo "▶︎ Launching…"
open ~/Desktop/MeetingCaptions.app
echo "✅ Running. Look for the 💬 icon in the menu bar."
