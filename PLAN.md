# Chamber

> **Implementation status (16 Nov 2026):** Phase 0 is complete and the first native
> app slice is running. The K2 uses a bundled go2rtc helper plus a WKWebView WebRTC
> surface because native WebRTC stalls at the printer's DTLS handshake. See
> `docs/phase-0-results.md` and `docs/decisions/0002-k2-camera-fallback.md`. The app
> now has multi-printer entries, a menu bar extra, notifications, temperature setters,
> and individual/all-axis homing. K1 MJPEG, discovery, and a native WHEP client remain.
>
> The sections below are the original plan and are kept for context.

**A native macOS control room for Creality 3D printers.**

Working title · Planning document v0.1 · 12 November 2026

---

## 1. One-page summary

Chamber is a native Mac app for watching and controlling Creality printers on the local
network. It is the Mac equivalent of K2 Companion on Android: live camera, print status,
temperatures, progress, pause/resume/stop, light and fan control, and useful notifications —
without a Creality Cloud account.

The first two supported machines are the ones already on the desk:

- **Creality K2 Plus** — WebSocket control API, WebRTC camera, CFS, chamber heat, light.
- **Creality K1 Max** — WebSocket control API, MJPEG camera, chamber sensor, light.

The same protocol covers most current Creality OS / Klipper-based printers (K1, K1C,
K1 SE, K2, K2 Pro, Ender-3 V3 family, Hi), so the architecture is model-driven rather
than hard-coded to two printers. Older Marlin/DWIN Ender printers are a separate problem
and are explicitly out of scope.

**Product shape:** a proper Mac app, not a phone app stretched to 1200 px. Sidebar of
printers, camera as the hero, inspector for controls, menu bar extra for glanceable
status, notifications with snapshots, multiple windows, keyboard shortcuts.

**Technical bet:** one local WebSocket protocol (`ws://<printer>:9999`, subprotocol
`wsslicer`) for telemetry and control, MJPEG for K1-family cameras, WebRTC for K2-family
cameras. Camera is the highest-risk area, so Phase 0 is a camera spike with a clear
go/no-go decision before the UI is built.

**Delivery estimate:** 7–9 weeks full-time, or roughly 3–4 months of evenings and
weekends, including a public beta. v1 is monitor + safe controls; starting new prints and
CFS material changes come after v1.

---

## 2. Why this is worth building

### The gap

- Creality Cloud is account-based, cloud-dependent, and its camera experience is
  inconsistent across app versions and firmware.
- K2 Companion proves people want a direct, no-account monitor/control app, but it is
  Android-only.
- Existing Mac options (Printer Tools, OctoEverywhere, browser tabs into Fluidd/Mainsail)
  are either multi-brand dashboards, cloud relays, or web UIs. None feels like a
  first-class Mac app built around a Creality printer.
- PrintClock already owns the "what time will this finish?" job. Chamber can own
  "what is my printer doing right now?" and hand the finish time to PrintClock.

### What "native Mac" means here

Not just SwiftUI. It means:

- A real window with sidebar, toolbar, and inspector.
- A menu bar extra that is useful at a glance and cheap when hidden.
- Multiple windows, full-screen camera, picture-in-picture-style floating camera.
- Keyboard shortcuts, VoiceOver, Reduce Motion, system appearance, Stage Manager.
- Drag-and-drop, Quick Look for snapshots, ShareLink, notifications with actions.
- No embedded web view pretending to be an app.

---

## 3. Product definition

> **Chamber watches your printers so you don't have to keep opening a browser tab.**

### Jobs to be done

1. "Is it still printing, and does it look okay?" → camera + status in under two seconds.
2. "How long left, and what temperature is it at?" → glanceable telemetry.
3. "Something looks wrong." → pause or stop immediately, with confirmation.
4. "Tell me when it finishes or fails." → notification with snapshot, even when the app
   is in the background.
5. "I have two printers." → one window, both printers, no tab juggling.

### Positioning

- **Local-first.** No account. No cloud dependency. Works with the internet down.
- **Camera-first.** The video is the interface, not a thumbnail in a settings page.
- **Creality-specific.** We can use every quirk of the hardware instead of generic
  lowest-common-denominator abstractions.
- **Calm.** Dense when you want data, quiet when nothing is happening.

### Non-goals for v1

- Slicing, model preparation, or G-code editing.
- AI failure detection.
- A cloud relay or remote-access service.
- Supporting every printer brand.
- Replacing Creality Print for job setup.

---

## 4. Scope

### v1 — "Control room"

**Printers and connection**

- Add printers by Bonjour discovery, manual IP/hostname, or subnet scan.
- Stable printer identity (MAC/hostname) so DHCP address changes do not duplicate entries.
- One persistent WebSocket per printer with heartbeat, reconnect/backoff, and clear
  connection states.
- Multiple printers simultaneously; no practical hard limit (target: 4–6 streams).
- Optional Moonraker connection for K2 printers as a diagnostic/fallback path, not the
  primary transport.

**Live view**

- MJPEG streaming for K1-family cameras.
- WebRTC streaming for K2-family cameras.
- Snapshot button, copy snapshot, save snapshot.
- Full-screen camera, floating always-on-top camera window, PiP.
- Camera grid for 2–4 printers; focus one printer at a time.
- Honest states: camera not installed, camera unreachable, firmware mismatch, stream
  reconnecting.
- Pause the stream when the window is hidden or the app is in the background (configurable).

**Telemetry**

- Job state, file name, progress, current layer / total layers.
- Nozzle, bed, and chamber temperatures (actual and target where available).
- Time elapsed, time remaining, estimated finish time.
- Fans, print speed, flow rate, light state.
- CFS slots: material, color, remaining filament (K2 Plus and CFS-equipped models).
- Error codes and material-runout flags in human language.

**Safe controls**

- Pause / resume.
- Stop, with confirmation.
- Nozzle and bed target temperatures.
- Chamber target temperature (K2 family).
- Light on/off (and dimming on K2 where supported).
- Fan speeds.
- Speed/flow override.
- Home X/Y/Z.
- Emergency stop is deliberately *not* one-click; stop requires confirmation.

**Notifications**

- Print complete, error, paused, filament runout, and "N minutes remaining".
- Notification includes a camera snapshot when available.
- Actions: Open Chamber, Pause, Mute this print.
- Rate-limited and deduplicated; no notification storms on reconnect.
- Optional sound; respects Focus modes.

**Mac integration**

- Menu bar extra: camera thumbnail, state, progress, time left, pause/resume, open app.
- Launch at login.
- Dock-only, menu-bar-only, or both (reuse the approach proven in PrintClock).
- Keyboard shortcuts: space pause/resume, ⌘R reconnect, ⌘F full screen, ⌘1–9 switch
  printer, ⌘⇧S snapshot.
- Share sheet and drag-out for snapshots.
- Optional PrintClock handoff: set a finish time from the live printer.

**Diagnostics**

- Per-printer connection log with redacted IPs/MACs.
- "Copy diagnostics" for bug reports.
- Export a capture bundle (frames seen, camera negotiation log, firmware/model info).

### v1.1 — "Do more"

- G-code upload (`POST /upload/<name>.gcode`) and start (`opGcodeFile`).
- File browser and print history from the printer.
- Timelapse browsing and download.
- CFS material assignment and color changes.
- Recording a print to a local time-lapse.
- Shortcuts actions and App Intents ("Pause printer", "Get print progress").

### Later / exploratory

- Home Assistant bridge or MQTT publisher.
- iPad companion.
- Optional encrypted remote relay (Tailscale integration is the sane first step).
- On-device failure detection using the camera.
- Widgets and a Lock Screen-style dashboard.

### Explicitly out

- Cloud account login or Creality Cloud APIs.
- Firmware flashing, rooting, or modifying the printer.
- Slicing.
- Windows/Linux.

---

## 5. Supported hardware

The protocol is shared across Creality OS devices, but cameras and capabilities differ.

| Model | Control/telemetry | Camera | Chamber | Light | CFS | v1 target |
|---|---|---|---|---|---|---|
| **K2 Plus** | WS 9999 + Moonraker 7125 | WebRTC :8000 | Heat + sensor | Yes, dimmable | Yes | **Primary** |
| **K1 Max** | WS 9999 | MJPEG :8080 | Sensor | Yes | No (unless CFS mod) | **Primary** |
| K2 / K2 Pro | WS 9999 | WebRTC :8000 | Heat + sensor | Yes | Yes | Supported |
| K1 / K1C | WS 9999 | MJPEG :8080 (some :4409) | Sensor | Yes | Some | Supported |
| K1 SE | WS 9999 | MJPEG (optional) | No | No | No | Best effort |
| Ender-3 V3 / KE / Plus | WS 9999 | MJPEG (optional) | No | No | No | Best effort |
| Creality Hi | WS 9999 | MJPEG | No | Yes | No | Best effort |
| Older Ender (Marlin/DWIN) | — | — | — | — | — | Out of scope |

**Model detection:** use `model` / `modelVersion` telemetry, with board codes (F008, F012,
F021, F018, F001, F002, F005) as a fallback. Capabilities are feature flags derived from
telemetry, not a giant switch statement: `webrtcSupport == 1`, presence of `boxTemp`,
`lightSw`, `cfsConnect`, fan channels, and max temperatures.

**Camera selection:** prefer `webrtcSupport == 1`; otherwise probe MJPEG. Probe order:
`:8080/?action=stream`, then `:4409/webcam/?action=stream`, then the K2 WebRTC endpoint.
Cache the result per printer and re-probe after a firmware update.

---

## 6. Protocol summary

Full field guide: [`docs/protocol-notes.md`](docs/protocol-notes.md). Spike plan:
[`docs/phase-0-spike.md`](docs/phase-0-spike.md).

### Control channel

```
ws://<printer>:9999
Sec-WebSocket-Protocol: wsslicer
```

- Plain WebSocket, no auth, no TLS.
- JSON frames; the printer pushes cumulative state rather than clean deltas.
- Heartbeat: `{"ModeCode":"heart_beat"}` → reply with the literal text `ok`.
- Poll `ReqPrinterPara` every 5 s, `reqPrintObjects` every 2 s, `boxsInfo` every 300 s
  (and on demand).
- If no frame arrives for 10 s, send a probe; after 30 s of silence, reconnect.

Representative commands:

```json
{"method":"get","params":{"ReqPrinterPara":1}}
{"method":"set","params":{"pause":1}}
{"method":"set","params":{"stop":1}}
{"method":"set","params":{"lightSw":1}}
{"method":"set","params":{"nozzleTempControl":215}}
{"method":"set","params":{"bedTempControl":{"num":0,"val":60}}}
{"method":"set","params":{"boxTempControl":40}}
{"method":"set","params":{"gcodeCmd":"M106 P0 S255"}}
{"method":"set","params":{"setFeedratePct":100}}
{"method":"set","params":{"autohome":"X Y"}}
```

### Cameras

**K1 family — MJPEG**

```
http://<printer>:8080/?action=stream
http://<printer>:8080/?action=snapshot
```

Some firmware exposes `:4409/webcam/?action=stream`. Parse the multipart stream and pull
JPEG frames; do not use a `WKWebView`.

**K2 family — WebRTC**

```
POST http://<printer>:8000/call/webrtc_local
Content-Type: plain/text
Body: base64(JSON({"type":"offer","sdp":"..."}))
Response: base64(JSON({"type":"answer","sdp":"..."}))
```

Known hazards, all documented by the Home Assistant Creality integration:

1. **RTP timestamps run ~20× fast.** Chromium hides it; WebKit-based clients lag badly.
   A native renderer must pace frames by arrival time (or re-stamp), not trust the RTP
   clock. This is a design requirement, not an optimization.
2. **mDNS ICE candidates fail.** The printer only starts connectivity checks for a
   routable IPv4 candidate. Do not advertise `<uuid>.local` host candidates.
3. **SDP must use CRLF.** Bare LF line endings can wedge the K1C's WebRTC server until
   the printer is power-cycled.
4. **Firmware regressions exist.** At least one K2 Plus firmware release broke the
   `:8000` stream. Detect and explain this instead of showing a spinner forever.
5. **One stream per printer may be enough.** Avoid opening multiple peer connections for
   the same printer; share one decoded stream across windows.

---

## 7. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         Chamber.app                          │
│                                                              │
│  ┌────────────────┐   ┌────────────────┐   ┌──────────────┐  │
│  │   ChamberUI    │   │  ChamberCore   │   │ CameraKit    │  │
│  │ SwiftUI views  │──▶│ state, actions │──▶│ MJPEG/WebRTC │  │
│  │ menu bar, etc. │   │ notifications  │   │ renderers    │  │
│  └────────────────┘   └───────┬────────┘   └──────┬───────┘  │
│                               │                   │          │
│                     ┌─────────▼────────┐   ┌──────▼───────┐  │
│                     │  CrealityKit     │   │  AVFoundation│  │
│                     │ WS, HTTP, models │   │  VideoToolbox│  │
│                     │ discovery, CFS   │   │  WebRTC.xcff │  │
│                     └─────────┬────────┘   └──────────────┘  │
└───────────────────────────────┼──────────────────────────────┘
                                │ LAN
                    ┌───────────▼───────────┐
                    │  K2 Plus / K1 Max     │
                    │  :9999 · :8000 · :8080│
                    └───────────────────────┘
```

### Modules

**`CrealityKit`** — no UI, no AppKit.

- `PrinterConnection` actor: WebSocket lifecycle, frame decoding, cumulative state,
  heartbeat, backoff.
- `PrinterProtocol`: typed commands and telemetry keys.
- `PrinterModel`: normalized snapshot (`PrinterState`) + capability flags.
- `Discovery`: Bonjour (`NWBrowser`), manual endpoint, optional subnet probe.
- `PrinterStore`: persistence, stable IDs, migrations.
- `MoonrakerClient` (optional): job queue, history, fallback telemetry.

**`CameraKit`**

- `MJPEGStream`: `URLSession` byte stream + multipart/JPEG parser, frame pacing.
- `WebRTCStream`: peer connection, offer/answer, ICE, custom renderer.
- `FrameRenderer`: `AVSampleBufferDisplayLayer` with arrival-time presentation
  timestamps; Metal path if needed.
- `SnapshotStore`: last frame, thumbnail cache, disk cache for notifications.
- `CameraSupervisor`: one stream per printer, shared across views; suspends when no
  consumer.

**`ChamberCore`**

- `PrinterRuntime`: combines connection + camera + derived state machine.
- `NotificationEngine`: transitions, debounce, snapshot attachment, actions.
- `PrintClockBridge`: finish-time handoff.
- `Diagnostics`: redacted log, capture export.

**`ChamberUI`**

- `AppShell`: `NavigationSplitView`, toolbar, inspector, settings.
- `PrinterSidebar`, `CameraStage`, `StatusStrip`, `ControlInspector`.
- `MenuBarExtra` content and `NSStatusItem` controller.
- `Onboarding`, `Settings`, `DiagnosticsView`.

### Concurrency model

- Swift 6 language mode, strict concurrency.
- One `PrinterConnection` actor per printer; UI observes a `@MainActor @Observable`
  runtime facade.
- Camera frames never cross the main actor. Decode/render on a dedicated queue; publish
  only snapshots and state to the UI.
- All network I/O is cancellation-aware. Closing a window stops consumers; idle printers
  keep telemetry but drop video.

### Networking details

- `URLSessionWebSocketTask` cannot set a custom `Sec-WebSocket-Protocol` header on all
  OS versions reliably; use `URLSessionWebSocketTask` with `URLRequest` and verify, or
  fall back to `Network.framework`'s WebSocket support. Phase 0 must prove the handshake
  with `wsslicer`.
- `URLSession` streaming for MJPEG; `Network.framework` for Bonjour and raw probes.
- App Sandbox: `com.apple.security.network.client`. Local Network privacy prompt on
  current macOS; include `NSLocalNetworkUsageDescription` and `NSBonjourServices`.
- No inbound listener in v1, so no server entitlement needed.

### Camera decision gate (Phase 0)

Three candidates, evaluated against real K2 Plus and K1 Max hardware:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Google WebRTC + custom renderer** | No helper process, smallest app, best latency, native | Timestamp and ICE quirks; framework size; more code | **Preferred** |
| **B. Bundle go2rtc helper** | Proven Creality support, re-stamps timestamps, handles odd firmware | Extra process, ~20–40 MB, sandbox/notarization complexity, App Store friction | Fallback |
| **C. MJPEG only** | Simple, reliable | K2 has no MJPEG; loses the main printer | Not viable alone |

**Exit criteria for the spike:** K2 Plus streams 1080p for 30 minutes at ≤1.5 s latency,
≤10% CPU on an M-series Mac, no drift, survives sleep/wake and printer reboot. If A
fails, ship B; do not spend v1 fighting WebRTC.

---

## 8. UX and visual design

Full brief: [`docs/design-brief.md`](docs/design-brief.md).

### Surfaces

1. **Main window** — sidebar, camera stage, status strip, control inspector.
2. **Menu bar popover** — snapshot, state, progress, time left, pause/resume, open.
3. **Floating camera** — small always-on-top window with minimal HUD.
4. **Full-screen camera** — keyboard exit, auto-hiding HUD.
5. **Settings** — printers, cameras, notifications, general, diagnostics.
6. **Onboarding** — discover, name, verify camera, enable notifications.

### Main window sketch

```
┌───────────────┬──────────────────────────────────┬──────────────────┐
│ Printers      │  K2 Plus                    ● Live │  Job             │
│               │ ┌──────────────────────────────┐ │  Benchy           │
│ ● K2 Plus     │ │                              │ │  ███████░░ 68%    │
│   Printing    │ │          camera              │ │  1h 12m left      │
│               │ │                              │ │                  │
│ ○ K1 Max      │ │                              │ │  Temperatures     │
│   Idle        │ └──────────────────────────────┘ │  Nozzle  215/215  │
│               │  Nozzle 215°  Bed 60°  Chamber 38°│  Bed      60/60   │
│ + Add printer │  Layer 84/124        01:12:33 left│  Chamber  38/40   │
│               │                                   │                  │
│               │  [Pause] [Stop] [Light] [Snapshot]│  Fans / Speed     │
└───────────────┴──────────────────────────────────┴──────────────────┘
```

### Design principles

- **Camera is the hero.** Give it the largest area and the least chrome. Controls live
  below or beside it, never on top of the video except on hover.
- **One accent color, semantic status colors.** System accent for interaction; teal/blue
  for printing, amber for paused, red for error, gray for idle/offline.
- **Monospaced digits** for temperatures, times, and percentages to stop layout jitter.
- **Density with breathing room.** A compact status strip, a calm inspector.
- **No fake 3D, no neon gamer aesthetic.** Think native Mac utility with a warm workshop
  feel: graphite, soft materials, a single warm accent, crisp typography.
- **Motion only for meaning.** Filmstrip fade on camera connect, progress bar easing,
  no bouncing icons.
- **Every empty state is a next step.** "No printers found" offers Scan, Enter IP, and
  Troubleshoot.

### Interaction details

- Click camera → focus; double-click → full screen.
- Space toggles pause/resume when a printer is selected.
- ⌘F full screen, Esc exits.
- Hover over camera reveals snapshot, full screen, floating window, mute (future audio).
- Drag snapshot out to Finder, Mail, or Messages.
- Right-click printer in sidebar: Reconnect, Copy IP, Open in Browser, Diagnostics.
- Menu bar extra shows a live thumbnail at ~1 fps, full-rate only when the popover is open.
- Notifications group per printer; actions don't require opening the app.

### Accessibility

- Full keyboard navigation and focus rings.
- VoiceOver labels for every control, including camera state.
- Reduce Motion disables fades and progress animation.
- Increase Contrast mode uses solid fills and stronger borders.
- No color-only status; pair every color with text or an SF Symbol.
- Minimum hit target 28×28 pt; camera controls 32×32 pt.

---

## 9. Feature specifications

### 9.1 Connection lifecycle

States: `idle → discovering → connecting → live → degraded → reconnecting → offline`.

- First connect: resolve host, open WebSocket with `wsslicer`, wait for the first JSON
  frame (not just TCP), then become `live`.
- Connection is "degraded" after 10 s without a frame; reconnect after 30 s.
- Backoff: 1 s, 2 s, 4 s, 8 s, 16 s, 30 s, capped at 60 s; reset after 10 s of healthy
  connection.
- Manual Reconnect bypasses backoff once.
- Printer powered off is a normal state, not an error: poll quietly every 10–15 s.
- Distinguish "printer unreachable" from "printer reachable but API not answering" in the
  UI and diagnostics.

### 9.2 Telemetry normalization

The printer sends cumulative, loosely typed state. `PrinterState` is a normalized value
type produced by a reducer:

- Coerce numeric strings to numbers once, at the edge.
- Keep raw telemetry for diagnostics.
- Derive state: printing, paused, idle, complete, error, heating, homing, self-test.
- `state` semantics differ across models; always cross-check `printFileName`,
  `printProgress`, and `printJobTime`.
- Treat a new file name or a backward `printJobTime` as a new job and reset per-job
  notification latches.
- Never let a missing field erase a known capability or a good value.

### 9.3 Camera pipeline

```
URLSession bytes ─▶ multipart parser ─▶ JPEG frames ─▶ frame pacer ─▶ AVSampleBufferDisplayLayer
WebRTC peer ─────▶ RTP/VP8/H264 ─────▶ decoder ─────▶ arrival-time renderer ─▶ layer
```

- One camera pipeline per printer, shared by all windows.
- Keep the last frame for instant display on reopen and for notifications.
- Drop frames rather than queue them when the display can't keep up.
- Target latency: <1 s on LAN for MJPEG; <1.5 s for WebRTC.
- Reconnect camera independently from telemetry; telemetry must keep working when video
  fails.
- Do not log camera credentials or full URLs at info level.

### 9.4 Notifications

Transitions, not snapshots:

- Printing → complete (progress 100 or state idle with a completed job).
- Printing → error (`err.errcode != 0`).
- Printing → paused (including runout).
- Remaining time crosses N minutes (default 10, configurable 1–60).
- Printer offline for more than 2 minutes while a job is active.

Rules:

- One notification per event per job.
- Attach the latest snapshot as a thumbnail.
- If the app is frontmost and the printer is selected, show an in-app banner instead.
- Coalesce multiple printers into a summary when more than two fire within 10 s.
- Never notify for reconnects, stale flags, or the printer's known runout latch quirks.

### 9.5 Menu bar extra

- Icon reflects aggregate state (printing/paused/error/idle) with a subtle badge.
- Popover: selected printer snapshot, name, state, progress, time left, temps.
- Buttons: Pause/Resume, Stop (confirmation), Open Chamber.
- Printer switcher if more than one.
- Thumbnail pauses when the popover closes; telemetry continues.
- Menu bar-only mode uses the same `NSStatusItem` pattern as PrintClock, including the
  activation-policy switch.

### 9.6 PrintClock handoff

Two options, in order of preference:

1. URL scheme: `printclock://timer?finish=<ISO8601>&source=chamber`. PrintClock adds a
   small handler; no shared framework needed.
2. In-app "Set finish time in PrintClock" button, enabled when PrintClock is installed.

If PrintClock is not installed, offer "Copy finish time" instead. Do not duplicate
PrintClock's timer UI inside Chamber.

### 9.7 Diagnostics

- Ring buffer of the last 2,000 protocol events per printer.
- Camera negotiation log: endpoint probed, HTTP status, SDP summary, ICE state, first
  frame time, frames dropped.
- Redact IP addresses, MAC addresses, and file names by default.
- "Export diagnostics" produces a zip with a README and a JSON manifest.
- A hidden developer menu can replay captured frames through the reducer.

---

## 10. Roadmap

Estimates assume one experienced Swift developer. "Part-time" means ~12–15 h/week.

| Phase | Duration | Deliverable | Exit criteria |
|---|---|---|---|
| **0. Protocol + camera spike** | 4–6 days | CLI harness that connects to K2 Plus and K1 Max, dumps state, displays both cameras | Both cameras stable for 30 min; WebRTC option chosen; protocol fixtures captured |
| **1. CrealityKit** | 1.5–2 weeks | WebSocket client, models, discovery, persistence, mock server | Reconnect suite passes; two printers tracked for 24 h; mock replays fixtures |
| **2. CameraKit** | 2–3 weeks | MJPEG + WebRTC pipelines, snapshots, shared stream supervisor | Latency/CPU targets met; sleep/wake and printer reboot handled |
| **3. App shell + controls** | 2 weeks | Sidebar, camera stage, inspector, safe controls, menu bar | All v1 controls work against both printers; confirmation flows |
| **4. Notifications + polish** | 1.5 weeks | Notification engine, onboarding, settings, accessibility, diagnostics | No duplicate/missed notifications in 72 h soak; VoiceOver pass |
| **5. Beta + packaging** | 1 week | Signed/notarized DMG, Homebrew cask, README, beta feedback | 10 external users; crash-free sessions >99%; install docs tested |

**Total:** ~8–10 weeks full-time including buffer; ~3–4 months part-time.

### Phase 0 is the decision point

Do not build the app shell first. The risk is the camera, not SwiftUI. The spike should
answer:

- Does `URLSessionWebSocketTask` negotiate `wsslicer` reliably?
- Does direct WebRTC work from a native macOS peer, or do we need go2rtc?
- What does the K2 Plus do across a 30-minute stream, sleep/wake, and a printer reboot?
- What are the real frame rates, bitrates, and CPU costs?
- Which firmware versions are on the two printers, and what regressions exist?

If Phase 0 slips by more than a week, cut WebRTC from v1 and ship a K1-only beta while
continuing the K2 spike. Do not ship a broken camera for the flagship printer.

---

## 11. Testing strategy

### Without hardware

- **Mock printer**: a small Swift executable that serves WebSocket `:9999`, MJPEG
  `:8080`, and fake WebRTC signalling `:8000`, driven by JSON fixtures. (The
  `CFSync` mock and `ha_creality_ws` simulator are useful references.)
- **Golden fixtures**: recorded frames from real K1 Max and K2 Plus sessions, including
  connection start, pause, resume, complete, error, runout, CFS changes, and malformed
  frames.
- **Reducer tests**: every telemetry key, missing fields, stale values, model variants.
- **Camera parser tests**: multipart boundaries split across packets, truncated JPEGs,
  slow consumers, reconnect mid-frame.
- **UI tests**: onboarding, add printer, switch printer, pause confirmation, notification
  actions, menu bar mode.

### With hardware

- 24-hour soak per printer, including a print.
- Sleep/wake the Mac mid-print.
- Reboot the printer mid-stream.
- Change DHCP address while running.
- Two printers streaming simultaneously.
- Wi-Fi roaming and a brief network drop.
- Firmware update regression check before each release.

### Performance budgets

| Metric | Target |
|---|---|
| Time to first frame after launch | < 2 s |
| Camera latency (LAN) | < 1.0 s MJPEG, < 1.5 s WebRTC |
| CPU per 1080p stream | < 10% on M1/M2 |
| Memory, 2 printers + 2 streams | < 350 MB |
| Reconnect after printer reboot | < 15 s |
| Notification delivery | < 2 s after state transition |

### Release gates

- No known crash in the last 7 days of beta.
- Both primary printers pass the hardware matrix.
- Camera failure produces a useful, actionable message, never an infinite spinner.
- Diagnostics contain no unredacted network identifiers by default.

---

## 12. Distribution, security, and legal

### Distribution

- Direct download: notarized DMG, universal binary (Apple Silicon + Intel), Homebrew cask.
- Mac App Store is possible for a native-only build, but bundled helper binaries and
  broad local-network access make direct distribution simpler. Decide after Phase 0.
- Sparkle 2 for updates (signed appcast), or reuse PrintClock's GitHub-release checker
  for consistency. Sparkle is the better long-term choice for delta updates.

### Security posture

- The printer API is unauthenticated plain HTTP/WS on the LAN. State that plainly.
- No credentials are stored because there are none.
- Bind to nothing; Chamber is a client only.
- Warn if the user enters a public IP address or tries to expose the printer to the
  internet.
- Recommend a trusted VLAN or VPN (Tailscale) for remote access.
- Redact identifiers in logs; require explicit consent to include sensitive data in a
  diagnostics export.

### Legal and naming

- The protocol is undocumented and reverse-engineered by the community. Chamber is an
  independent client, not affiliated with Creality.
- Do not use Creality logos or assets. Use "for Creality printers" descriptively, not
  "Creality Chamber".
- Do not bypass Creality Cloud authentication or DRM.
- Ship with a clear disclaimer and an MIT (or similar) license.
- Final name and bundle ID need a trademark/App Store check. "Chamber" is a working title.

---

## 13. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| K2 WebRTC is unreliable from native macOS | Medium | High | Phase 0 gate; go2rtc fallback; custom timestamp renderer |
| Firmware changes break the protocol | High | Medium | Capability flags, tolerant decoding, diagnostics, quick releases |
| Printer limits concurrent clients/streams | Medium | Medium | One shared stream per printer; test 2–6 printers; backoff |
| Camera port 8000 regressions | Medium | High | Detect and explain; recommend known-good firmware; MJPEG fallback where possible |
| Long-running stream leaks memory | Medium | Medium | Soak tests, frame pools, Instruments budgets |
| Notification spam / wrong states | High | Medium | Transition model, per-job latches, 72 h soak |
| App Store rejection or sandbox issues | Low–Medium | Medium | Direct distribution first; sandbox audit |
| Trademark conflict with name | Low | High | Clear before public beta |
| Building for "all Creality" too early | High | Medium | Model-driven support with a tested matrix; best-effort label for untested models |
| User expects remote access | Medium | Medium | Explicit LAN/VPN positioning; Tailscale guide |

---

## 14. Decisions and open questions

### Decided

- Native SwiftUI app, macOS 14+, Swift 6.
- Local-first, no account, LAN + VPN only.
- v1 = monitor + safe controls; print starting after v1.
- One shared WebSocket protocol for all supported printers.
- MJPEG for K1, WebRTC for K2, with go2rtc as the fallback plan.
- New repository, separate from PrintClock.
- XcodeGen + SwiftPM modules, matching the PrintClock workflow.

### Open

1. **Final name and bundle ID.** "Chamber" is a placeholder. Shortlist: Chamber,
   PrintPerch, LayerView, Kiosk. Check trademarks and App Store availability.
2. **Minimum macOS.** 14 keeps a wider audience; 15 unlocks newer SwiftUI and local-network
   behavior. Recommendation: macOS 14.
3. **Intel support.** Universal binary doubles camera framework size and test surface.
   Recommendation: Apple Silicon first, Intel if WebRTC framework cooperates.
4. **Distribution.** Direct + Homebrew recommended; Mac App Store only if the camera path
   stays helper-free.
5. **Camera architecture.** Decide after the Phase 0 spike, not before.
6. **PrintClock integration depth.** URL-scheme handoff is cheap and useful; a shared
   package is overkill for v1.
7. **Moonraker.** Use as a diagnostic fallback on K2, not as the primary API. Revisit for
   print queue/history in v1.1.
8. **License and telemetry.** MIT recommended; no telemetry by default, opt-in crash
   reports only.
9. **Whether to support rooted/custom Klipper printers** in v1. Recommendation: later;
   Moonraker support is a separate mode.

---

## 15. Definition of done for v1

- A new user can install, discover both printers, and see live video without reading docs.
- Both cameras stream for an hour with no manual intervention.
- Pause, resume, stop, light, fans, and temperatures work on both printers.
- A completed print produces exactly one notification with a snapshot.
- The menu bar extra shows useful status and can pause/resume.
- The app survives sleep/wake, printer reboot, and a Wi-Fi drop.
- Diagnostics can explain a camera failure without a debugger.
- The app is signed, notarized, and installable via DMG and Homebrew.
- No cloud account is required at any point.

---

## 16. References

- K2 Companion for Creality (Google Play):
  https://play.google.com/store/apps/details?id=uk.co.harktech.k2_companion
- Home Assistant Creality WebSocket integration and engineering reference:
  https://github.com/3dg1luk43/ha_creality_ws
- Older K1 integration:
  https://github.com/hurricaneb/hass_creality_k1
- go2rtc Creality WebRTC support:
  https://github.com/AlexxIT/go2rtc/issues/1600
- Printer Tools protocol notes (K1 MJPEG / K2 WebRTC, port 9999):
  https://printertools.app/blog/guides/troubleshoot-creality-k1-k2-local-monitoring
- Printago: K2 Moonraker on port 7125:
  https://docs.printago.io/docs/connecting-printers/creality
- SimplyPrint: Creality LAN mode and camera behavior:
  https://help.simplyprint.io/en/article/creality-k1-k1c-k1-max-ke-and-k2-simplyprint-client-or-klipper-and-the-camera-p0bwte/
- K2 Plus camera port regression thread:
  https://forum.creality.com/t/k2-plus-camera-feed-no-longer-on-port-8000/51384
- PrintClock (existing Mac app, for patterns and handoff):
  https://github.com/frankt2012/PrintClock
