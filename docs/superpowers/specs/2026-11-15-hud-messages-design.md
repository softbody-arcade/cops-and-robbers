# HUD: countdowns, prep, events and round result (short design)

## Intent
Move the round's live information from toasts into the HUD app, so wheel players read everything in one place at bottom centre. Chat stays the scrollable record. Rare system warnings stay toasts. This was approved by the user ("In the HUD, go ahead with your proposal").

## What moves into the HUD (only while the app is placed; toasts remain the fallback)
- **Countdowns:** "RUNNER STARTS IN 3", "COPS RELEASED IN 7" and "CRASH PENALTY 10", shown with a large number.
- **GO flashes:** "GO! RUN!" for the runner, "GO!" for cops at release, and "PENALTY OVER" each show for 2 s.
- **Prep line:** role and car name, plus "waiting for /cnr go". It replaces the prep toast.
- **Reset feedback:** pressing a reset button when it is not allowed highlights the status line's reset part for 1.5 s. It replaces the toast.
- **Last-seen pings:** no toast while the HUD is placed. The status line already shows the info.
- **Event line:** the latest notices ("Bob: crash penalty 10s", "AI red crashed: penalty") are shown for 4 s, at most 2 at a time.
- **Result card:** shown for 10 s after a round ends. It contains:
  - the title ("RUNNER CAUGHT", "ROUND ENDED", "ESCAPED", "RUNNER LEFT" or "ROUND CANCELLED")
  - the runner and their time
  - the catchers
  - the top 3 for the map, sent by the server after the run is recorded
  - "Next round in N" when auto rounds are on.

## Stays
- **Chat:** command replies, and the round record (results, leaderboard, illegal resets, teleports, penalties).
- **Toasts:** missing reset binding, outdated client version, BeamNG.Earth API missing, spawn failure, no road found, teleport blocked.

## Clean-up
Remove the dead `cnr_restoreConfig` client handler and toast. The server no longer sends it since the hotfix.

## Changes
- **Server:**
  - `cnr_roundEnd` gets `autoNextSeconds` when an automatic next round is scheduled.
  - After a run is recorded, a new `cnr_top` event goes to everyone with the top 3 lines for the map.
- **`hud.lua` (pure):** `payload` takes these extra inputs:
  - `info.timer = {label, endsAt}`
  - `info.flash = {text, untilT}`
  - `info.prep = {role, car}`
  - `info.events = {{text, untilT}}`
  - `info.resetFlashUntil`
  - `info.result = {title, runner, time, catchers, top, untilT, nextAt}`

  It produces:
  - `banner = {label, number|nil, big}`, with the flash taking priority over the timer
  - `prep`
  - `events` (unexpired, newest 2)
  - `status.resetFlash`
  - `result` (with `nextIn`)
  - `visible`, which is also true while the result card is showing.
- **Client:** feeds these inputs, and suppresses the corresponding toasts while the HUD is placed. The car name comes from the model's `Brand` and `Name` (`core_vehicles.getModel`).
- **Vue app:** renders the banner, prep line, event lines and result card above the status row and catch bar. The default placement grows to 520×170 px with content anchored to the bottom, so empty space stays transparent.
- **Version:** 1.4.0.

## Approaches
- **In the existing HUD (chosen by the user):** one app and one place to look.
- **A separate big centred countdown app:** more prominent, but a second auto-placed app that covers the road. Rejected.

## Left to the builder
Exact styling, and the layout order inside the app.
