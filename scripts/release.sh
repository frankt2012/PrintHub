#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0}"
DMG="$ROOT/dist/PrintHub-$VERSION.dmg"

xcodebuild \
    -project PrintHub.xcodeproj \
    -scheme PrintHub \
    -configuration Release \
    -derivedDataPath build-release \
    CODE_SIGNING_ALLOWED=NO \
    build

APP="$ROOT/build-release/Build/Products/Release/PrintHub.app"

# Ad-hoc signing is enough for a direct-download build. Notarization requires a
# Developer ID Application certificate and notarytool credentials.
codesign --force --sign - "$APP/Contents/MacOS/go2rtc"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$ROOT/dist/dmg"
mkdir -p "$ROOT/dist/dmg"
ditto "$APP" "$ROOT/dist/dmg/PrintHub.app"
ln -s /Applications "$ROOT/dist/dmg/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "PrintHub" \
    -srcfolder "$ROOT/dist/dmg" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

echo "DMG: $DMG"
shasum -a 256 "$DMG"
