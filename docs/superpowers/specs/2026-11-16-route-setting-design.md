# Route to the runner: a cop setting

Status: short design for review, 2026-11-16. Adds a third setting to the player settings card (`2026-11-16-player-settings-design.md`). Built after the sky polish branch merges, because both touch `copsAndRobbers.lua` and the settings card.

## Why
- Today every cop gets a route to the runner: a line on the road and the minimap, or a BeamNG.Earth GPS destination.
  - It comes with every last-seen ping, and every second while any cop sees the runner.
  - It is cleared (and the chase line shows IN SIGHT) once the cop is close enough to see the runner themselves.
- Some players want more help, some want less. The choice should be the player's own.

## Goals
- A setting **Route to the runner**, as a cop, with three choices:
  - **Always:** the route also stays while you see the runner yourself. The IN SIGHT tag still shows, and the route keeps following the runner's position every second.
  - **Out of sight (default):** today's behaviour, unchanged.
  - **Never:** no route line and no GPS destination at all. The chase line still shows the distance and direction (`Runner seen 640 m NE`).
- Saved in the player's own game (`settings/cnr_settings.json`, key `route`), like the two switches. It applies on every server.

## Non-goals
- A host switch. The choice only gives a player less help, or the route they'd have anyway while seeing the runner, so it can't be used against anyone.
- Changing it during a chase. The card opens in the lobby and in prep only, as today.
- Any server change. The server already sends the runner's position with its IN SIGHT updates (`main.lua` sends `pos` or `geo` with `route = false`).

## Approaches
- **Client-only, decided in `onLastSeen` (picked).** The client already decides what to draw from each update, so the setting is one more input there.
- **The server sends routes per player setting.** This would need the setting on the server and a round trip, for no gain. Rejected.

## Design
- **Settings store:**
  - `playerSettings` gains a choice key `route` with the values `"always"`, `"sight"` and `"never"`, defaulting to `"sight"`.
  - A missing or unknown value loads as `"sight"`.
  - `set` takes only those three values for `route`; the switches stay booleans.
  - The card sends `{ action = "setting", key = "route", value = "always" | "sight" | "never" }`.
- **The card:**
  - one more row under Siren: **Route to the runner**, sub-text "As a cop"
  - a three-way choice with the labels **Always**, **Out of sight** and **Never**: three small buttons in a row, the chosen one highlighted
  - the HUD payload's `settings` block carries `route`
- **`onLastSeen`**, by setting:
  - **sight:** exactly today's code.
  - **always:** an update with `route == false` still sets the route to the position sent: `core_groundMarkers.setPath`, or the Earth GPS through `geo.setGpsTarget`. It also shows the distance and direction with the IN SIGHT tag instead of clearing them.
  - **never:**
    - never calls `setPath` or `geo.setGpsTarget`
    - clears any route left from before (`geo.clearRoute`) once
    - shows the straight-line distance and direction on every update, on BeamNG.Earth too, where the by-road distance needs a GPS target
    - an update with `route == false` still shows IN SIGHT, as today
- **Runner and practice:** the runner never gets routes, so the setting does nothing for them. Practice rounds as a cop follow it like real rounds.
- **Text that changes:**
  - How to play's cop lines mention the setting
  - the README and FEATURES player-settings entries list it
  - DEPENDENCIES: nothing new (the same `setPath` and Earth GPS calls)

## Tests
- **Settings store:** loading gives `"sight"` by default and for unknown values; `set` accepts the three values and refuses others; the file round-trips.
- **Client:**
  - **Out of sight:** a live update with `route = false` clears the route and shows IN SIGHT, as today.
  - **Always:** the same update sets the route (a `setPath` call with the position) and shows IN SIGHT with the distance.
  - **Never:** a last-seen ping and a live update make no `setPath` call and still show `Runner seen … N` and `Runner … N`. Switching to Never with a route set clears it.
  - **BeamNG.Earth with Never:** no `gpsSet` call; the straight-line distance shows.
- **HUD payload:** `settings.route` is there in lobby and round modes.

## In-game check
1. Out of sight: as today.
2. Always: the route stays on the minimap while you chase the runner in sight.
3. Never: no route line or GPS destination, and the chase line still gives the distance and direction.
4. The card still fits the HUD with the extra row.

## Calls made (not discussed, easy to change)
- **Labels:** Always, Out of sight, Never, in that order.
- **Placement:** three buttons rather than a dropdown, so the choice is one click and always visible.
- **Never on BeamNG.Earth:** shows the straight-line distance, since the by-road distance needs a GPS target.
