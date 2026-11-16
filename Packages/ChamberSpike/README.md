# ChamberSpike

Phase 0 harness for the Creality protocol and cameras. This is deliberately a
small SwiftPM package: it will become the `CrealityKit` and `CameraKit` modules
used by the app.

## Requirements

- macOS 14 or later
- Xcode 16 / Swift 6 toolchain
- A printer on the same LAN, or the local mock printer

## Build and run

```sh
cd Packages/ChamberSpike
./Tools/fetch-webrtc.sh   # ~100 MB binary framework, not committed
swift build
swift run chamber-spike probe 192.168.1.50
```

### Commands

```sh
# Find printers advertising on Bonjour.
swift run chamber-spike discover

# Check the WebSocket handshake, ports, model, and camera type.
swift run chamber-spike probe 192.168.1.50

# Watch telemetry for 60 seconds, printing changes.
swift run chamber-spike watch 192.168.1.50 --seconds 60

# Record every raw frame for replay and regression tests.
swift run chamber-spike watch 192.168.1.50 --seconds 300 --record captures/k2-idle.jsonl

# Save a K1-family MJPEG snapshot. Falls back to :4409 automatically.
swift run chamber-spike snapshot 192.168.1.50 --out captures/k1.jpg

# Measure MJPEG frame rate and save a frame every 15th frame.
swift run chamber-spike mjpeg 192.168.1.50 --seconds 30 --save captures/k1-frames

# Negotiate the K2 WebRTC camera and save the first decoded frame.
swift run chamber-spike webrtc 192.168.1.50 --seconds 30

# Send a safe control command. Stop requires --yes.
swift run chamber-spike control 192.168.1.50 pause
swift run chamber-spike control 192.168.1.50 light-off
swift run chamber-spike control 192.168.1.50 nozzle 215
```

Options:

| Option | Used by | Meaning |
|---|---|---|
| `--seconds <n>` | watch, mjpeg, webrtc | Duration |
| `--record <path>` | watch | Raw JSONL capture |
| `--verbose` | watch | Heartbeats and unparsed frames |
| `--ws-port <n>` | probe, watch | Default 9999 |
| `--camera-port <n>` | probe | Default 8080 |
| `--webrtc-port <n>` | probe, webrtc | Default 8000 |
| `--port <n>` | snapshot, mjpeg | Default 8080 |
| `--path <path>` | snapshot, mjpeg | Override the camera path |
| `--save <dir>` | mjpeg | Save every 15th JPEG |
| `--out <path>` | snapshot, webrtc | Output file |
| `--yes` | control | Required for `stop` |

## Mock printer

The mock exercises the handshake, heartbeat, polling, control commands, MJPEG,
and a fake WebRTC endpoint:

```sh
cd Tools/mock-printer
npm install
npm start
```

It listens on:

- `ws://127.0.0.1:9999` — printer API, subprotocol `wsslicer`
- `http://127.0.0.1:18080` — MJPEG snapshot/stream
- `http://127.0.0.1:18000` — fake WebRTC signalling

The camera port is 18080 rather than 8080 because WirePod uses 8080 on this Mac.
Test with:

```sh
swift run chamber-spike probe 127.0.0.1 --camera-port 18080 --webrtc-port 18000
swift run chamber-spike watch 127.0.0.1 --seconds 8
swift run chamber-spike mjpeg 127.0.0.1 --port 18080 --seconds 4
swift run chamber-spike snapshot 127.0.0.1 --port 18080
```

## Status

| Area | State |
|---|---|
| WebSocket handshake (`wsslicer`) | Verified against mock |
| Heartbeat (`heart_beat` / `ok`) | Verified against mock |
| Polling (`ReqPrinterPara`, `reqPrintObjects`, `boxsInfo`) | Verified against mock |
| Telemetry merge + state derivation | Unit tested |
| Control commands (pause/resume/light/temps/fan/speed) | Verified against mock |
| MJPEG streaming | Verified against mock; 10 fps, no parser stalls |
| WebRTC signalling | Exchange verified against mock (offer posted, HTTP 501 expected); awaiting real K2 Plus |
| WebRTC renderer | Frame counter + first-frame JPEG; custom timestamp pacing still to test |
| Discovery | `dns-sd` browse/resolve verified; app will use `NWBrowser` with entitlements |

## Known decisions

- `URLSessionWebSocketTask` is used instead of `Network.framework`'s WebSocket:
  the latter failed against the mock with a connection abort, while URLSession
  negotiated `wsslicer` correctly.
- MJPEG parsing scans for JPEG SOI/EOI markers rather than trusting multipart
  `Content-Length`; this survives chunk splits and printer header variations.
- The WebRTC renderer records the RTP-timestamp-to-wall-clock ratio. On real K2
  hardware this should confirm the reported ~20× fast timestamps before the app
  builds its production renderer.
