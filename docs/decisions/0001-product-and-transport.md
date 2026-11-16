# ADR 0001 — Product shape and transport

- **Status:** Accepted
- **Date:** 2026-11-12

## Context

We want a native macOS app to watch and control Creality printers, initially a K2 Plus and
a K1 Max, inspired by K2 Companion on Android. The printers expose an undocumented local
API. Camera transport differs by family: MJPEG on K1, WebRTC on K2.

## Decisions

1. **Native SwiftUI app, macOS 14+, Swift 6.** No embedded web UI as the primary
   interface.
2. **Local-first.** No Creality account, no cloud relay. Remote access is via VPN
   (Tailscale or equivalent), not a service we operate.
3. **v1 is monitor + safe controls.** Live camera, telemetry, pause/resume/stop, light,
   fans, temperatures, notifications, menu bar. G-code upload/start and CFS material
   changes are v1.1.
4. **Primary transport is `ws://<printer>:9999` with subprotocol `wsslicer`.** Moonraker
   on port 7125 is an optional fallback/diagnostic path, not the primary API.
5. **MJPEG for K1-family cameras; WebRTC for K2-family cameras.** The K2 camera path is
   validated in a Phase 0 spike before the UI is built.
6. **Separate repository from PrintClock.** Integration is a URL-scheme handoff, not a
   shared framework.
7. **Model-driven capabilities, not per-model code paths.** Derive features from
   telemetry flags and board codes.

## Consequences

- We own the protocol client and its quirks; firmware changes are an ongoing maintenance
  cost.
- The app can work with the internet down and requires no account, which is the main
  differentiator.
- The camera is the critical path. If native WebRTC fails the spike, we accept a bundled
  go2rtc helper as the fallback.
- "All Creality printers" means Creality OS / Klipper-based models; older Marlin/DWIN
  printers are out of scope.
