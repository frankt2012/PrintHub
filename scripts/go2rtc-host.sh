#!/bin/zsh
set -u

DIR="/Volumes/HOME 1TB EXT/Documents/Chamber/Tools/go2rtc"
OUT="/Volumes/HOME 1TB EXT/Documents/Chamber/captures/go2rtc-host.log"
DONE="/Volumes/HOME 1TB EXT/Documents/Chamber/captures/go2rtc-host.done"
rm -f "$DONE"
: > "$OUT"

cd "$DIR" || { echo "missing dir" >> "$OUT"; touch "$DONE"; exit 1; }

{
  echo "=== go2rtc host test ==="
  date
  echo ""
  ./go2rtc -config go2rtc.yaml &
  PID=$!
  echo "pid: $PID"
  sleep 8
  echo ""
  echo "=== streams ==="
  curl -sS -m 5 http://127.0.0.1:1984/api/streams
  echo ""
  echo ""
  echo "=== snapshot ==="
  curl -sS -m 20 -o "$DIR/snapshot.jpg" -w "http=%{http_code} bytes=%{size_download} type=%{content_type}\n" "http://127.0.0.1:1984/api/frame.jpeg?src=k2"
  echo ""
  echo "=== stream info ==="
  curl -sS -m 10 "http://127.0.0.1:1984/api/streams?src=k2"
  echo ""
  echo ""
  kill "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  echo "=== done ==="
} >> "$OUT" 2>&1

touch "$DONE"
