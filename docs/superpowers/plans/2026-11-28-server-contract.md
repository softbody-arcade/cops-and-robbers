# Split step 2: the server contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put Cops and Robbers' server half behind a game interface (hooks plus services), move the remaining manager parts to `server/CopsAndRobbers/arcade/`, and leave `main.lua` as wiring, with every golden trace unchanged.

**Architecture:** First the services the contract needs become their own `arcade/` modules behind today's callers: vectors, traffic slots, safe saves, the settings service, the round-car registry and parking. Then Cops and Robbers' effect handling moves into `cnr/game.lua` intact, and its branches switch to service calls. Last, `arcade/cycle.lua` takes the lobby/round/results cycle, the tick, start and finish, and every BeamMP entry point. A fake game in the tests proves the contract fits a second game. The golden traces gate every task.

**Tech Stack:** Lua 5.3 (BeamMP Server 3.9.3; CI runs `lua5.3`), the repo's `tests/run.lua` runner (`make test` runs `tests/test_*.lua`), the server boot in `tests/server_boot.lua`, and the golden traces in `tests/traces/`.

**Spec:** [docs/superpowers/specs/2026-11-28-server-contract-design.md](../specs/2026-11-28-server-contract-design.md) (approved 2026-11-28; decisions on #72). It argues from the arcade manager spec, arcade-base `docs/superpowers/specs/2026-11-27-arcade-manager-design.md`. Ticket: #72, with #92 folded in.

## Global Constraints

- Every golden trace in `tests/traces/` matches after every task. A mismatch is a bug in the task, never a reason to re-record. Gate with `git diff --exit-code <plan commit> -- tests/traces` and `make test`.
- Behaviour changes allowed, only as the spec's "Behaviour change" section says:
  - a round keeps the settings snapshot taken at its start;
  - an automatic-rounds toggle keeps a host's disk edit;
  - a failed save never loses a file (#92).
- New and moved server modules live in `server/CopsAndRobbers/arcade/`, required as `arcade.<name>`. An `arcade.*` module never requires `cnr.*`.
- No module-level state in `arcade/` or `cnr/`, except the grid and rebuild counters in `cnr/round.lua` (spec: Ordering). Services with state are built with `new(...)` from `main.lua`.
- Events keep their `cnr_` names and payloads. No client file changes.
- Server Lua stays within Lua 5.3. No source comments. Version numbers stay out of commits.
- Before each commit: `make test`. Check each changed server file with `luajit -bl <file> >/dev/null`, plus `luac5.3 -p` where installed.
- Review rule: every task review also checks each hook or service the task touches against Street racing (grid, race, series, per-player upgrades) and Wheel racing (changes for everyone except last place), and flags any Cops and Robbers concept in `arcade/`.

## Review Focus

- **A hot reload mid-round** (top-level `main.lua` re-run): fresh services and a fresh game, one timer, start-up messages again, and grid and rebuild IDs that never repeat (Task 9).
- **A spawn arriving between a setup and the driver's `cnr_myVehicle`,** in a real round and in driven practice. It must neither publish a round car early nor release AI setup early (Task 4).
- **A panel save while the disk is full or the rename fails:** the original `config.json` and the live value survive, and the panel shows the error (Tasks 2, 3).
- **Disconnects at every phase:** picking, prep, chase, practice, issuer, runner, cop. The roster cleanup order and the round-car push stay as the traces show (Task 8).
- **An automatic start after the last issuer left:** the lowest player ID issues it, as today, through `ctx.round:start` with `command = "next"` (Task 7).

---

### Task 1: Vectors, traffic slots and the sit-out snapshot

**Files:**
- Move: `server/CopsAndRobbers/cnr/vec.lua` → `server/CopsAndRobbers/arcade/vec.lua` (`git mv`)
- Create: `server/CopsAndRobbers/cnr/vec.lua` (a re-export, one line: `return require("arcade.vec")`)
- Modify: `server/CopsAndRobbers/arcade/traffic.lua`, `server/CopsAndRobbers/cnr/traffic.lua`, `server/CopsAndRobbers/arcade/roster.lua`, `server/CopsAndRobbers/main.lua` (callers)
- Test: `tests/test_arcade_traffic.lua`, `tests/test_arcade_roster.lua`; the existing `cnr.vec` tests keep passing unchanged

**Interfaces:**
- Produces: `arcade.vec`, the same module `cnr.vec` is today, re-exported by `cnr.vec`.
- Produces: `traffic.whole(v) -> integer`, exported from `arcade.traffic`. `cnr/traffic.lua` uses it instead of its own copy. `arcade/traffic.lua` uses `arcade.vec.toVec` instead of its copied `isNum` and `toVec`.
- Produces: `traffic.perPlayer(setting, maxCars, reserved)`, where `reserved` is the number of car slots kept free (today `practice and 3 or 1`).
- Produces: `t:allowance(cfg, reserved, eligible)`; the unused `pid` is dropped.
- Produces: `r:sitOutSnapshot() -> { [pid] = true }`, a fresh copy.

- [ ] **Step 1: Failing tests.**
  - `perPlayer(5, 6, 3) == 3`, `perPlayer(5, 6, 1) == 5`, `perPlayer(5, nil, 3) == 5`, and `perPlayer(5, 2, 3) == 0`.
  - `t:allowance({ trafficPerPlayer = 5 }, 1, false) == 0`.
  - `traffic.whole("2.7") == 2` and `traffic.whole(-1) == 0`.
  - After `r:setSitOut(2, true)`, `r:sitOutSnapshot()` returns `{ [2] = true }`; changing the returned table doesn't change `r:sittingOut`.
- [ ] **Step 2: Run** `make test` → those tests FAIL.
- [ ] **Step 3: Implement.** Callers in `main.lua`:
  - `openTraffic` passes `current.test and pid == current.issuerId and 3 or 1`;
  - `cnr_rules` and `Round:start`'s traffic count pass `1`;
  - the start command passes `roster:sitOutSnapshot()` to `Round:start`, instead of fetching the table by its internal name.
- [ ] **Step 4: Run** `make test` → PASS; `git diff --exit-code <plan commit> -- tests/traces` → empty; `grep -n "isNum\|local function toVec\|local function whole" server/CopsAndRobbers/arcade/traffic.lua server/CopsAndRobbers/cnr/traffic.lua` → only `arcade/traffic.lua`'s `whole`.
- [ ] **Step 5: Commit** with the message "arcade.vec, traffic slots and the sit-out snapshot".

### Task 2: Saves that never lose a file, the settings service, and override checks (#92, #89)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/store.lua`, `server/CopsAndRobbers/arcade/settings.lua`, `server/CopsAndRobbers/cnr/config.lua`
- Test: `tests/test_arcade_store.lua`, `tests/test_arcade_settings.lua`, `tests/test_config.lua`

**Interfaces:**
- Produces: `store.write(path, content) -> true | nil, err`.
  1. Writes `<path>.tmp`, checking `open`, `write` and `close`.
  2. Renames it over `path` only once it is complete.
  3. On any failure, removes only `<path>.tmp` and leaves `path` byte-for-byte unchanged.

  If `FS.Rename` can't replace an existing target, `store.write` moves `path` aside first, renames, and restores the old file when the rename fails. Every caller (settings, leaderboard, build, colours, stations) handles the error. Each caller logs `could not save <basename>: <err>` and keeps its in-memory state.
- Produces: the settings service `s = settings.new(path, decl, log)` with:
  - `s:load() -> cfg, warnings, raw`, as today, also kept inside `s`;
  - `s:effective() -> cfg`;
  - `s:get(key) -> value`, from the live effective settings;
  - `s:set(key, text) -> true | nil, err`. It re-reads the file and changes only `key`, dropping retired entries. A missing file starts from `{}`. An unreadable or corrupt file returns `nil, err` and writes nothing. A failed save returns `nil, err` and keeps the live value. Success updates the live effective settings.
  - `s:apply(values) -> keys | nil, err`: the panel's multi-key save, with the same failure rules;
  - `s:snapshot() -> deep copy of the effective settings` (list values copied too).
- Produces: a declaration field `RANGES = { minKey = "maxKey" }`. `merge` checks it where it called `decl.fix`, before `TIMING_RANGES`, with today's warning format `"%s (%s) is below %s, using %s"`. `combine` merges game `RANGES` like the other fields. `cnr/config.lua` declares `RANGES = { copSpawnMinMeters = "copSpawnMaxMeters" }`, and `GAME.fix` is removed.
- Produces (#89): `combine` validates every combined default with the validators `merge` uses for config values. It checks each `OVERRIDES` value's type, choices, `POSITIVE`, `MAXIMA`, `WHOLE` and list shape, and that each `RANGES` and `TIMING_RANGES` default maximum is not below its minimum. It also requires both ends of a range to have number defaults. A failure is an assertion naming the key.

- [ ] **Step 1: Failing tests** in `tests/test_arcade_store.lua`:
  - a failing write, close or rename (stub `io.open`'s file and `FS.Rename`) returns `nil, err`, leaves the original bytes, and leaves no `.tmp`;
  - a successful write replaces the content, also when `FS.Rename` refuses an existing target (the test's fake `FS.Rename` already refuses).
- [ ] **Step 2: Failing tests** in `tests/test_arcade_settings.lua`:
  - `set` keeps a key edited on disk after load;
  - `set` on a legacy file drops `clockSpeed`, `lastSeenIntervalSeconds` and the `"map"` values;
  - `set` on a corrupt or unreadable file returns `nil, err`, the file is unchanged, and `get` returns the old value;
  - a stubbed `store.write` failure makes `set` return `nil, err` and keeps `get`;
  - `snapshot()` is a deep copy: changing `snapshot().excludedModels` doesn't change `get("excludedModels")`;
  - a declaration with `RANGES` warns `copSpawnMaxMeters (10) is below copSpawnMinMeters, using 50` and fixes the value, in the same position in the warning list as `fix` did (extend `merge preserves the corrected config, warnings and their defined order`);
  - `cnr.config.declaration` contains no functions: walk the table and assert `type(v) ~= "function"`.
  - #89: `combine` fails naming the key for:
    - `OVERRIDES = { nightChancePercent = 150 }` (above its maximum);
    - `{ lightningMinSeconds = 0.5 }` (not whole);
    - `{ lightningMinSeconds = 60 }` (above `lightningMaxSeconds`' default);
    - `{ excludedModels = { a = 1 } }` (not a list);
    - a game `TIMING_RANGES` entry whose keys have no number defaults.

    `OVERRIDES = { weather = "rain" }` still passes.
- [ ] **Step 3: Run** `make test` → the new tests FAIL.
- [ ] **Step 4: Implement**, keeping every existing caller working. `main.lua`'s `readSettings`, `panelSettings` and the automatic-rounds adapter keep their current behaviour in this task; Task 3 rewires them.
- [ ] **Step 5: Run** `make test` → PASS; the golden gate is clean.
- [ ] **Step 6: Commit** with the message "Saves never lose a file; the settings service gets get, set, apply and snapshot; overrides are checked (#92, #89)".

### Task 3: The settings snapshot and the automatic-rounds toggle

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/arcade/autoRounds.lua`
- Test: `tests/test_main.lua`, `tests/test_arcade_auto_rounds.lua`

**Interfaces:**
- Consumes: the Task 2 settings service.
- Produces: `autoRounds.register(p, ctx)`, where `ctx.settings` is the settings service itself (the `{get, set}` adapter and `refreshConfig` are gone). The `auto` command calls `ctx.settings:set("autoNextRound", arg)`. On an error it replies with the error and changes nothing. On success it pushes rules and, for `off`, cancels the schedule and sends `cnr_autoNext {}`, as today.
- Produces: in `main.lua`, the settings in force: `cfg` is the live effective settings while no round runs, and the round's snapshot from round start to round end. Round end then switches `cfg` back to the live settings. `rules.payload` reads `cfg`, so `cnr_rules` follows the same switch. The round end sends `cnr_rules` to everyone only when the payload differs from the last one sent (keep the last payload's signature). The toggle and join sends stay unconditional. Automatic scheduling at round end reads `settings:get("autoNextRound")` and `settings:get("autoNextDelaySeconds")` live.

- [ ] **Step 1: Failing tests** in `tests/test_main.lua`:
  - `"a disk edit survives a mid-round auto toggle and applies from the next round"`:
    1. Start a round.
    2. Write `"headStartSeconds":9` into `env.dir .. "config.json"`.
    3. `env.panel(1, "auto on")`.
    4. Assert the file still has 9, and the running round's `cnr_rules` and setup payloads still show the old value.
    5. End the round; the next round's `cnr_rules` shows 9.
  - `"auto off mid-chase still stops the next countdown"`.
  - `"auto on with an unreadable config.json changes nothing and says so"`: make the file unreadable (replace it with a directory), toggle, and assert the reply carries the error and no `cnr_autoNext`.
  - `"a held-back change reaches players at round end once"`: two round ends with no change send `cnr_rules` once.
- [ ] **Step 2: Run** `make test` → FAIL.
- [ ] **Step 3: Implement.** `reloadRound` and `panelSettings` use the service (`settings:load()` and `settings:apply(values)`). The legacy test `a save drops retired sky settings from config.json` (`tests/test_main.lua:514`) keeps passing.
- [ ] **Step 4: Run** `make test` → PASS; the golden gate is clean (`auto_next.txt` still has the toggle's unchanged rules broadcast before `cnr_autoNext`).
- [ ] **Step 5: Commit** with the message "A round keeps its settings snapshot; the auto toggle keeps disk edits".

### Task 4: The round-car registry and parking

**Files:**
- Create: `server/CopsAndRobbers/arcade/cars.lua`, `server/CopsAndRobbers/arcade/parking.lua`
- Modify: `server/CopsAndRobbers/main.lua`
- Test: `tests/test_arcade_cars.lua`, `tests/test_arcade_parking.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `cars.new(roster, messages, traffic) -> c`. It owns today's `activeVid`, `registeredRoundCar`, `preRoundVehicles`, `lastRoundCars` and the split of `allowRoundSpawn`:
  - `c:permit(pid)`: a setup was delivered. It grants the one-use permission and marks placement pending.
  - `c:permitted(pid) -> bool` and `c:placementPending(pid) -> bool`.
  - `c:claim(pid, vid)`: a spawn the game marked `roundCar`. It uses up the permission and records the provisional car; placement stays pending. It publishes at once only if the player was already confirmed.
  - `c:confirm(pid, vid)`: `cnr_myVehicle`. It sets confirmed and clears pending, permission and pre-round exclusions.
  - `c:replacementAllowed(pid) -> bool`: confirmed and no active car.
  - `c:activeVid(pid)`, `c:confirmedVid(pid)`, `c:vidFor(pid)`, `c:firstVid(pid)`, `c:setActive(pid, vid, onReplace)`; `onReplace` is called when a confirmed car's ID changes (Cops and Robbers passes `forgetVehicleSight`).
  - `c:rememberPreRound(pid)`, `c:isPreRound(pid, vid)`, `c:forgetPreRound(pid, vid)`.
  - `c:position(owner, vid) -> { pos, vel } | nil`, using `arcade.vec`.
  - `c:publish(participants, pid?)` sends `cnr_roundCars` as `pushRoundCars` does today: sorted, de-duplicated, confirmed only, the same signature skip.
  - `c:clearPublished()` does what `clearRoundCars` does.
  - `c:clearRound()` clears the per-round tables, as round end does today.
- Produces: `parking.new(roster, messages) -> k` with `k:park(pid)`, which sends `cnr_parkBystanderCars {on=true}` and remembers the player only when delivered, `k:isParked(pid)` and `k:releaseAll()`, which sends `{on=false}` to each parked player and clears the set, in today's order.
- The game-side decisions stay in `main.lua` for now: which spawn is a `roundCar` (`matchesRoundVehicle`, `not current.test`), the issuer and the AI slots.

- [ ] **Step 1: Failing unit tests** for `cars`:
  - permission and placement are separate: `claim` uses up `permitted`, but `placementPending` stays true until `confirm`;
  - `claim` publishes only for an already confirmed player;
  - `replacementAllowed` holds after a confirmed car is deleted (`setActive(pid, nil)`);
  - `publish` sends nothing when the key list hasn't changed;
  - `clearPublished` sends `{keys = {}}` only after a non-empty publish.

  For `parking`: an undelivered park isn't remembered, and `releaseAll` sends `on=false` to each parked player once.
- [ ] **Step 2: Failing test** in `tests/test_main.lua`: `"in driven practice a spawn before cnr_myVehicle doesn't release AI setup"`:
  1. `env.panel(1, "test runner")`, pick, and let the setup go out.
  2. `onVehicleSpawn` from 1 with the round model, then tick.
  3. Assert no `cnr_setupAI` yet.
  4. Send `cnr_myVehicle`, tick, and assert `cnr_setupAI`.
- [ ] **Step 3: Run** `make test` → FAIL (the new modules don't exist).
- [ ] **Step 4: Implement** and switch `main.lua`'s callers to `cars` and `parking`. `dispatchAISetup` waits on `cars:placementPending(pid)`. The vehicle callbacks keep their exact return values and logs.
- [ ] **Step 5: Run** `make test` → PASS, including `tests/test_main.lua:2470` (deletion and reroll replacement); the golden gate is clean.
- [ ] **Step 6: Commit** with the message "arcade.cars and arcade.parking own round-car identity and parked bystanders".

### Task 5: The game object, with the effect handling moved intact

**Files:**
- Create: `server/CopsAndRobbers/cnr/game.lua`
- Modify: `server/CopsAndRobbers/main.lua`
- Test: the golden traces and `make test` (a pure move)

**Interfaces:**
- Produces: `cnr.game.new(ctx) -> game`. In this task `ctx` is a table `main.lua` builds from its locals and services. `game` owns `current` (the `cnr.round` object), `aiCars`, the AI serials, `pendingAISetup`, `aiSpawnsLeft`, `partsBaseline`, `missingCount`, `stations`, `currentBuild`, the run counts and runner keys, and `lastResult`. `game:applyEffects(effects)` is today's `applyEffects`, moved unchanged apart from reading services from `ctx`.
- `main.lua` calls `game:applyEffects(...)` wherever it called `applyEffects(...)`. Handlers still live in `main.lua` and reach game state through `game` fields or small `game:` methods, named after the old local functions.

- [ ] **Step 1: Move** `applyEffects` and the game state it touches into `cnr/game.lua`. Keep `ipairs` order and the recursive call on a failed setup.
- [ ] **Step 2: Run** `make test` → PASS; the golden gate is clean; `grep -n "e.kind ==" server/CopsAndRobbers/main.lua` → nothing.
- [ ] **Step 3: Commit** with the message "cnr.game holds the round and its effect handling".

### Task 6: Effects call manager services

**Files:**
- Modify: `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_main.lua`, the golden traces

**Interfaces:**
- Consumes: `cars`, `parking` (Task 4), the messages service, the settings snapshot (Task 3).
- Produces: inside `cnr/game.lua`, each effect kind uses only `ctx` services:
  - `setup` calls `ctx.messages.send` and, when delivered, `ctx.cars:permit(pid)`; a failed delivery runs `setupFailed` at once, as today;
  - `spectate` sends through `ctx.messages`;
  - `setupAI` uses `ctx.parking:park`, `ctx.cars:rememberPreRound` and `ctx.traffic`;
  - `roundEnd` calls `ctx.round:finish(result, audience, scheduleNext)` (below);
  - the rest keep their sends.
- Produces: `ctx.round:finish(endPayload, audience, scheduleNext)`, implemented in `main.lua` for now. In order:
  1. `parking:releaseAll()`;
  2. `cnr_roundEnd` with `endPayload` to `audience` (`-1` or the issuer);
  3. `cars:clearRound()` and the other per-round clears;
  4. `cars:clearPublished()`;
  5. schedule the next round when `scheduleNext` is true and `settings:get("autoNextRound")` is true;
  6. switch `cfg` back to live and send `cnr_rules` if it changed (Task 3).

  The `record` effect stays a separate game effect after it.

- [ ] **Step 1: Failing test** `"a practice end unparks bystanders before the issuer's roundEnd"`: in `practice_runner`-style setup with a second player, assert `cnr_parkBystanderCars {on=false}` comes before `cnr_roundEnd` to the issuer in `env.sent`.
- [ ] **Step 2: Run** → it passes today. This test pins the order before the change; that's expected.
- [ ] **Step 3: Replace** the branches one effect kind at a time, running `make test` and the golden gate after each.
- [ ] **Step 4: Run** `make test` → PASS; the golden gate is clean; `grep -n "send(\|MP\." server/CopsAndRobbers/cnr/game.lua` → nothing (all through `ctx`).
- [ ] **Step 5: Commit** with the message "Cops and Robbers' effects use the manager's services".

### Task 7: The cycle, starting and finishing a round

**Files:**
- Create: `server/CopsAndRobbers/arcade/cycle.lua`
- Modify: `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/arcade/panel.lua`
- Test: `tests/test_arcade_cycle.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `cycle.new(services) -> y`, where `services` holds messages, roster, settings, cars, parking, traffic, the panel service, autoRounds and the clock. Its methods:
  - `y:attach(game)` reads `game:manifest()`. It builds the panel allow-list from the manager's commands (`auto on`, `auto off`, `next`, `reload`) plus `manifest.commands`, and keeps `manifest.minPlayers`.
  - `y:state() -> "lobby" | "round" | "results"`.
  - `y:dispatch(hook, ...)` is the one place the manager calls the game. In this step it calls `game[hook](game, ...)` and returns its results; step 5 wraps it.
  - `ctx.round:start(request) -> true | nil, reason`, in order:
    1. `dispatch("canStart", request)`;
    2. refuse unless `prepared.solo` or `#prepared.participants >= minPlayers`;
    3. `snapshot = settings:snapshot()`;
    4. state → round;
    5. `dispatch("start", prepared, snapshot, now)`.
  - `ctx.round:finish(...)`, as in Task 6, moved here; state → results.
  - `y:startNext()` builds `request = { issuer = <today's startNext choice>, command = "next" }` and calls `ctx.round:start`.
  - `y:tick()` keeps the spec's tick order:
    1. panel and lobby pushes (`dispatch("panelState")` lazily, `dispatch("lobbyFields")`);
    2. a due automatic start;
    3. stop if not in a round;
    4. `dispatch("tick", now)`.

    The AI dispatch or timeout, the position sampling and the lightning announcement move inside Cops and Robbers' `tick`, in that order.
- Produces: in `cnr/game.lua`, the hooks `manifest()` (with `version` from `ctx.version`, `minPlayers = 1`, `commands` = today's `cnr/panel.lua` `COMMANDS` plus the `start ` prefix, and `clientEvents`), `settingsDeclaration()`, `canStart(request)`, `start(prepared, snapshot, now)`, `tick(now)`, `panelState()` and `lobbyFields()`.
  - `canStart` keeps today's start sequence and texts; `command = "next"` maps to today's `start next`.
  - The game's `start`, `test runner` and `test cop` commands call `ctx.round:start({ issuer = pid, command = <word>, text = <rest> })`.
  - Cops and Robbers' practice requests return `prepared.solo = true`.

- [ ] **Step 1: Failing unit tests** in `tests/test_arcade_cycle.lua`, with a stub game:
  - a non-solo start with fewer participants than `minPlayers` is refused and `start` is never dispatched;
  - a solo start with zero participants passes;
  - `start` receives a snapshot that later `settings:set` calls don't change;
  - `finish` moves to results, then a new start moves to round;
  - `startNext` sends `command = "next"`;
  - `tick` calls `panelState` only while someone has the panel open.
- [ ] **Step 2: Failing test** in `tests/test_main.lua`: `"watch-only practice by a sitting-out player still starts"` (pins `tests/test_main.lua:3131` through the cycle). Also: `"an automatic start after the issuer left is issued by the lowest player id"`.
- [ ] **Step 3: Run** `make test` → FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** `make test` → PASS; the golden gate is clean.
- [ ] **Step 6: Commit** with the message "arcade.cycle owns the lobby, round and results cycle".

### Task 8: Entry points through the contract

**Files:**
- Modify: `server/CopsAndRobbers/arcade/cycle.lua`, `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_main.lua`, `tests/test_arcade_cycle.lua`

**Interfaces:**
- Produces: in `arcade/cycle.lua`, handlers the wiring binds to BeamMP:
  - `y:onPlayerJoin(pid)` → `dispatch("join", pid, name, now)`. In 2.x the game's `join` sends the whole join sequence in the spec's order and calls `ctx` services for the manager's parts.
  - `y:onPlayerDisconnect(pid)`, in order: `roster:leaveEarly`, `dispatch("leave", pid, now)`, `roster:leaveLate`, `cars:publish`.
  - `y:onVehicleSpawn(pid, vid, data)` and `y:onVehicleEdited(pid, vid, data)` → `dispatch("checkVehicle", kind, pid, vid, decoded, facts)`, where `facts = { permitted, placementPending, confirmed, replacementAllowed, activeVid, preRound, trafficOpen }`. The cycle applies `allow`, `reason` and `roundCar` with the `cars` rules, returns `0` or `1`, logs refusals with today's text and rate limit, and calls `dispatch("onVehicle", "spawn"|"edit", …)` when allowed.
  - `y:onVehicleDeleted(pid, vid)` and `y:onVehicleReset(pid, vid)` → the registry updates, then `dispatch("onVehicle", "delete"|"reset", …)`.
  - `y:onPanel(pid, data)` handles `open`, `close` and the manager's commands itself. A game command passes the allow-list, then `dispatch("panelAction", pid, action, payload)`. Settings saves and reloads stay the manager's.
  - `y:onClientEvent(name, pid, data)` → `dispatch("clientEvent", name, pid, data)`, for each name in `manifest.clientEvents`.
- Produces: in `cnr/game.lua`, the hooks `join`, `leave`, `checkVehicle`, `onVehicle`, `panelAction` and `clientEvent`, holding today's Cops and Robbers logic from `main.lua`: `vehicleAllowed`'s policy, `checkParts`, colour paint, sit-out notices, grid, picked, setup, change, missing, sight, cover, stations, board, AI vehicles, traffic reports and the lightning clock.

- [ ] **Step 1: Failing tests** in `tests/test_arcade_cycle.lua`, with a stub game:
  - a refused spawn returns 1 and logs once within 10 s;
  - a `roundCar` spawn without permission is refused;
  - disconnect order: a stub `leave` sees `leaveEarly` already done and `leaveLate` not yet;
  - an unknown panel command never reaches `panelAction`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**, moving one handler group at a time, with `make test` and the golden gate after each.
- [ ] **Step 4: Run** `make test` → PASS; the golden gate is clean.
- [ ] **Step 5: Commit** with the message "BeamMP entry points reach the game only through the contract".

### Task 9: main.lua as wiring, hot reload and docs

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `tests/test_reload.lua`, `docs/DEPENDENCIES.md`, `docs/FEATURES.md` (the snapshot and save behaviour)
- Test: `tests/test_reload.lua`

**Interfaces:**
- Produces: a `main.lua` that only does this:
  1. sets `package.path`;
  2. builds the services, the cycle and `cnr.game.new(ctx)`;
  3. loads data;
  4. binds BeamMP's handler names: the `cnrOn*` globals, each one line calling the cycle;
  5. starts the 250 ms timer;
  6. sends the start-up messages.

- [ ] **Step 1: Failing test** in `tests/test_reload.lua`: `"grid and rebuild ids from before a reload don't complete the current ones"`:
  1. Boot, start an evolving round, and start a rebuild.
  2. `env.reload()`.
  3. Start a new round and rebuild.
  4. Send `cnr_myVehicle` with the old rebuild ID.
  5. Assert the current rebuild is still pending (no `cnr_applied`), and that the rest of the report (car registered, `cnr_roundCars`) behaves as today.

  Do the same for a stale grid ID with `cnr_startGrid`.
- [ ] **Step 2: Run** → FAIL only if the counters reset. If it passes at once, keep it as a pin and say so in the report.
- [ ] **Step 3: Implement** the wiring. Checks:
  - `grep -n "current:\|e.kind\|cnr\." server/CopsAndRobbers/main.lua` shows only the `require("cnr.game")` and `require("cnr.config")` lines;
  - `grep -rn 'require("cnr' server/CopsAndRobbers/arcade/` prints nothing;
  - `wc -l server/CopsAndRobbers/main.lua` is under 200.
- [ ] **Step 4: Docs.**
  - `docs/DEPENDENCIES.md`: the arcade section names `cycle`, `cars`, `parking` and `vec`, and says `main.lua` is wiring.
  - `docs/FEATURES.md`: a round uses the settings from its start; the auto toggle keeps disk edits; a failed save keeps the file.
- [ ] **Step 5: Run** `make test`, `make vuecheck` and `make package` → PASS; the golden gate is clean.
- [ ] **Step 6: Commit** with the message "main.lua is wiring; reload keeps grid and rebuild ids".

### Task 10: A fake game proves the contract

**Files:**
- Create: `tests/fake_game.lua`, `tests/test_contract.lua`
- Test: `tests/test_contract.lua`

**Interfaces:**
- Consumes: `arcade.cycle`, `arcade.cars`, `arcade.parking`, the settings service and the contract hooks, as Tasks 7 and 8 define them.
- Produces: `fake_game.new(ctx)`, a racing game with:
  - `manifest { id = "race", minPlayers = 2, commands = { "race" }, clientEvents = { "race_lap" } }`;
  - phases `grid` → `race`;
  - per-player round-car permissions (`ctx.cars:permit` for every racer);
  - a targeted rebuild of one racer's car through the car tools;
  - finishing through `ctx.round:finish`.

  No runner, cop, practice or effect list. The test boots `arcade.cycle` with this game and fake BeamMP functions (reuse `tests/server_boot.lua`'s fakes); it doesn't boot Cops and Robbers.

- [ ] **Step 1: Write the tests:**
  - `"a race needs two players"`: refused with one player;
  - `"a race starts, ticks, finishes into results and schedules the next with auto on"`;
  - `"a racer joining mid-race and leaving keeps the cleanup order"`;
  - `"a car the race doesn't allow is refused with 1"`;
  - `"a rebuild targets only the chosen racer"`;
  - `"its client event reaches clientEvent"`.
- [ ] **Step 2: Run** `make test`. Any failure shows a Cops and Robbers assumption in the contract: fix it in `arcade/`, not in the fake game, and note it in the report.
- [ ] **Step 3: Run** `make test` → PASS; the golden gate is clean.
- [ ] **Step 4: Commit** with the message "A fake racing game exercises the contract".

### Batch completion (controller)

- [ ] Each task gets a counterpart task review with the review rule above before the next task's review closes. Fixes go back to the implementer and are re-reviewed.
- [ ] On the final head: `make test`, `make vuecheck` and `make package` pass, and all five CI jobs are green.
- [ ] The whole-branch review is clean and posted on PR #94. Then #72 moves to Review, and the playtest runs through the playtest extension with the step 1 checks. Merge after the maintainer's go.
