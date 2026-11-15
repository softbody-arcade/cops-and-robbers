# HUD Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Countdowns, GO flashes, the prep line, reset feedback, event lines and a round result card in the HUD app, with toasts only as the fallback.

**Architecture:** The server adds `autoNextSeconds` to `cnr_roundEnd` and sends a new `cnr_top` event after recording a run. The pure `hud.lua` turns the client inputs into display fields (unit-tested). The client feeds those inputs and suppresses the matching toasts while `hudPlaced`. The Vue app renders the new fields.

**Tech Stack:** Lua 5.3 (server), LuaJIT subset (client), Vue 3 SFC, `make test`.

**Spec:** `docs/superpowers/specs/2026-11-15-hud-messages-design.md`

## Global Constraints
- Toasts stay whenever the HUD is not placed (`hudPlaced == false`). Chat messages are unchanged.
- Flash duration is 2 s. Events show for 4 s, at most 2, newest first. Reset highlight is 1.5 s. The result card shows for 10 s.
- Banner labels, exactly: `RUNNER STARTS IN`, `COPS RELEASED IN`, `CRASH PENALTY`. Flash texts: `GO! RUN!`, `GO!`, `PENALTY OVER`.
- Result titles: `RUNNER CAUGHT` (caught), `ROUND ENDED` (called), `ESCAPED` (escaped), `RUNNER LEFT` (disconnect), `ROUND CANCELLED` (cancelled).
- The default HUD placement becomes 520×170 px (bottom 70px, centred as before).
- Version 1.4.0.

## Review Focus
1. A countdown that has reached 0 must not show "0". The banner disappears once `endsAt` has passed (test in Task 2).
2. A round ending while a flash or event is showing: the result card takes the space and the old events are cleared (test in Task 2).
3. A test round has no recorded run, so there is no `cnr_top`. The result card must render without a top list (test in Task 2).
4. An auto round starting before the 10 s card expires: the new prep replaces the card (test in Task 2).
5. Joining mid-round: the HUD shows what applies right away (manual in Task 4).

---

### Task 1: Server: `autoNextSeconds` and `cnr_top`

**Files:** Modify `server/CopsAndRobbers/main.lua` (the `roundEnd` and `record` effects). Test: `tests/test_main.lua`.

- [ ] **Step 1: Failing tests**

```lua
test("roundEnd carries autoNextSeconds when an auto round is scheduled", function()
  local env = boot({ config = '{"autoNextRound": true, "autoNextDelaySeconds": 5}' })
  env.startRound(); env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick"); if env.lastSent("cnr_roundEnd") and env.lastSent("cnr_roundEnd").data:find("caught", 1, true) then break end end
  assertEq(env.lastSent("cnr_roundEnd").data:find('"autoNextSeconds":5', 1, true) ~= nil, true)
  env.cleanup()
end)

test("a recorded run sends the top 3 for the map", function()
  local env = boot()
  env.startRound(); env.go()
  for _ = 1, 90 do env.clock = env.clock + 0.25; env.call("cnr_tick") end
  local top = env.lastSent("cnr_top")
  assertEq(top.pid, -1)
  assertEq(top.data:find("1. Reinder", 1, true) ~= nil, true)
  env.cleanup()
end)
```

- [ ] **Step 2:** `make test` → both tests fail.
- [ ] **Step 3:** Implement:
  - In the `roundEnd` effect, compute `autoNextSeconds = cfg.autoNextDelaySeconds` when an auto round is scheduled (same condition as today), and pass it in the payload.
  - In the `record` effect, after saving: `send(-1, "cnr_top", { lines = leaderboard.formatTop(board, 3, mapName) })`.
- [ ] **Step 4:** `make test` → all pass.
- [ ] **Step 5:** Commit `feat: roundEnd autoNextSeconds and cnr_top`.

---

### Task 2: `hud.lua` display fields

**Files:** Modify `client/lua/ge/extensions/copsAndRobbers/hud.lua`. Test: `tests/test_hud.lua`.

**Interfaces (additions to `hud.payload(state, now, info)`):**
- Inputs:
  - `info.timer = {label, endsAt}`
  - `info.flash = {text, untilT}`
  - `info.prep = {role, car}`
  - `info.events = {{text, untilT}, ...}` (oldest first)
  - `info.resetFlashUntil`
  - `info.result = {title, runner, time, catchers (string|nil), top ({string}|nil), untilT, nextAt|nil}`
- Outputs:
  - `banner`:
    - a flash shown until `untilT` gives `{label = flash.text, big = true}`
    - otherwise a timer with `endsAt > now` gives `{label, number = ceil(endsAt - now), big = true}`
    - otherwise `nil`
  - `prep`: `{role = "RUNNER"|"COP", car}` or `nil`
  - `events`: the newest unexpired 2, as plain strings, newest first
  - `status.resetFlash`: `now < resetFlashUntil`
  - `result`: while `now < untilT`, `{title, runner, time, catchers, top, nextIn = ceil(nextAt - now) or nil}`. While a result is shown: `visible = true`, and `banner`, `events` and `status` are `nil`.
  - `visible` is true when `info.active` or a result is shown.

- [ ] **Step 1: Failing tests** (append to `tests/test_hud.lua`)

```lua
test("timer banner counts down and disappears at zero", function()
  local s = hud.new()
  local p = hud.payload(s, 10.2, { active = true, role = "cop", timer = { label = "COPS RELEASED IN", endsAt = 17 } })
  assertEq(p.banner.label, "COPS RELEASED IN"); assertEq(p.banner.number, 7)
  assertEq(hud.payload(s, 17.0, { active = true, role = "cop", timer = { label = "COPS RELEASED IN", endsAt = 17 } }).banner, nil)
end)

test("flash beats the timer and expires", function()
  local s = hud.new()
  local info = { active = true, role = "runner", flash = { text = "GO! RUN!", untilT = 5 }, timer = { label = "COPS RELEASED IN", endsAt = 11 } }
  assertEq(hud.payload(s, 4, info).banner.label, "GO! RUN!")
  assertEq(hud.payload(s, 4, info).banner.number, nil)
  assertEq(hud.payload(s, 5, info).banner.label, "COPS RELEASED IN")
end)

test("prep line and reset flash", function()
  local s = hud.new()
  local p = hud.payload(s, 1, { active = true, role = "runner", prep = { role = "runner", car = "Gavril D-Series" } })
  assertEq(p.prep.role, "RUNNER"); assertEq(p.prep.car, "Gavril D-Series")
  local q = hud.payload(s, 1, { active = true, role = "cop", chaseStart = 0, resetFlashUntil = 1.5 })
  assertEq(q.status.resetFlash, true)
  assertEq(hud.payload(s, 2, { active = true, role = "cop", chaseStart = 0, resetFlashUntil = 1.5 }).status.resetFlash, false)
end)

test("events: newest two unexpired, newest first", function()
  local s = hud.new()
  local p = hud.payload(s, 10, { active = true, role = "cop", events = {
    { text = "a", untilT = 9 }, { text = "b", untilT = 12 }, { text = "c", untilT = 13 }, { text = "d", untilT = 14 } } })
  assertEq(#p.events, 2); assertEq(p.events[1], "d"); assertEq(p.events[2], "c")
end)

test("result card replaces everything for its time and counts down to the next round", function()
  local s = hud.new()
  local info = { active = false, events = { { text = "x", untilT = 99 } }, flash = { text = "GO!", untilT = 99 },
    result = { title = "RUNNER CAUGHT", runner = "Reinder", time = "4:12", catchers = "Bob", untilT = 20, nextAt = 25.2 } }
  local p = hud.payload(s, 12, info)
  assertEq(p.visible, true); assertEq(p.result.title, "RUNNER CAUGHT"); assertEq(p.result.nextIn, 14)
  assertEq(p.banner, nil); assertEq(p.events, nil); assertEq(p.result.top, nil)
  assertEq(hud.payload(s, 20, info).visible, false)
end)
```

Review Focus #4 (new prep replaces the card) is the client's job: it clears `result` on `cnr_roundSetup` (Task 3).

- [ ] **Step 2:** `make test` → the new tests fail.
- [ ] **Step 3:** Implement per the interface, in the LuaJIT subset.
- [ ] **Step 4:** `make test` and `luajit tests/run.lua tests/test_hud.lua` → all pass.
- [ ] **Step 5:** Commit `feat: HUD model for countdowns, flashes, prep, events and result`.

---

### Task 3: Client wiring

**Files:** Modify `client/lua/ge/extensions/copsAndRobbers.lua`.

- [ ] **Step 1: Keep HUD inputs in client state.**
  - `startTimer(seconds, label)` also sets `hudTimer = {label = <banner label>, endsAt}`. The labels map to the Global Constraints:
    - "Runner starts in" → `RUNNER STARTS IN`
    - "Cops released in" → `COPS RELEASED IN`
    - "Crash penalty" → `CRASH PENALTY`
  - Flashes:
    - `onRunnerGo` (runner) sets the flash `GO! RUN!`.
    - `onRelease` (cop) sets the flash `GO!`.
    - `onPenaltyEnd` sets the flash `PENALTY OVER`.
  - `onRoundSetup` sets `hudPrep = {role, car = carName(model)}` and clears `hudResult`. `hudPrep` is cleared on `onCountdown`. `carName` uses `core_vehicles.getModel(model).model` `Brand .. " " .. Name`, falling back to the model key.
  - `onNotice`, and the AI-penalty case, append `{text, untilT = clock + 4}` to `hudEvents`.
  - `requestReset` when not allowed sets `hudResetFlashUntil = clock + 1.5`.
  - `onRoundEnd` builds `hudResult`: title per Global Constraints, runner, `formatTime`, catchers joined with ", ", `untilT = clock + 10`, `nextAt = clock + autoNextSeconds` when present. It also clears the timer, flash and events.
  - `cnr_top` sets `hudResult.top = lines` when a result is showing.
- [ ] **Step 2: Payload and toasts.** Pass all of these to `hud.payload`. Keep pushing at 0.1 s while `active` or while a result shows. Suppress, when `hudPlaced`:
  - the countdown toast in `onUpdate`
  - the GO and penalty-over toasts
  - the prep toast
  - the last-seen toasts
  - the notice and AI-penalty toasts
  - the round-end toast
  - the not-allowed reset toast
- [ ] **Step 3: Clean-up.** Remove `onRestoreConfig`, its `AddEventHandler`, and the "Only paint can be changed…" toast.
- [ ] **Step 4:** `luajit -bl` on all client files → OK. `make test` → all pass.
- [ ] **Step 5:** Commit `feat: client feeds countdowns, flashes, prep, events and result to the HUD`.

---

### Task 4: Vue rendering, placement size, version, docs, deploy

**Files:**
- Modify `client/ui/modules/apps/CopsAndRobbersHud/app.vue` and `app.json` (css height 170px), and `HUD_PLACEMENT` height in the client.
- Version bump to 1.4.0 in the server, the client, `mod_info` and the version tests.
- `README.md`, `docs/FEATURES.md`.

- [ ] **Step 1:** In `app.vue`, render these elements, top to bottom inside the bottom-anchored column:
  - the result card: title, runner and time, "Caught by …", the top list, "Next round in N"
  - otherwise:
    - the banner: label, plus a large number when present
    - the prep line
    - the event lines
    - the status row, with the `.reset-flash` class on the reset item while `status.resetFlash`
    - the catch bar
  - Same panel style as today.
- [ ] **Step 2:** `make package` → the zip contains the updated app. Bump the version to 1.4.0, then `make test` → all pass. Update the docs (HUD section).
- [ ] **Step 3:** Commit `feat: 1.4.0 - countdowns, prep, events and round result in the HUD`, then `make deploy` → the log shows `Cops and Robbers 1.4.0 loaded`.
- [ ] **Step 4: Manual check with the user.**
  - `/cnr test runner`: prep line → "RUNNER STARTS IN 3…" → "GO! RUN!" → "COPS RELEASED IN 7…" → status → catch bar → result card for 10 s.
  - Toasts appear only when the HUD has been removed from the layout.
