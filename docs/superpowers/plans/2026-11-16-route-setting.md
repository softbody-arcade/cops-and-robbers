# Route Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A cop setting "Route to the runner" (Always, Out of sight, Never) on the player settings card, saved in the player's own game, deciding whether the client draws the route.

**Architecture:**
- **Settings store:** `playerSettings.lua` gains a choice key next to its booleans.
- **Route logic:** `copsAndRobbers.lua` `onLastSeen` decides what to draw from the setting.
- **Payload:** the HUD payload carries the value.
- **Card:** `HudSettings.vue` gets a three-button row.
- The server is unchanged.

**Tech Stack:** Lua (BeamNG GE extension), Vue 3 on the game's UI kit. Tests: `make test`; UI compile check: `make vuecheck`.

**Spec:** `docs/superpowers/specs/2026-11-16-route-setting-design.md`

## Global Constraints

- **When to build:** start from main *after* the sky polish branch (`worktree-sky-transitions`) is merged.
- **Ledger:** update main's In progress entry with the branch name before entering the worktree. No version bump in the branch.
- **Setting key and values:** key `route`, values `"always"`, `"sight"` and `"never"`, default `"sight"`. A missing or unknown value loads as `"sight"`.
- **The card's message:** `{ action = "setting", key = "route", value = "always" | "sight" | "never" }`.
- **Card copy:**
  - row name **Route to the runner**, sub-text "As a cop"
  - button labels **Always**, **Out of sight** and **Never**, in that order
  - the chosen button uses `ACCENTS.main`, the others `ACCENTS.secondary`
- **Behaviour by value:**
  - **sight:** today's `onLastSeen`, unchanged.
  - **always:** a `live` update with `route == false` still sets the route to the position sent (`core_groundMarkers.setPath(target)`, or `geo.setGpsTarget(d.geo)` in geo mode). The tag is `IN SIGHT`, and `infoParts` shows the distance and direction (`{ before = "Runner", meters, after = compass }`).
  - **never:**
    - never calls `core_groundMarkers.setPath` with a target or `geo.setGpsTarget`
    - the first update of a round under Never calls `geo.clearRoute()`
    - every update shows the straight-line distance and direction (`before = "Runner seen"` for a ping, `"Runner"` for a live update), also in geo mode
    - a `live` update with `route == false` shows `IN SIGHT` with no distance, as today
- **Project style:** no code comments, no emojis.

## Review Focus

1. **A player switches to Never while a route from an earlier ping is still drawn.** The route must go. Test in Task 1: `Never clears a route left from before`.
2. **BeamNG.Earth with Never.** No GPS destination is set, and the distance still shows. Test in Task 1: `Never on BeamNG.Earth sets no GPS destination and shows the straight distance`.
3. **A broken or old settings file** (no `route` key, or `route = 5`). Out of sight, with no error. Test in Task 1: `route loads as out of sight when missing or unknown`.
4. **Always while in sight on BeamNG.Earth.** The GPS destination keeps following the runner. Test in Task 1: `Always keeps the Earth GPS destination while in sight`.

---

### Task 1: The setting and the route logic

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/playerSettings.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua` (`onLastSeen`)
- Modify: `client/lua/ge/extensions/copsAndRobbers/hud.lua` (`M.payload` settings block)
- Test: `tests/test_player_settings.lua`, `tests/test_client.lua`, `tests/test_hud.lua`

**Interfaces:**
- Produces:
  - `prefs.route` (one of the three values)
  - `playerSettings.set(prefs, "route", value) -> bool`
  - `payload.settings.route`

- [ ] **Step 1: Write the failing tests**

`tests/test_player_settings.lua`:
- `test("route loads as out of sight when missing or unknown")`:
  - `ps.load(nil).route == "sight"`
  - `ps.load({ route = 5 }).route == "sight"`
  - `ps.load({ route = "fast" }).route == "sight"`
  - `ps.load({ route = "never" }).route == "never"`
- `test("route takes only its three values")`:
  - `ps.set(p, "route", "always") == true`, and then `p.route == "always"`
  - `ps.set(p, "route", "always") == false`
  - `ps.set(p, "route", true) == false`
  - `ps.set(p, "route", "fast") == false`
  - `ps.set(p, "headlights", "never") == false`

`tests/test_client.lua`:
- Stub `_G.core_groundMarkers = { setPath = function(t) env.paths[#env.paths + 1] = t or false end }` with `env.paths = {}` in the tests below, or in `tests/client_stubs.lua` if it doesn't break other tests.
- Use the existing `copInChase(env)` helper.
- `test("out of sight clears the route when you see the runner, as today")`:
  - a live update `{ live = true, route = true, pos = { x = 0, y = 640, z = 0 } }` adds a path
  - then `{ live = true, route = false, pos = { x = 0, y = 100, z = 0 } }` gives tag `IN SIGHT`, `status.info == nil`, and a final `env.paths` entry of `false` (cleared)
- `test("always keeps the route while you see the runner")`:
  - files `{ route = "always" }`
  - the `route = false` update adds a path to `(0, 100, 0)` and leaves no `false` after it
  - tag `IN SIGHT`, `status.info.before == "Runner"`, `status.info.dist == "100 m"`
- `test("never draws no route and still shows distance and direction")`:
  - files `{ route = "never" }`
  - a ping `{ pos = { x = 0, y = 640, z = 0 } }` adds no path with a target
  - `status.info.before == "Runner seen"`, `dist == "640 m"`, `after == "N"`
  - a live update `{ live = true, route = true, ... }` likewise adds none and shows `before == "Runner"`
- `test("Never clears a route left from before")`:
  - start on Out of sight, ping once (path set)
  - `env.M.ui({ action = "setting", key = "route", value = "never" })`, ping again
  - the last `env.paths` entry is `false`, and no later target was set
- `test("Never on BeamNG.Earth sets no GPS destination and shows the straight distance")`:
  - `env.fire("cnr_mode", { geo = true })` with a `beamngEarth_api` stub like the existing `geo.gpsInfo` tests, counting `gpsSet` calls
  - files `{ route = "never" }`, a cop chase
  - `cnr_lastSeen` with `{ geo = { lat = 640, lon = 0, h = 0 } }`
  - `gpsSet` was never called, and `status.info.meters`-based `dist == "640 m"`
  - restore `beamngEarth_api = nil`
- `test("Always keeps the Earth GPS destination while in sight")`: geo mode with `{ route = "always" }`. A live update with `route = false` and `geo` calls `gpsSet` once more.

`tests/test_hud.lua`:
- `payload.settings.route == "sight"` when `info.settings` has none
- `"never"` when `info.settings.route == "never"`

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `lua tests/run.lua tests/test_player_settings.lua tests/test_client.lua tests/test_hud.lua`
Expected: FAIL on the new tests.

- [ ] **Step 3: Implement**

- `playerSettings.lua`: a choice table `CHOICES = { route = { always = true, sight = true, never = true } }` with default `"sight"`. `load` and `set` handle choices next to the booleans; booleans still accept only booleans.
- `copsAndRobbers.lua` `onLastSeen`: branch on `prefs.route` exactly as Global Constraints says.
  - Keep a local `routeCleared` flag, reset in `onRoundSetup`, so Never clears once per round. It also clears again after the value changes to Never mid-round.
  - The straight-line distance and direction are the same `here:distance(target)` and `geo.compass` the non-Earth path uses today.
- `hud.lua`: `settings.route = (prefs.route == "always" or prefs.route == "never") and prefs.route or "sight"`.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `make test`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/playerSettings.lua client/lua/ge/extensions/copsAndRobbers.lua client/lua/ge/extensions/copsAndRobbers/hud.lua tests/test_player_settings.lua tests/test_client.lua tests/test_hud.lua
git commit -m "feat: route to the runner as a cop setting: always, out of sight or never"
```

### Task 2: The card row and the docs

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue` (a row under Siren)
- Modify: `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue` (the settings line)
- Modify: `README.md` and `docs/FEATURES.md` (the Player settings entries)

**Interfaces:**
- Consumes:
  - `settings.route` (Task 1)
  - the card's existing `emit('setting', key, value)`, which `app.vue` forwards as `ui({ action: 'setting', key, value })`

- [ ] **Step 1: The row**

- Under the Siren row, in the same `.row` and `.label` markup: name **Route to the runner**, `.desc` "As a cop".
- Instead of a switch, three `BngButton`s (`cnr-btn`) labelled Always, Out of sight and Never, in that order.
  - The one whose value equals `settings.route` uses `ACCENTS.main`, the others `ACCENTS.secondary`.
  - Clicking emits `setting('route', value)`, with values `always`, `sight` and `never`.
- Keep the row's height close to the switch rows; the card must still fit (in-game check).

- [ ] **Step 2: Docs**

- How to play's settings line adds: "as a cop, how the route to the runner is shown (always, only out of sight, or never)".
- README and FEATURES Player settings entries list **Route to the runner** with the three choices and Out of sight as the default.

- [ ] **Step 3: Verify**

Run: `make test && make vuecheck`
Expected: `0 failed`; vuecheck ok.

- [ ] **Step 4: Commit**

```bash
git add client/ui/modules/apps/CopsAndRobbersHud/HudSettings.vue client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue README.md docs/FEATURES.md
git commit -m "feat: the settings card offers the route to the runner"
```

### Task 3: Merge and deploy

The controller does this with the user, after the final whole-branch review: merge into main, bump the version, install on the local server for the user's in-game check (the spec's list), and deploy when the user says so.
