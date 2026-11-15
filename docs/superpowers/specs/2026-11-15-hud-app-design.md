# HUD app: status line + catch bar (short design)

## Intent
A first, deliberately simple in-game UI for Cops and Robbers. It previews what a real UI can look like. It replaces two of the toast messages that players on wheels currently have to read: the status line and the catch percentage.

## Goals
- One UI app placed automatically at **bottom centre** on join. No setup is needed by players.
- **Status line:** role, survival time since release, reset status, and distance info.
- **Catch bar:** visible only while the catch timer is above 0. It shows the actual percentage in 1% steps and moves smoothly.

## Non-goals (for now)
- Countdowns, round-end screens, notices and leaderboards stay as toasts or chat.
- No interactive controls. The keybindings are the controls.
- No Vue or BeamNG component library.

## Behaviour
- **Placement:**
  - On join, after a short delay so BeamNG.Earth's MP layout switch has happened, the app is added to the current layout with `ui_appLayouts.addApp(currentLayout.filename, <app>, placement)` if it is not already in it. The placement is bottom centre, about 520×90 px.
  - The player may move or resize it afterwards.
  - On leaving the server (`onClientEndMission` / extension unload) the app is removed from the layout again.
- **Visibility:** the app is hidden when no round is running for this player.
- **Status line** (only while the chase is running): `ROLE  m:ss  |  reset status  |  distance info`.
  - Reset status: `Reset OK`, the server hint (`Stay still 4s to reset`, `Can't reset while being caught`, …) or `Penalty`.
  - Distance info: `Runner 640 m NE`, `Runner 2.4 km by road NE` on BeamNG.Earth, or `Nearest cop 230 m` for the runner.
  - The toast version of the status line is no longer shown while the app is active.
- **Catch bar:** shown while progress is above 0.
  - Runner: red, labelled "BEING CAUGHT". Cops: blue, labelled "HOLDING RUNNER".
  - The label includes an integer percentage.
  - Between server updates (4 per second) the bar is extrapolated from the last change, so it fills and drains smoothly.
  - The catch toast is no longer shown while the app is active.

## Changes
- **Server:** catch progress in `cnr_state` is rounded to 0.01 instead of 0.05, so state updates go out every tick while someone is held.
- **Client Lua:** pushes `guihooks.trigger("CnRHud", {...})` about 10 times per second while active, and once with `visible = false` when inactive. It also does the auto-placement and removal.
- **UI app:** `ui/modules/apps/CopsAndRobbersHud/` with `app.json`, `app.js` (an Angular directive listening to `CnRHud`) and `app.png`. It uses plain HTML/CSS, has a dark translucent panel and high-contrast text, and its size follows the app box.

## Approaches considered
- **Angular UI app (chosen, Claude's call):** proven for mods for years, plain HTML/CSS/JS, and 68 of the 108 built-in apps still use it.
- **Vue UI app:** the game's current system, with a new runtime loader for mods in 0.40. It cannot be tested here, so it is kept for later and bigger UIs.
- **ImGui window:** needs no layout, but looks like a developer tool. Rejected for a polished HUD.

## Left to the builder
- The exact CSS and sizes, and the app's preview image.
- How app names map to `addApp`, to be verified against `ui/apps.lua`.
- Fallback: when the app cannot be added (no layout), the toast status line and catch toast stay.
