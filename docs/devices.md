# Devices

Working hardware for PrintHub development.

| Name | Model | Firmware | Address | Control | Camera | Notes |
|---|---|---|---|---|---|---|
| K2 Plus | Creality K2 Plus | 1.1.8.0 | 192.168.1.50 | WS `:9999` | WebRTC `:8000` | Fluidd at `:4408`; primary test printer |
| K1 Max | Creality K1 Max | unknown | unknown | WS `:9999` | MJPEG `:8080` / `:4409` | Down for repair; deferred |

## Notes

- The `:4408` URL is Fluidd, not the printer API. PrintHub uses `:9999` for
  telemetry/control and `:8000` for the K2 camera.
- Use a DHCP reservation for the printer so the address does not move.
- On 15 Nov 2026 the K2 Plus was not reachable from the OpenCode sandbox:
  `ping` returned “No route to host”, `curl :4408` failed immediately, and a
  `/24` scan found no host at `.243`. The user’s Chrome reached it without
  trouble, and Chrome was used as a bridge for Phase 0. The native harness still
  needs to be run from a normal process on the printer’s LAN.
- K2 Plus firmware `1.1.8.0` runs Moonraker behind Fluidd at `:4408`. The real
  telemetry and camera results are in `docs/phase-0-results.md`.
- Native WebRTC reaches ICE but stalls at DTLS. The v1 camera path uses a bundled
  go2rtc helper; see `docs/decisions/0002-k2-camera-fallback.md`.
- Record the exact firmware in `docs/hardware-test-log.md` for every session.
