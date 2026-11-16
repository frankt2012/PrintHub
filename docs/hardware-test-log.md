# Hardware test log

Copy this template for each session. Record facts, not impressions. Attach a capture
bundle under `.captures/` (git-ignored).

---

## Session

| Field | Value |
|---|---|
| Date | |
| Tester | |
| Mac model / macOS | |
| Chamber build | |
| Printer | K2 Plus / K1 Max |
| Printer firmware | |
| `model` / `modelVersion` | |
| Network | Wi-Fi / Ethernet, VLAN, AP isolation? |
| Printer IP | |
| Scenario | first connect / print / pause / complete / error / reboot / sleep-wake |

## Connectivity

| Check | Result | Notes |
|---|---|---|
| WS `:9999` handshake with `wsslicer` | | |
| First JSON frame | | |
| Heartbeat round-trip | | time |
| `ReqPrinterPara` reply | | |
| `reqPrintObjects` reply | | |
| `boxsInfo` reply | | |
| Reconnect after 30 s silence | | |
| IP change / DHCP | | |
| Concurrent clients | | |

## Camera

| Check | Result | Notes |
|---|---|---|
| Mode detected | MJPEG / WebRTC | |
| Endpoint | | |
| First frame | | ms |
| Resolution / fps | | |
| Latency | | ms |
| 30-minute stability | | dropped frames |
| CPU / memory | | |
| Sleep/wake | | |
| Printer reboot | | |
| Stream while telemetry reconnects | | |

## Commands

| Command | Result | Notes |
|---|---|---|
| Pause / resume | | |
| Stop | | |
| Nozzle / bed target | | |
| Chamber target | | |
| Light | | |
| Fan | | |
| Speed / flow | | |
| Home | | |

## Telemetry observations

Paste interesting raw frames here. Note missing keys, type changes, stale values, and
model-specific quirks.

```json
{}
```

## Failures and follow-ups

| Issue | Severity | Next step |
|---|---|---|
| | | |

## Capture

- Path:
- Firmware notes:
- Repro steps:
