#!/bin/sh
set -euo pipefail

# Downloads the WebRTC binary used by the Phase 0 spike.
# The xcframework is ~100 MB and is intentionally not committed.

VERSION="${WEBRTC_VERSION:-157.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/WebRTC.xcframework"
ZIP="/tmp/WebRTC-M${VERSION}.xcframework.zip"
URL="https://github.com/stasel/WebRTC/releases/download/${VERSION}/WebRTC-M${VERSION}.xcframework.zip"

if [ -d "$DEST" ]; then
    echo "WebRTC already present at $DEST"
    exit 0
fi

mkdir -p "$ROOT/Vendor"
echo "Downloading $URL"
curl -L --fail --progress-bar "$URL" -o "$ZIP"
unzip -q "$ZIP" -d "$ROOT/Vendor"
echo "Installed $DEST"
