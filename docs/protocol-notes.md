# Creality local protocol — field notes

Community-reverse-engineered notes for building Chamber. Everything here is
**firmware-dependent and unofficial**. Verify against the actual printers, record firmware
versions, and keep decoding tolerant.

Primary sources:

- `ha_creality_ws` engineering reference and source:
  https://github.com/3dg1luk43/ha_creality_ws
- `hass_creality_k1`:
  https://github.com/hurricaneb/hass_creality_k1
- go2rtc Creality WebRTC support:
  https://github.com/AlexxIT/go2rtc/issues/1600
- Printer Tools troubleshooting notes:
  https://printertools.app/blog/guides/troubleshoot-creality-k1-k2-local-monitoring

---

## 1. Transport

| Purpose | Endpoint | Notes |
|---|---|---|
| Status + control | `ws://<host>:9999` | Subprotocol `wsslicer`, JSON, no auth |
| MJPEG camera (K1 family) | `http://<host>:8080/?action=stream` | Snapshot: `?action=snapshot` |
| MJPEG camera (some firmware) | `http://<host>:4409/webcam/?action=stream` | K1 SE / K1C 2025 reports |
| WebRTC camera (K2 family) | `http://<host>:8000/call/webrtc_local` | Base64 JSON SDP exchange |
| Moonraker (K2, stock) | `http://<host>:7125` | Optional, useful for history/queue |
| Web UI | `http://<host>/` | Useful for manual verification |

The WebSocket is plain `ws://`, not TLS. There is no authentication. Treat the printer
LAN as a trusted network.

### Handshake

```
GET / HTTP/1.1
Host: <printer>:9999
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: ...
Sec-WebSocket-Version: 13
Sec-WebSocket-Protocol: wsslicer
```

If the subprotocol is missing, the printer may close the connection. Verify this first in
Phase 0.

---

## 2. Frame format

The printer pushes JSON objects. The stream is cumulative in practice: every frame carries
all keys seen so far on that connection, not just deltas. Chamber should still merge
defensively.

Special frames:

| Frame | Meaning | Response |
|---|---|---|
| `{"ModeCode":"heart_beat"}` | Liveness ping | Send the literal text `ok` |
| `ok` | Acknowledgement | Ignore |
| Any other JSON object | State update | Merge into snapshot |

Rules:

- Decode bytes as UTF-8 with replacement; ignore non-JSON text.
- Ignore arrays and scalars.
- Do not assume a key disappears when it is absent from a frame.
- Cap message size; a full G-code listing can be ~150 KB and printers with thousands of
  files can exceed 1 MB.

---

## 3. Polling

The printer does not necessarily stream everything on its own. Send these requests after
the first frame:

| Request | Cadence | Purpose |
|---|---|---|
| `{"method":"get","params":{"ReqPrinterPara":1}}` | Every 5 s | Main telemetry |
| `{"method":"get","params":{"reqPrintObjects":1}}` | Every 2 s | Print objects / progress |
| `{"method":"get","params":{"boxsInfo":1}}` | Every 300 s and on demand | CFS slot data |
| `{"method":"get","params":{"reqGcodeFile":1}}` | When `printFileName` changes | File metadata |

Liveness:

- No frame for 10 s → send `ReqPrinterPara` as a probe.
- No frame for 30 s → close and reconnect.
- Do not rely on WebSocket ping/pong; the printer's app-level heartbeat is what matters.

---

## 4. Commands

All commands use this envelope:

```json
{"method":"set","params":{ ... }}
```

| Action | Payload | Notes |
|---|---|---|
| Pause | `{"pause":1}` | |
| Resume | `{"pause":0}` | |
| Stop | `{"stop":1}` | Confirm in UI |
| Light on/off | `{"lightSw":1}` / `{"lightSw":0}` | |
| Light dimming (K2) | `{"gcodeCmd":"SET_PIN PIN=LED VALUE=0.5"}` | 0.0–1.0; model-dependent |
| Nozzle target | `{"nozzleTempControl":215}` | |
| Bed target | `{"bedTempControl":{"num":0,"val":60}}` | `num` is the bed index |
| Chamber target | `{"boxTempControl":40}` | K2 family |
| Fan | `{"gcodeCmd":"M106 P0 S255"}` | `P` is the fan channel, `S` 0–255 |
| Speed + flow | `{"setFeedratePct":100}` and `{"setFlowratePct":100}` | Usually one UI slider |
| Home | `{"autohome":"X Y"}` then `{"autohome":"Z"}` | Wait for `deviceState != 7` between |
| Start a file | `{"opGcodeFile":"printprt<...>.gcode"}` | **v1.1**; exact path form varies |
| CFS material | `{"modifyMaterial":{...}}` | **v1.1**; build payload from current slot |

### Upload and start (post-v1)

Observed in community tooling and OrcaSlicer discussions:

```http
POST http://<printer>/upload/<filename>.gcode
Content-Type: multipart/form-data
```

Then start with the printer's stored path, typically:

```json
{"method":"set","params":{"opGcodeFile":"printprt<...>.gcode"}}
```

Do not ship this until it has been tested on both printers, including filenames with
spaces/non-ASCII, and with the printer's file listing (`reqGcodeFile` /
`retGcodeFileInfo2`) to get the exact path.

---

## 5. Telemetry keys

These are the keys worth normalizing. Names are what the community integrations consume;
some models omit some keys.

| Key | Type | Meaning |
|---|---|---|
| `state` | int | 0/7/9 processing, 1 printing, 2 finished (K1C), 4 stopped, 5 paused |
| `printFileName` | string | Non-empty means a job exists; may be a full path |
| `printProgress` / `dProgress` | number | 0–100; prefer `printProgress`, fall back only when absent |
| `printJobTime` | seconds | Elapsed; going backwards means a new job |
| `printLeftTime` / `printTimeLeft` | seconds | Remaining |
| `layer` / `TotalLayer` | int | Current / total layers |
| `nozzleTemp` | °C | Actual |
| `bedTemp0` | °C | Actual |
| `boxTemp` / `targetBoxTemp` / `maxBoxTemp` | °C | Chamber actual/target/max |
| `maxNozzleTemp` / `maxBedTemp` | °C | Slider limits |
| `lightSw` | 0/1 | Light state |
| `fan` / fan speed keys | number | Model-dependent; inspect real frames |
| `printSpeed` / feedrate keys | number | Model-dependent |
| `cfsConnect` | 0/1 | CFS present |
| `boxsInfo` | object | CFS slots: material, color, remaining |
| `materialStatus` | 0/1 | 1 = "consumable not detected" on many models |
| `deviceState` | int | 7 = homing |
| `withSelfTest` | 1–99 | Self-test progress; outranks job state |
| `err.errcode` or `err` | int | Non-zero = error |
| `model` | string | Friendly model name |
| `modelVersion` | string | Board code, e.g. F008/F012/F021/F018 |
| `hostname` | string | Device name |
| `webrtcSupport` | 0/1 | 1 = use WebRTC camera |
| `retGcodeFileInfo2` | object | File listing; can be large |

### State derivation

Do not map `state` directly to UI text. Derive:

```
if withSelfTest in 1...99        -> selfTesting
else if err.errcode != 0         -> error
else if state == 1               -> printing
else if state == 5 or pause flag -> paused
else if state in {0,7,9} and file -> processing
else if state == 4               -> stopped
else if file and progress >= 100 -> complete
else                              -> idle
```

Cross-check with `printFileName`, `printProgress`, and `printJobTime`. A job transition
should reset per-job notification latches.

### Capability flags

- `hasWebRTC = webrtcSupport == 1` or model is K2 family.
- `hasChamberControl =` K2 family (K2/K2 Pro/K2 Plus).
- `hasChamberSensor =` K1/K1C/K1 Max/K2 family (not K1 SE / Ender V3).
- `hasLight =` not K1 SE / Ender V3.
- `hasCFS = cfsConnect == 1` or `boxsInfo` present.
- Fan channels and dimming are discovered from real frames, not assumed.

---

## 6. Cameras

### 6.1 K1 family — MJPEG

```
GET http://<host>:8080/?action=stream
```

Response is `multipart/x-mixed-replace` with JPEG parts. Parse:

- Find the boundary from `Content-Type`.
- Split on `--boundary`.
- For each part, find `\r\n\r\n`, then read `Content-Length` if present; otherwise scan
  for JPEG SOI `FF D8` and EOI `FF D9`.
- Feed complete JPEGs to the renderer.

Snapshot endpoint:

```
GET http://<host>:8080/?action=snapshot
```

Some firmware exposes `http://<host>:4409/webcam/?action=stream` (K1 SE / K1C 2025).
Probe both, remember which worked, and re-probe after a firmware update.

### 6.2 K2 family — WebRTC

Signalling:

```http
POST /call/webrtc_local HTTP/1.1
Host: <printer>:8000
Content-Type: plain/text
Origin: http://<printer>:8000
Referer: http://<printer>:8000/

<base64 of {"type":"offer","sdp":"..."}>
```

Response:

```
<base64 of {"type":"answer","sdp":"..."}>
```

Some firmware returns raw SDP instead of base64 JSON; accept both.

Critical implementation notes:

1. **CRLF only.** Join SDP lines with `\r\n`. Bare LF can wedge the K1C WebRTC server
   until a power cycle.
2. **No mDNS candidates.** The printer ignores `<uuid>.local` host candidates. Use raw
   IPv4 addresses, or resolve mDNS names before sending the offer.
3. **Timestamp pacing.** Creality's RTP timestamps advance roughly 20× faster than
   wall-clock. WebKit-based clients play slowly and drift. Use a native renderer that
   presents frames on arrival time, or re-stamp timestamps. This is the single most
   important camera detail for a Mac app.
4. **Video only.** Offer one video transceiver; no audio. Reduce the answer to the video
   m-line if the printer adds sections.
5. **One peer connection per printer.** Share the decoded frames across windows.
6. **Firmware regressions.** Some K2 Plus firmware broke port 8000. Detect a failed
   negotiation and show a specific message; do not loop forever.
7. **Probe before dialing.** A quick `GET /call/webrtc_local` (any HTTP response) tells
   you the service is alive before creating a peer connection.

### 6.3 Fallback: go2rtc

If native WebRTC fails the Phase 0 gate, bundle a universal `go2rtc` helper and use:

```yaml
streams:
  k2plus: webrtc:http://<host>:8000/call/webrtc_local#format=creality
```

go2rtc 1.9.10+ supports the Creality signalling format. It can also re-stamp timestamps
via an ffmpeg template if needed. Costs: helper process, larger app, sandbox/notarization
work, App Store friction. Treat it as a deliberate fallback, not the default.

---

## 7. Discovery

mDNS/Bonjour patterns used by the community integration:

```
_http._tcp.local.        name contains "creality", "k1", or "k2"
_workstation._tcp.local. name contains "creality", "k1", or "k2"
```

Plan:

1. Browse Bonjour, resolve hostnames to IPv4.
2. Probe `:9999` with a WebSocket handshake to confirm it is a printer.
3. Fall back to manual IP/hostname.
4. Optional subnet scan: TCP connect to `:9999` on the local /24, with a short timeout and
   clear progress UI.
5. Persist a stable ID from MAC/hostname; update the IP silently when it changes.

`Network.framework` (`NWBrowser`, `NWConnection`) is the native path. Include
`NSBonjourServices` and `NSLocalNetworkUsageDescription` in `Info.plist`.

---

## 8. Recording fixtures

For every test session, capture:

```json
{
  "printer": "K2 Plus",
  "firmware": "1.1.5.x",
  "modelVersion": "F008",
  "capturedAt": "2026-11-12T18:00:00Z",
  "scenario": "start-print",
  "frames": [ { "t": 0.0, "json": { ... } } ],
  "camera": { "type": "webrtc", "firstFrameMs": 900, "resolution": "1920x1080" }
}
```

Use the same fixtures in unit tests and to replay regressions. Keep one "happy path" and
one "nasty path" per scenario: malformed frames, missing keys, state flapping, reconnect,
runout, CFS removal, firmware with no camera.

---

## 9. Open protocol questions

- Exact `opGcodeFile` path format for K1 vs K2.
- Upload endpoint behavior on K2 (chunked? multipart field names? auth?).
- Which fan channels exist on K1 Max vs K2 Plus.
- CFS slot schema differences across firmware.
- Whether multiple clients can subscribe to `:9999` simultaneously, and any limit.
- Whether Moonraker on K2 exposes anything the WS API does not (history, queue, job
  metadata).
- Behavior of `:8000` across recent K2 firmware releases.

Answer these with captures, not assumptions.
