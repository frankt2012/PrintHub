#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x "$ROOT/Tools/go2rtc/go2rtc" ]; then
    "$ROOT/Tools/fetch-go2rtc.sh"
fi

xcodegen generate

xcodebuild \
    -project Chamber.xcodeproj \
    -scheme Chamber \
    -configuration Debug \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO \
    build

APP="$ROOT/build/Build/Products/Debug/Chamber.app"
codesign --force --deep --sign - "$APP"

echo "Built $APP"

if [ "${1:-}" = "--run" ]; then
    open -n "$APP"
fi
