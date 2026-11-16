# ADR 0002 — K2 camera transport fallback

- **Status:** Accepted
- **Date:** 2026-11-16
- **Context:** K2 Plus, firmware 1.1.8.0, `192.168.1.50`

## Finding

The K2 camera at `http://192.168.1.50:8000/call/webrtc_local` works:

- Chrome negotiated the camera and played **1920 × 1080 at 15 fps** with zero
  dropped frames.
- go2rtc 1.9.15, run as a child of a permissioned macOS app bundle, negotiates the
  same camera and re-publishes it to a local browser page.

The native WebRTC client does **not** work with this printer:

- Signalling succeeds; the printer returns a valid answer.
- ICE reaches `connected` / `completed` with a selected UDP candidate pair.
- DTLS stays `connecting`; the client retransmits ClientHello and receives no
  response (transport `bytes=0`, no RTP).
- The same failure occurs with WebRTC M157 and M139, with TCP candidates enabled
  and disabled, and after closing all Chrome sessions.
- The printer's answer is `a=setup:passive`; the native client correctly starts
  DTLS as `active=1 role=client`.

go2rtc HLS was tested as a native AVPlayer path, but its playlist produced only
two 0.5 s segments and did not stay live; AVPlayer showed one frame and stalled.

**go2rtc's own WebRTC page works in Chrome, Safari, and WKWebView**, at low
latency and 1920 × 1080.

## Decision

Use **go2rtc as a bundled helper** for K2 cameras in v1.

- go2rtc handles the Creality WebRTC source (`#format=creality`) and serves a
  local WebRTC page.
- The app uses a **WKWebView camera surface** pointed at
  `http://127.0.0.1:1984/stream.html?src=k2&mode=webrtc&background=false`.
  Native chrome surrounds it; CSS injection hides the web player controls.
- go2rtc's RTSP and WebRTC listeners are bound to **127.0.0.1 only**, so there is
  no macOS firewall prompt and no LAN listener.
- Keep the direct native WebRTC code as an experimental path. Revisit it after v1
  or when the printer DTLS failure is understood.

## Consequences

- The app bundle grows by ~20 MB (go2rtc) and gains a helper process.
- Direct/notarized distribution is the natural path; Mac App Store packaging would
  need the helper audited or removed.
- The camera surface is a web view rather than `AVPlayerLayer`. This is a v1
  compromise for reliable video; the controls and layout remain native.
- Future options, in order:
  1. go2rtc WebRTC → native WHEP client (standard peer, likely avoids the
     printer's DTLS quirk);
  2. continue debugging native DTLS against the printer;
  3. ffmpeg-assisted MJPEG with a working SPS/PPS path.
- K1-family cameras remain native MJPEG; go2rtc is only needed for K2 WebRTC.
