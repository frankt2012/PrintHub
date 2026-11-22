# 0003 — Read-only CFS support

## Status

Accepted for 0.2.0.

## Context

The K2 Plus reports CFS data through Moonraker at
`/printer/objects/query?box`. The same data is not reliably present on the
printer WebSocket at port 9999. Captures from firmware 1.1.8.0 show:

- `state` is `connect` when a CFS is attached.
- `T1`–`T4` describe up to four CFS units; unused units report `state: None`.
- Slot arrays (`color_value`, `material_type`, `remain_len`) are indexed A–D,
  with `-1` used for empty or unreported values.
- Loaded slots also appear in `same_material` as
  `[material_id, color, [slot_names], material_name]`.
- `remain_len` reports `0` for loaded slots on the tested unit, so `0` cannot
  be treated as "empty" or "0 mm remaining".
- Material IDs are numeric strings (`000001` = PLA in the capture). Other IDs
  are not documented and must not be guessed.

## Decision

PrintHub reads CFS data every 15 seconds and presents it as information only:

- One panel per reported unit, with temperature and humidity when present.
- Four slots per unit with material, color swatch, and remaining length.
- Empty slots are shown as `Empty`; they are not editable.
- Unknown material IDs are shown as `Material <id>`.
- `remain_len` of `0` or `-1` is treated as unreported and hidden.
- Failure to reach Moonraker leaves the last known snapshot in place and never
  affects printer control or the active print.

PrintHub does not write CFS state, change materials, or trigger filament
loading/unloading in this release.

## Consequences

- CFS information depends on Moonraker being reachable on port 4408.
- The panel will need updated parsing if Creality documents more material IDs
  or changes the `box` object.
- Read-only behavior keeps the feature safe to use during an active print.
