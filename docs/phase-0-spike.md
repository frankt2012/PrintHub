# Phase 0 — protocol and camera spike

**Timebox: 5 working days.** The goal is not a polished app. It is to prove the two
riskiest assumptions and capture enough protocol data to build the real thing.

> **Status (15 Nov 2026):** the harness exists at
> [`Packages/PrintHubSpike`](../Packages/PrintHubSpike/README.md). WebSocket
> handshake/heartbeat/polling, control commands, MJPEG streaming, and the WebRTC
> signalling exchange are verified against a local mock. Real-hardware
> verification is waiting on the printers being reachable on the LAN.

1. A native macOS process can hold a reliable `ws://<printer>:9999` session with
   subprotocol `wsslicer`.
2. A native camera pipeline can display the K2 Plus WebRTC stream and the K1 Max MJPEG
   stream for 30 minutes without falling apart.

If either fails, we change the architecture now, not after the UI is built.

---

## Deliverables

- A small SwiftPM executable (`Spike`) with subcommands:
  - `probe <host>` — check ports 9999, 8000, 8080, 4409, 7125.
  - `watch <host>` — connect, log every frame (timestamped), print a live state summary.
  - `camera <host>` — open a window and display MJPEG or WebRTC.
  - `record <host> --scenario <name>` — write a fixture bundle.
- Captured fixtures for each printer under `.captures/` (git-ignored):
  - idle, start print, pause, resume, complete, error, runout (if reproducible).
- A one-page verdict: native WebRTC vs go2rtc, with numbers.
- Firmware/model notes filled into [hardware-test-log.md](hardware-test-log.md).

---

## Day 1 — transport and telemetry

### WebSocket handshake

Try `URLSessionWebSocketTask` first:

```swift
var request = URLRequest(url: URL(string: "ws://\(host):9999")!)
request.setValue("wsslicer", forHTTPHeaderField: "Sec-WebSocket-Protocol")

let task = URLSession.shared.webSocketTask(with: request)
task.resume()
```

Verify:

- The server returns `101 Switching Protocols` with `Sec-WebSocket-Protocol: wsslicer`.
- The first frame arrives without sending anything (or after `ReqPrinterPara`).
- The heartbeat frame is `{"ModeCode":"heart_beat"}` and the server accepts a literal
  `ok` text frame.

If the subprotocol is dropped or the handshake fails, use `Network.framework`:

```swift
let wsOptions = NWProtocolWebSocket.Options()
wsOptions.setSubprotocols(["wsslicer"])

let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

let connection = NWConnection(host: NWEndpoint.Host(host),
                              port: 9999,
                              using: parameters)
```

`NWProtocolWebSocket` gives direct control over the headers and is the reliable fallback.
Record which one works; this becomes the production transport.

### Frame capture

Log:

- Monotonic receive time.
- Raw JSON (pretty-printed for readability, raw for replay).
- Whether the frame was a heartbeat.
- Gaps > 2 s.

Send the polls from the protocol notes and confirm replies. Run for at least 10 minutes
while the printer is idle, then during a print.

### State reducer sketch

Do not build the final model yet. Build a throwaway reducer that prints:

```
state=1 progress=68.4 file=Benchy.gcode left=4321s nozzle=215/215 bed=60/60 box=38/40
```

This exposes type quirks (`"68.4"` vs `68.4`, empty strings, missing keys) early.

---

## Day 2 — MJPEG (K1 Max)

- Connect to `http://<k1>:8080/?action=stream` with `URLSession.bytes`.
- Parse the multipart boundary and extract JPEGs.
- Display with `NSImage`/`CALayer` first; optimize later.
- Measure first-frame time, frame rate, latency, CPU, memory over 30 minutes.
- Test `?action=snapshot`.
- If 8080 is closed, probe `http://<k1>:4409/webcam/?action=stream`.

Success: 30 minutes, no parser stalls, <10% CPU on an M-series Mac, <1 s latency.

---

## Days 3–4 — WebRTC (K2 Plus)

### Signalling

1. `POST http://<k2>:8000/call/webrtc_local` with `Content-Type: plain/text`.
2. Body is base64 of `{"type":"offer","sdp":"..."}`.
3. Response is base64 of `{"type":"answer","sdp":"..."}` (also accept raw SDP).
4. Join SDP lines with `\r\n` only.
5. Do not include mDNS host candidates; use raw IPv4.

### Framework candidates

| Framework | Why | Check |
|---|---|---|
| `stasel/WebRTC` xcframework | Prebuilt Google WebRTC, SwiftPM, macOS support | Binary size, arm64+x86_64, API version |
| LiveKit `WebRTC` xcframework | Actively maintained build | Same, plus license/notice |
| Bundled go2rtc | Proven Creality support | Process management, size, sandbox |

Start with the prebuilt Google WebRTC framework. Create a peer connection with no STUN
(LAN only), add one video transceiver, create an offer, set local description, POST it,
set the remote answer, and render the remote video track.

### Renderer

Try in this order:

1. **`RTCMTLVideoView`** — fastest to stand up. Measure drift and lag over 10 minutes.
2. **Custom `RTCVideoRenderer` → `AVSampleBufferDisplayLayer`** — present frames using
   arrival time (`CACurrentMediaTime()`), not `RTCVideoFrame.timeStampNs`. WebRTC delivers
   I420; convert to NV12/BGRA for the display layer (vImage or VideoToolbox). This is the
   likely production path because Creality's RTP timestamps run ~20× fast.
3. **go2rtc** — if 1 and 2 fail or are unstable, run the helper and consume its output.

### Measurements

| Metric | Target | Notes |
|---|---|---|
| First frame | < 2 s | from peer connection start |
| End-to-end latency | < 1.5 s | compare a stopwatch in frame |
| Frame rate | ≥ 15 fps | 1080p |
| 30-minute drift | ~0 | audio/video sync not relevant, but playback speed is |
| CPU | < 10% | M1/M2, one stream |
| Memory | < 200 MB | one stream |
| Reconnect after printer reboot | < 15 s | |
| Sleep/wake recovery | automatic | |

Use a stopwatch or phone timer in view to measure latency, not a feeling.

---

## Day 5 — decision and write-up

### Scorecard

Score each option 1–5.

| Criterion | Weight | Native WebRTC | go2rtc helper |
|---|---|---|---|
| K2 stream reliability | 30% | | |
| Latency / smoothness | 20% | | |
| Integration effort | 15% | | |
| App size / packaging | 10% | | |
| Sandbox / notarization / App Store | 10% | | |
| Maintenance risk | 15% | | |

**Decision rule:** if native WebRTC is stable for 30 minutes and latency is within 0.5 s
of go2rtc, choose native. If it drifts, drops, or needs more than ~5 days of extra work,
choose go2rtc and move on.

### Write-up

- Which transport worked (`URLSessionWebSocketTask` vs `Network.framework`).
- Exact firmware versions and camera endpoints.
- WebRTC offer/answer samples (redacted).
- Latency/CPU/memory numbers.
- Any firmware bugs and workarounds.
- Final camera decision and the reason.
- Updated risks in `PLAN.md` if anything changed.

---

## Protocol questions to answer with captures

- Does `state` behave consistently across K1 Max and K2 Plus?
- What does a completed job look like on each (state 2 vs idle + 100%)?
- Which fan keys exist, and what are the channel numbers?
- What does `boxsInfo` look like with 4 slots, one empty, and no CFS?
- Does `materialStatus` latch after a runout?
- How often does the printer push frames without polling?
- Can two clients hold `:9999` at once? Three?
- Does `:8000` survive a 30-minute stream and a printer reboot?
- Does the K1 Max camera drop frames during heating or high motion?

---

## Guardrails

- Do not leave a stream running unattended for hours in the spike; use a timer.
- Do not test destructive commands (stop, firmware) on a print you care about.
- Keep the printers on a trusted LAN; do not expose ports to the internet.
- Record firmware versions before and after every session.
- If a command wedges the printer, power-cycle it and note the sequence.
