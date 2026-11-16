#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Tools/go2rtc"

if [ -x "$DEST/go2rtc" ]; then
    echo "go2rtc already present at $DEST/go2rtc"
    exit 0
fi

mkdir -p "$DEST"
cd "$DEST"

VERSION="v1.9.15"
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    ASSET="go2rtc_mac_arm64.zip"
else
    ASSET="go2rtc_mac_amd64.zip"
fi

echo "Downloading go2rtc $VERSION (macOS $ARCH)"
curl -L --fail --progress-bar \
    "https://github.com/AlexxIT/go2rtc/releases/download/$VERSION/$ASSET" \
    -o go2rtc.zip

unzip -o -q go2rtc.zip
chmod +x go2rtc
rm -f go2rtc.zip
echo "Installed $DEST/go2rtc"
