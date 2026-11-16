# Chamber — design brief

A native Mac app for watching and controlling Creality printers. The design target is
"calm control room", not "gamer dashboard" and not "phone app in a bigger window".

---

## 1. Design intent

**Three feelings, in order:**

1. **Reassurance.** A glance tells you the print is fine, or exactly what is wrong.
2. **Presence.** The camera feels live and immediate, not like a web page embedded in an
   app.
3. **Control.** Actions are obvious, reversible where possible, and never accidentally
   destructive.

**Reference points:** Apple's Home app for glanceable device state, Freeform for a calm
canvas, Xcode's inspector for density, Halide for camera-first chrome, and a physical
workshop control panel for warmth.

**Avoid:** neon RGB, fake carbon fiber, oversized phone buttons, glassmorphism on every
surface, animated gradients, "AI" badges, and dashboards that look like a car stereo.

---

## 2. Surfaces

### 2.1 Main window

Default 1180 × 760 pt; minimum 960 × 620 pt. Resizable, restorable, multiple windows
allowed (one per printer, optionally).

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ⌘  Chamber            [grid] [focus]        [snapshot] [full screen]  ⋯   │  toolbar
├──────────────┬──────────────────────────────────────────┬──────────────────┤
│  PRINTERS    │                                          │  JOB             │
│              │                                          │                  │
│  ● K2 Plus   │              live camera                 │  Benchy.3mf      │
│    Printing  │              (16:9, fills)               │  ███████░░░ 68%  │
│              │                                          │  1h 12m left     │
│  ○ K1 Max    │                                          │                  │
│    Idle      │                                          │  TEMPERATURES    │
│              │                                          │  Nozzle 215/215  │
│              │                                          │  Bed     60/60   │
│  + Add       │  ┌────────────────────────────────────┐  │  Chamber 38/40   │
│              │  │ Nozzle 215°  Bed 60°  Chamber 38°  │  │                  │
│              │  │ Layer 84/124        01:12:33 left  │  │  FANS / SPEED    │
│              │  └────────────────────────────────────┘  │  ...             │
│              │  [ Pause ]  [ Stop ]  [ Light ]  [ ⤓ ]   │                  │
└──────────────┴──────────────────────────────────────────┴──────────────────┘
```

- **Sidebar** 220–260 pt: printer list, state dot + label, tiny progress line. Bottom:
  Add Printer. Collapsible with ⌃⌘S.
- **Camera stage:** flexible; 16:9 letterboxed with a subtle rounded corner (12 pt). Black
  stage, not a card floating on gray. HUD appears on hover.
- **Status strip** beneath the camera: temperatures, layer, time left. Compact, monospaced.
- **Action row:** Pause/Resume is primary; Stop is secondary and confirmed; Light and
  Snapshot are icon buttons.
- **Inspector** 300 pt: Job, Temperatures, Fans/Speed, CFS, Printer info. Collapsible with
  ⌥⌘I. Sections use disclosure groups, remembered per printer.

### 2.2 Menu bar popover

Width 340 pt. Content:

```
┌──────────────────────────────────┐
│  K2 Plus              Printing ● │
│  ┌────────────────────────────┐  │
│  │      snapshot / live       │  │
│  └────────────────────────────┘  │
│  Benchy               68%        │
│  ███████████░░░░░  1h 12m left   │
│  215° / 60° / 38°                │
│  [ Pause ]        [ Open Chamber ]│
└──────────────────────────────────┘
```

- Live thumbnail at ~1 fps; full rate only while the popover is open.
- If multiple printers: a small segmented picker or a list; aggregate badge on the icon.
- Menu bar icon: template image; a small dot or progress ring for state. No color-only
  status.
- Menu bar-only mode: same content, `LSUIElement`/activation policy switch.

### 2.3 Floating camera

- 320 × 180 default, resizable, always-on-top, remembers position per printer.
- Rounded corners, 1 pt border, shadow; drag anywhere.
- HUD on hover: name, state, time left, pause, close.
- Keyboard: ⌘⇧F toggles floating camera for the selected printer.
- Does not steal focus when shown.

### 2.4 Full-screen camera

- True full screen on the selected display.
- Auto-hiding HUD (3 s): name, progress, time left, temps.
- Esc exits; space pauses; ⌘⇧S snapshot.
- Optional "keep screen awake while printing" (default on, per printer setting).

### 2.5 Onboarding

Four steps, one window, 720 × 520:

1. **Welcome** — one sentence, no marketing carousel.
2. **Find printers** — Bonjour results appear as cards; "Enter IP address" secondary;
   "Scan my network" tertiary with progress.
3. **Verify** — for each printer: name, model, firmware, camera test with a live preview
   or a clear failure reason.
4. **Notifications** — explain what will be sent, request permission, offer a test.

No account. No email. No "sign in with Creality".

### 2.6 Settings

Tabs: General, Printers, Cameras, Notifications, Diagnostics.

- **General:** launch at login, Dock/menu bar mode, appearance (System/Light/Dark),
  keep awake while printing.
- **Printers:** list, add/remove, host, stable ID, reconnect, firmware/model info.
- **Cameras:** per-printer mode (Auto/MJPEG/WebRTC), quality cap, hardware decoding,
  pause when hidden, snapshot folder.
- **Notifications:** per-event toggles, minutes-remaining value, sound, snapshot
  attachment, Focus behavior.
- **Diagnostics:** log level, copy diagnostics, export bundle, reset caches.

---

## 3. Visual system

### Color

Use system materials and semantic colors. Do not hard-code a brand palette that fights
macOS.

| Role | Light | Dark | Usage |
|---|---|---|---|
| Window background | system window | system window | Base |
| Sidebar | thin material | thin material | Sidebar |
| Stage | near-black (`#0B0C0E`) | near-black | Camera stage |
| Primary text | label | label | Names, values |
| Secondary text | secondary label | secondary label | Units, metadata |
| Printing | teal (`#2FB7A8`) | teal | State dot, progress |
| Paused | amber (`#D89A2B`) | amber | State dot |
| Error | red (`#D9534F`) | red | State dot, error banner |
| Idle/offline | gray | gray | State dot |
| Accent | system accent | system accent | Selection, primary buttons |

Rules:

- Status color is never the only signal; always pair with a label or symbol.
- Use at most one saturated color in the camera area (the status dot).
- Camera letterboxing is pure black; no gradients behind video.

### Typography

- UI: SF Pro Text / system font, 13 pt body, 11 pt captions, 15 pt section titles.
- Numeric readouts: SF Mono or `.monospacedDigit()` at 13–22 pt.
- Job name: 15 pt semibold, truncated in the middle.
- No custom fonts. No all-caps except small section labels with 0.5 pt tracking.

### Spacing and shape

- 4 pt grid; 8/12/16/24 pt spacing scale.
- Corner radii: 8 pt controls, 12 pt camera, 10 pt cards.
- Borders: 1 pt separator at 60% opacity; no heavy strokes.
- Shadows only on floating windows and popovers, never on inline cards.

### Iconography

- SF Symbols throughout: `play.fill`, `pause.fill`, `stop.fill`, `lightbulb.fill`,
  `camera.fill`, `arrow.up.right.square`, `thermometer.medium`, `fanblades.fill`.
- Custom symbols only where SF Symbols has no equivalent (e.g. CFS spool).
- 16 pt in toolbars, 14 pt inline, 20 pt in empty states.

---

## 4. Components

### Printer row

```
●  K2 Plus                    68%
   Printing · 1h 12m left     ▬▬▬▬▬▬▬░░
```

- 44 pt tall, full-width selection.
- State dot 8 pt; pulse only while connecting.
- Hover reveals a reconnect button on the right.
- Right-click context menu.

### Camera stage

- Aspect-fit video, black background, 12 pt radius.
- Top-left HUD: printer name + state pill. Top-right: live indicator + resolution/fps
  (optional, debug).
- Bottom gradient HUD on hover: snapshot, full screen, floating, mute (future).
- Connecting: a still of the last frame with a subtle shimmer and "Reconnecting…" label.
- No camera: a centered illustration + "No camera detected" + Troubleshoot button.
- Error: a specific message, not "Something went wrong".

### Temperature pill

```
Nozzle   215°  / 215°
```

- Label 11 pt secondary; value 13 pt monospaced; target 11 pt secondary.
- Tap opens a popover slider with a text field and presets.
- Heating state: a thin progress arc or a subtle pulsing dot, not a color flash.

### Progress

- Linear bar, 6 pt tall, rounded; percentage right-aligned.
- Time left beneath, secondary; finish time on hover.
- Layer progress as a secondary line: "Layer 84 of 124".
- Never animate progress backwards on reconnect; snap and continue.

### Action buttons

- Pause/Resume: prominent, bordered, accent tint when paused.
- Stop: bordered, red text; opens a confirmation sheet that names the job and explains it
  cannot be undone.
- Light: toggle with a clear on/off state.
- Snapshot: momentary; shows a "Saved to Desktop" toast with Show in Finder.
- Disabled states explain why (tooltip), never just gray out silently.

### Notifications

- Title: printer name + event ("K2 Plus finished printing").
- Body: job name, duration, and a short result.
- Attachment: snapshot, 16:9, no text overlay.
- Actions: Open, Pause (for errors/runout), Mute this print.
- Group by printer; summary when several events fire together.

### Empty and error states

| State | Message | Action |
|---|---|---|
| No printers | "No printers yet." | Add Printer, Scan |
| Printer offline | "K2 Plus is offline." | Reconnect, Network Help |
| API refused | "Connected, but the printer API didn't answer." | Diagnostics, Retry |
| Camera absent | "No camera detected on this printer." | Learn More |
| Camera firmware issue | "The camera service isn't responding on this firmware." | Firmware Notes, Retry |
| Wrong IP | "Another device is using this address." | Edit Address |

Every error state includes a "Copy diagnostics" link.

---

## 5. Motion

- Camera connect: 150 ms fade from last frame to live.
- State changes: 120 ms color/label crossfade.
- Progress: 200 ms linear interpolation, no spring.
- Sidebar selection: standard macOS.
- No looping animations except a small "live" pulse (1.6 s) that can be disabled.
- Respect Reduce Motion: replace fades with cuts and disable pulses.

---

## 6. Keyboard and menus

| Shortcut | Action |
|---|---|
| Space | Pause/resume selected printer |
| ⌘R | Reconnect selected printer |
| ⌘F | Full screen camera |
| ⌘⇧F | Floating camera |
| ⌘⇧S | Snapshot |
| ⌘1–9 | Select printer |
| ⌘, | Settings |
| ⌥⌘I | Toggle inspector |
| ⌃⌘S | Toggle sidebar |
| ⌘⇧D | Copy diagnostics |
| Esc | Exit full screen / dismiss HUD |

Menus:

- **File:** Add Printer, Snapshot, Export Diagnostics, Close Window.
- **Printer:** Pause/Resume, Stop, Light, Home, Reconnect, Reveal in Browser.
- **View:** Sidebar, Inspector, Grid/Focus, Full Screen Camera, Floating Camera.
- **Window:** standard.
- **Help:** Chamber Help, Creality Protocol Notes, Report an Issue.

---

## 7. Copy tone

- Direct, calm, specific.
- Prefer "K2 Plus is offline" over "Connection error".
- Explain what the user can do next.
- Never blame the user or the printer without evidence.
- No exclamation marks. No "Oops".

Examples:

- "Camera stream ended. The printer is still printing."
- "This firmware reports no camera. You can still monitor the print."
- "Stop this print? The print head will return to home and the job cannot be resumed."
- "Connected to the printer, but it didn't send status. Try reconnecting."

---

## 8. Accessibility

- Every control has a label and help text; icons are not the only label.
- Full keyboard access; focus ring visible on the camera stage.
- VoiceOver announces state changes politely, not constantly:
  "K2 Plus, printing, 68 percent, 1 hour 12 minutes remaining."
- Reduce Motion and Increase Contrast are honored.
- Minimum contrast 4.5:1 for text, 3:1 for large text.
- Camera HUD remains readable over bright prints via a subtle scrim, not a heavy bar.
- Snapshot and notification text are accessible; images have alt text ("Snapshot of K2
  Plus print at 68 percent").
- Support Dynamic Type equivalents through system text sizes where feasible (macOS
  accessibility text size).

---

## 9. Native APIs to use

- `NavigationSplitView`, `.inspector`, `.toolbar`, `.searchable` where relevant.
- `MenuBarExtra` or `NSStatusItem` for the menu bar (choose after testing multi-window
  behavior; PrintClock's `NSStatusItem` approach is proven).
- `AVSampleBufferDisplayLayer` for K1 MJPEG camera rendering.
- `WKWebView` for the v1 K2 camera surface, pointed at the local go2rtc WebRTC page;
  a native WHEP client is the follow-up.
- `UNUserNotificationCenter` with categories and actions.
- `NSWorkspace` for reveal/open, `NSSharingServicePicker` for share.
- `SMAppService` for launch at login (macOS 13+).
- `NWBrowser` for Bonjour, `NWPathMonitor` for network changes.
- `Settings` scene for preferences; `WindowGroup` for main and floating windows.
- `AppIntents` in v1.1, not v1.
- `os.Logger` with per-subsystem categories and privacy annotations.

---

## 10. What makes it feel like a Mac app

- It remembers window frames, sidebar width, inspector width, and last selected printer.
- It supports multiple windows and full screen without custom title bar tricks.
- It uses the standard About, Settings, Services, Hide, and Quit menus.
- It does not put iOS-style segmented controls or bottom tab bars in a desktop window.
- It uses the menu bar for glanceable status, not as the only UI.
- It handles sleep/wake, display changes, and network changes gracefully.
- It feels fast: no spinners for local operations, no 300 ms artificial transitions.
- It has a real Help book or at least a concise in-app help window.
