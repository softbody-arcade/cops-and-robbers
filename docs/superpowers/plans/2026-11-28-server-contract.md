# Split step 2: the server contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put Cops and Robbers' server half behind a game interface (hooks plus services), move the remaining manager parts to `server/CopsAndRobbers/arcade/`, and leave `main.lua` as wiring, with every golden trace unchanged.

**Architecture:** First the services the contract needs become their own `arcade/` modules behind today's callers: vectors, traffic slots, safe saves, the settings service, the car tools and spectators. Then Cops and Robbers' effect handling moves into `cnr/game.lua` intact, and its branches switch to service calls. Then `arcade/cycle.lua` takes the lobby/round/results cycle, the tick, start and finish, and every BeamMP entry point. A fake game in the tests proves the contract fits a second game. The golden traces gate every task.

**Tech Stack:** Lua 5.3 (BeamMP Server 3.9.3; CI runs `lua5.3`), the repo's `tests/run.lua` runner (`make test` runs `tests/test_*.lua`), the server boot in `tests/server_boot.lua`, and the golden traces in `tests/traces/`.

**Spec:** [docs/superpowers/specs/2026-11-28-server-contract-design.md](../specs/2026-11-28-server-contract-design.md) (approved 2026-11-28; decisions on #72). It argues from the arcade manager spec, arcade-base `docs/superpowers/specs/2026-11-27-arcade-manager-design.md`. Ticket: #72, with #92 and #89 folded in. The spec's section "Refinements from planning" lists the contract details this plan settles.

## Global Constraints

- Every golden trace in `tests/traces/` matches after every task. A mismatch is a bug in the task, never a reason to re-record or to make the recorder report something that didn't happen. Gate with `git diff --exit-code <plan commit> -- tests/traces` and `make test`.
- Behaviour changes allowed, only as the spec's "Behaviour change" section says:
  - a round keeps the settings snapshot taken at its start, and only the automatic-next on/off stays live;
  - an automatic-rounds toggle keeps a host's disk edit;
  - a failed save never loses a file (#92).
- New and moved server modules live in `server/CopsAndRobbers/arcade/`, required as `arcade.<name>`. An `arcade.*` module never requires `cnr.*`.
- No module-level state in `arcade/` or `cnr/`, except the grid and rebuild counters in `cnr/round.lua`. Services with state are built with `new(...)` from `main.lua`.
- Events keep their `cnr_` names and payloads; the manager's tools send `cnr_` events through 2.x. No client file changes.
- Server Lua stays within Lua 5.3. No source comments. Version numbers stay out of commits.
- Before each commit: `make test`. Check each changed server file with `luajit -bl <file> >/dev/null`, plus `luac5.3 -p` where installed.
- Review rule: every task review also checks each hook or service the task touches against Street racing (grid, race, series, per-player upgrades) and Wheel racing (changes for everyone except last place), and flags any Cops and Robbers concept in `arcade/`.
- A test marked **(characterization)** pins today's behaviour before a move and is expected to pass before the change; say so in the report.

## Review Focus

- **A hot reload mid-round** (top-level `main.lua` re-run): fresh services and a fresh game, one timer, start-up messages again, and grid and rebuild IDs that never repeat (Task 10).
- **A spawn between a setup and the driver's `cnr_myVehicle`,** in a real round and in driven practice. It must neither publish a first round car early nor release AI setup early (Tasks 4, 8).
- **A panel save while the disk is full or the rename fails:** the original `config.json` and the live value survive, and the panel shows the error with the request ID (Task 2).
- **Disconnects at every phase:** picking, prep, chase, practice; issuer, runner, cop. The roster cleanup order stays, and a runner leaving sends exactly one empty `cnr_roundCars` (Task 9).
- **An automatic start after the last issuer left:** the lowest player ID issues it, as today, through `ctx.round:start` with `command = "next"` (Task 7).

---

### Before Task 1 (controller)

- [ ] Step 1 (#71) and the #84 batch are released (decision on #72). Run `git fetch --tags origin`, take the newest release tag from `gh release list -R softbody-arcade/cops-and-robbers -L 1`, and check that `git merge-base --is-ancestor aaffd27 <tag>` succeeds (`aaffd27` is PR #85's merge). If it doesn't, stop and ask the maintainer.

### Task 1: Vectors, traffic slots and the sit-out snapshot

**Files:**
- Move: `server/CopsAndRobbers/cnr/vec.lua` → `server/CopsAndRobbers/arcade/vec.lua` (`git mv`)
- Create: `server/CopsAndRobbers/cnr/vec.lua`, a re-export with one line: `return require("arcade.vec")`
- Modify: `server/CopsAndRobbers/arcade/traffic.lua`, `server/CopsAndRobbers/cnr/traffic.lua`, `server/CopsAndRobbers/arcade/roster.lua`, `server/CopsAndRobbers/main.lua` (callers)
- Test: `tests/test_arcade_traffic.lua` (update its fixtures to the new signatures), `tests/test_arcade_roster.lua`; the existing `cnr.vec` tests keep passing unchanged

**Interfaces:**
- Produces: `arcade.vec`, the same module `cnr.vec` is today, re-exported by `cnr.vec`.
- Produces: `traffic.whole(v) -> integer`, exported from `arcade.traffic`. `cnr/traffic.lua` uses it instead of its own copy. `arcade/traffic.lua` uses `arcade.vec.toVec` instead of its copied `isNum` and `toVec`.
- Produces: `traffic.perPlayer(setting, maxCars, reserved)`, where `reserved` is the number of car slots kept free; today it is `practice and 3 or 1`.
- Produces: `t:allowance(cfg, reserved, eligible)`; the unused `pid` is dropped.
- Produces: `r:sitOutSnapshot() -> { [pid] = true }`, a fresh copy.
- Produces: `r:players() -> { [pid] = name }`, wrapping `MP.GetPlayers() or {}`, and `r:name(pid) -> string | nil`, wrapping `MP.GetPlayerName`. Later tasks use these instead of engine calls in game code.
- Produces: `r:playingList(players) -> { pid, … }`: the pids `r:playing` counts, sorted ascending, as a dense list.

- [ ] **Step 1: Failing tests.**
  - `perPlayer(5, 6, 3) == 3`, `perPlayer(5, 6, 1) == 5`, `perPlayer(5, nil, 3) == 5`, and `perPlayer(5, 2, 3) == 0`. Update today's boolean fixtures: `false` → `1`, `true` → `3`.
  - `t:allowance({ trafficPerPlayer = 5 }, 1, false) == 0`.
  - `traffic.whole("2.7") == 2` and `traffic.whole(-1) == 0`.
  - After `r:setSitOut(2, true)`, `r:sitOutSnapshot()` is `{ [2] = true }`, and changing the returned table doesn't change `r:sittingOut(2)`.
  - `r:playingList({ [7] = "Kim" })` is `{ 7 }`, so `#` counts it.
- [ ] **Step 2: Run** `make test` → those tests FAIL.
- [ ] **Step 3: Implement.** Callers in `main.lua`:
  - `openTraffic` passes `current.test and pid == current.issuerId and 3 or 1`;
  - `cnr_rules`, `Round:start`'s traffic count and `cnr.traffic.note` pass `1`;
  - the start command passes `roster:sitOutSnapshot()` to `Round:start`.
- [ ] **Step 4: Run** `make test` → PASS, and the golden gate is clean. `grep -n "isNum\|local function toVec\|local function whole" server/CopsAndRobbers/arcade/traffic.lua server/CopsAndRobbers/cnr/traffic.lua` shows only `arcade/traffic.lua`'s `whole`.
- [ ] **Step 5: Commit** with the message "arcade.vec, traffic slots and the sit-out snapshot".

### Task 2: Saves that never lose a file, the settings service, and override checks (#92, #89)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/store.lua`, `server/CopsAndRobbers/arcade/settings.lua`, `server/CopsAndRobbers/cnr/config.lua`, `server/CopsAndRobbers/arcade/playerColors.lua`, `server/CopsAndRobbers/main.lua` (save callers and the panel save)
- Test: `tests/test_arcade_store.lua`, `tests/test_arcade_settings.lua`, `tests/test_config.lua`, `tests/test_arcade_player_colors.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `store.write(path, content) -> true | nil, err`. It keeps today's `FS` call order, so the traces still record `fs remove` then `fs write`:
  1. Write `<path>.tmp`, checking `open`, `write` and `close`. A failure removes only the `.tmp` and returns `nil, err`.
  2. If `path` exists, copy it to `<path>.bak` with a checked binary read and write. These are plain `io` and `os` calls, not `FS`, so the recorder doesn't see them. A failure removes the `.tmp` and returns `nil, err`, before anything is removed.
  3. `FS.Remove(path)`.
  4. `FS.Rename(tmp, path)`.
  5. On success, `os.remove(<path>.bak)` and return `true`.
  6. If the rename fails: copy `<path>.bak` back to `path`, remove the `.tmp`, remove the `.bak` and return `nil, err`. If that restore fails, leave `<path>.bak` in place and return an error naming it, so the old bytes are always on disk.
- Callers handle the error:
  - **Settings, build, stations, leaderboard:** log `could not save <basename>: <err>` and keep their in-memory state as it was before the change.
  - **Player colours:** `c:set` and `c:clear` change the in-memory entries only after a successful save. On failure they return `false, err`, and the `cnr_color` handler passes the error to `sendMine`, as today's invalid-colour path does, also for a clear.
  - **Build replacement and reset:** `backupBuild` moves `build.json` aside before the new build is saved (`main.lua:831`). If the save then fails, the aside file is renamed back to `build.json`, the in-memory build stays the old one, and the panel replies with the error.
- Produces: the settings service `s = settings.new(path, decl, log)`:
  - `s:load() -> cfg, warnings, raw`, as today, and kept inside `s`;
  - `s:effective() -> cfg`, the live settings;
  - `s:get(key) -> value`, from the live settings;
  - `s:set(key, text) -> true | nil, err`. It re-reads the file and changes only `key`, dropping retired entries as every save does. A missing file starts from `{}`. An unreadable or corrupt file returns `nil, err` and writes nothing. A failed save returns `nil, err` and keeps the live value. Success updates the live settings.
  - `s:apply(values) -> keys | nil, err`: the panel's multi-key save, with the same rules (it replaces `panel.applyValues` + `save` in `panelSettings`);
  - `s:snapshot() -> a deep copy of the live settings`, list values copied too.
- Produces: a declaration field `RANGES = { minKey = "maxKey" }`. `merge` checks it where it called `decl.fix`, before `TIMING_RANGES`, with today's warning format `"%s (%s) is below %s, using %s"`. `combine` merges a game's `RANGES` like the other fields. `cnr/config.lua` declares `RANGES = { copSpawnMinMeters = "copSpawnMaxMeters" }`, and `GAME.fix` is removed.
- Produces (#89): `combine` validates every combined default, game defaults and overrides alike, with the validators `merge` uses for config values:
  - type;
  - choices;
  - `POSITIVE`, `MAXIMA` and `WHOLE`;
  - list shape;
  - each `RANGES` and `TIMING_RANGES` default maximum not below its minimum;
  - both ends of a range having number defaults.

  A failure is an assertion naming the key.

- [ ] **Step 1: Failing tests** in `tests/test_arcade_store.lua`:
  - a failing write, close or rename returns `nil, err`, leaves the original bytes and leaves no `.tmp`. Stub the temp file's `write` or `close` through `io.open`, and the fake `FS.Rename`.
  - a successful write replaces the content, with the fake `FS.Rename` refusing an existing target.
  - the recorded order of a successful save is `fs remove`, then `fs write`. Use `serverBoot`'s fakes and check `env.stream`.
- [ ] **Step 2: Failing tests** in `tests/test_arcade_settings.lua` and `tests/test_config.lua`:
  - `set` keeps a key edited on disk after load;
  - `set` on a legacy file drops `clockSpeed`, `lastSeenIntervalSeconds` and the `"map"` values;
  - `set` on a corrupt or unreadable file returns `nil, err`, leaves the file unchanged, and `get` returns the old value;
  - a failing save makes `set` and `apply` return `nil, err` and keep `get`;
  - `snapshot()` is a deep copy: changing `snapshot().excludedModels` doesn't change `get("excludedModels")`;
  - `RANGES` warns `copSpawnMaxMeters (10) is below copSpawnMinMeters, using 50` and fixes the value, in the warning position `fix` had. Extend `merge preserves the corrected config, warnings and their defined order`;
  - `cnr.config.declaration` contains no functions: walk it and assert `type(v) ~= "function"`;
  - #89: `combine` fails naming the key for:
    - a game default `{ fooSeconds = -1 }` declared `POSITIVE`;
    - a game `RANGES = { aMeters = "bMeters" }` with defaults 10 and 5;
    - `OVERRIDES = { nightChancePercent = 150 }`;
    - `{ lightningMinSeconds = 0.5 }`;
    - `{ lightningMinSeconds = 60 }`;
    - `{ excludedModels = { a = 1 } }`;
    - a game `TIMING_RANGES` whose keys have no number defaults.

    `OVERRIDES = { weather = "rain" }` still passes.
- [ ] **Step 3: Failing tests** in `tests/test_main.lua`:
  - `"a panel save that can't be written keeps config.json and the live value"`: make `FS.Rename` fail for `config.json`, send `{"action":"settings","id":7,"values":{"headStartSeconds":9}}`, and assert:
    - a `cnr_panelReply` with `ok = false` and `id = 7`;
    - the original bytes on disk;
    - the panel's `settings.headStartSeconds` unchanged.
  - `"a colour that can't be saved isn't applied"`: for both a set and a clear of a saved colour, the player's `cnr_myColor` reply carries the error, and the old colour stays.
  - `"a new build that can't be saved keeps the old build"`: with an existing `build.json`, make the save fail. `build.json` keeps its bytes, the panel reply carries the error, and the panel still shows the old build.
  - In `tests/test_arcade_store.lua`: `"a failed rename and a failed restore leave the original in <path>.bak"`, and `"an unreadable original stops the save before anything is removed"`.
- [ ] **Step 4: Run** `make test` → the new tests FAIL.
- [ ] **Step 5: Implement.** `main.lua`'s `readSettings`, `panelSettings` (now `settings:apply`) and the automatic-rounds adapter keep their behaviour otherwise; Task 3 rewires the toggle.
- [ ] **Step 6: Run** `make test` → PASS, and the golden gate is clean.
- [ ] **Step 7: Commit** with the message "Saves never lose a file; the settings service gets get, set, apply and snapshot; declarations are checked (#92, #89)".

### Task 3: The settings snapshot and the automatic-rounds toggle

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/arcade/autoRounds.lua`, `server/CopsAndRobbers/cnr/panel.lua`
- Test: `tests/test_main.lua`, `tests/test_arcade_auto_rounds.lua`

**Interfaces:**
- Consumes: the Task 2 settings service.
- Produces: `autoRounds.register(p, ctx)`, where `ctx.settings` is the settings service itself; the `{get, set}` adapter and `refreshConfig` are gone. The `auto` command calls `ctx.settings:set("autoNextRound", arg)`:
  - on an error it replies with the error and changes nothing;
  - on success it pushes rules and, for `off`, cancels the schedule and sends `cnr_autoNext {}`, as today.
- Produces: in `main.lua`, `cfg` means the settings in force: the live settings while no round runs, and the round's snapshot from round start to round end. Round end switches `cfg` back to live. Which source each value comes from:
  - **Gameplay rules, `cnr_rules` and the round's payloads:** `cfg`.
  - **Panel `auto` and `settings.autoNextRound`:** always live, `settings:get("autoNextRound")`. `cnr.panel.snapshot` takes them as a separate `autoNextRound` input.
  - **Other panel settings:** `cfg`.
  - **Scheduling at round end:** live `autoNextRound`, and the snapshot's `autoNextDelaySeconds`.
  - **`cnr_rules`:** goes out on join, on the toggle and on `reload` unconditionally, as today and at today's position (before the reply, before `cnr_autoNext`). At round end it is sent to everyone only when the payload differs from the last one sent; keep its signature.

- [ ] **Step 1: Failing tests** in `tests/test_main.lua`:
  - `"a disk edit survives a mid-round auto toggle and applies from the next round"`:
    1. Start a round.
    2. Write `"headStartSeconds":9` into `env.dir .. "config.json"`.
    3. `env.panel(1, "auto on")`.
    4. Assert the file still has 9.
    5. Let the round reach `cnr_runnerGo`, and assert its `headStartSeconds` is 7.
    6. End it, start the next round, and assert that round's `cnr_runnerGo.headStartSeconds` is 9.
  - `"a held-back change reaches players once at round end"`: from a known `#env.sent` offset, count `cnr_rules` sends at each round end: one after a round with a held-back change, zero after an unchanged round.
  - `"a subscribed panel shows auto off at once during a chase"`.
  - `"a disk edit to the delay doesn't change the running round's next countdown"`.
  - `"auto off mid-chase still stops the next countdown"`.
  - `"auto on with an unreadable config.json changes nothing and says so"`: replace the file with a directory, toggle, and assert the reply carries the error, there is no `cnr_autoNext`, and the panel still shows the old value.
- [ ] **Step 2: Run** `make test` → FAIL.
- [ ] **Step 3: Implement.** `reloadRound` uses `settings:load()`. The legacy test `a save drops retired sky settings from config.json` (`tests/test_main.lua:514`) keeps passing.
- [ ] **Step 4: Run** `make test` → PASS, and the golden gate is clean; `auto_next.txt` still has the toggle's rules broadcast before `cnr_autoNext`.
- [ ] **Step 5: Commit** with the message "A round keeps its settings snapshot; the auto toggle keeps disk edits".

### Task 4: The car tools and spectators

**Files:**
- Create: `server/CopsAndRobbers/arcade/cars.lua`, `server/CopsAndRobbers/arcade/spectators.lua`
- Modify: `server/CopsAndRobbers/main.lua`
- Test: `tests/test_arcade_cars.lua`, `tests/test_arcade_spectators.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `cars.new(roster, messages, traffic) -> c`. It owns today's `activeVid`, `registeredRoundCar`, `preRoundVehicles`, `lastRoundCars`, and the split of `allowRoundSpawn`. Operations:
  - `c:setup(pid, payload) -> delivered, reason` sends `cnr_roundSetup` with the game's payload. When delivered, it grants the one-use permission and marks placement pending.
  - `c:requestPick(pid, payload)` sends `cnr_pickVehicle`.
  - `c:rebuild(targets, payload, id) -> { [pid] = delivered }` sends `cnr_rebuild` to each target and marks each delivered target pending rebuild `id`.
  - `c:acknowledgeRebuild(pid, id) -> bool` clears that player's pending rebuild only when `id` matches, and returns whether it did.
  - `c:pendingRebuild(pid) -> bool`.
- Permissions:
  - `c:permitted(pid) -> bool`;
  - `c:placementPending(pid) -> bool`;
  - `c:replacementAllowed(pid) -> bool`: confirmed, and no active car.
- Identity:
  - `c:claim(pid, vid) -> "permit" | "replacement" | nil` takes a spawn the game marked `roundCar`. It uses up the permission if there is one, otherwise the replacement right. It records the provisional car, and placement stays pending. It returns which right it used, or `nil` when neither applies.
  - `c:confirmed(pid) -> bool`, and `claim`'s second return value (whether it published at once), added in Task 4.
  - `c:confirm(pid, vid) -> replaced`, for `cnr_myVehicle`, sets confirmed and clears pending, permission and pre-round exclusions. It returns true when it changed an already confirmed car's ID; the game then drops that car's sight, as today (`tests/test_main.lua:3639`).
  - `c:activeVid(pid)`, `c:confirmedVid(pid)`, `c:vidFor(pid)` and `c:firstVid(pid)`.
  - `c:setActive(pid, vid) -> replaced` returns true when a confirmed car's ID changed. The caller reports that to the game.
  - `c:rememberPreRound(pid)`, `c:isPreRound(pid, vid)` and `c:forgetPreRound(pid, vid)`.
  - `c:position(owner, vid) -> { pos, vel } | nil`, using `arcade.vec`; `nil` unless both are valid, as `carFor` today.
  - `c:rawPosition(owner, vid) -> raw | nil, err`, wrapping `MP.GetPositionRaw`, for callers that need the position without a velocity (the start-grid planner).
  - `c:vehicles(owner) -> { [vid] = packet }`, wrapping `MP.GetPlayerVehicles` (the AI capacity check, the planner's single car, ownership checks).
  - `c:removeParticipant(pid)`: the game calls it when it drops a player from the round without a disconnect (a failed setup, a removed cop). That player's key leaves the published list at the next `publish`.
- Publication:
  - `c:publish(pid?)` sends `cnr_roundCars` of every confirmed car of a round participant, sorted and de-duplicated, with today's signature skip and a single-player send when `pid` is given. A player becomes a participant at their first `setup` and stops being one at `removeParticipant` or when they leave.
  - `c:setPublishing(on)` turns publishing on or off; the cycle turns it on at round start and off at finish. `publish` does nothing while off, as `pushRoundCars` does when no round is active.
  - `c:clearPublished()` does what `clearRoundCars` does.
  - `c:clearRound()` clears the per-round tables, as round end does today.
- Produces: `spectators.new(roster, messages) -> k`:
  - `k:spectate(pid, payload, label)` logs `"<name> spectates (<label>)"` and sends `cnr_spectate`;
  - `k:park(pid)` sends `cnr_parkBystanderCars {on=true}` and remembers the player only when delivered;
  - `k:isParked(pid)`;
  - `k:releaseAll()` sends `{on=false}` to each parked player and clears the set, in today's order.
- The game-side decisions stay in `main.lua` in this task:
  - which spawn is a `roundCar` (`matchesRoundVehicle`, `not current.test`);
  - the issuer and the AI slots;
  - `forgetVehicleSight` when `setActive` reports a replacement.

- [ ] **Step 1: Failing unit tests** for `cars`:
  - after `setup`, `claim` uses up `permitted` while `placementPending` stays true until `confirm`;
  - a claim publishes immediately only for a player who was confirmed before;
  - after a confirmed car is deleted (`setActive(pid, nil)`), `claim` returns `"replacement"`, and a second `claim` returns `nil`;
  - a reroll's new setup lets `claim` return `"permit"` while the old car is still confirmed;
  - `publish` sends nothing when the key list hasn't changed or publishing is off;
  - `clearPublished` sends `{keys = {}}` only after a non-empty publish;
  - `rebuild` returns a delivery map; `acknowledgeRebuild` with an old ID returns false and keeps `pendingRebuild`, and the current ID clears it;
  - `confirm` returns `replaced = true` only when a confirmed car's ID changes;
  - a cop who confirmed a car and is then removed with `removeParticipant` (a failed reroll setup) is absent from the next `publish` and from the list a joining spectator gets.

  For `spectators`: an undelivered park isn't remembered, and `releaseAll` sends `on=false` once to each parked player.
- [ ] **Step 2: Test (characterization)** in `tests/test_main.lua`: `"in driven practice a spawn before cnr_myVehicle doesn't release AI setup"`:
  1. `env.panel(1, "test runner")`, pick, and let the setup go out.
  2. `onVehicleSpawn` from 1 with the round model, then tick.
  3. Assert no `cnr_setupAI` yet.
  4. Send `cnr_myVehicle`, tick, and assert `cnr_setupAI`.
- [ ] **Step 3: Run** `make test` → the unit tests FAIL; the modules don't exist.
- [ ] **Step 4: Implement** and switch `main.lua`'s callers to `cars` and `spectators`:
  - `dispatchAISetup` waits on `cars:placementPending(pid)`;
  - the vehicle callbacks keep their exact return values and logs;
  - the `setup`, `pickVehicle`, `rebuild` and `spectate` effects use the tools.
- [ ] **Step 5: Run** `make test` → PASS, including `tests/test_main.lua:2470` (deletion and reroll replacement), and the golden gate is clean.
- [ ] **Step 6: Commit** with the message "arcade.cars and arcade.spectators own car operations, round-car identity and spectators".

### Task 5: The game object, with the effect handling moved intact

**Files:**
- Create: `server/CopsAndRobbers/cnr/game.lua`
- Modify: `server/CopsAndRobbers/main.lua`
- Test: the golden traces and `make test`; this is a pure move

**Interfaces:**
- Produces: `cnr.game.new(ctx) -> game`. In this task `ctx` is a table `main.lua` builds from its locals and services.
  - `game` owns `current` (the `cnr.round` object), `aiCars`, the AI serials, `pendingAISetup`, `aiSpawnsLeft`, `partsBaseline`, `missingCount`, `stations`, `currentBuild`, the run counts and runner keys, and `lastResult`.
  - `game:applyEffects(effects)` is today's `applyEffects`, moved unchanged apart from reading services from `ctx`.
- `main.lua` calls `game:applyEffects(...)` wherever it called `applyEffects(...)`. Handlers stay in `main.lua` and reach game state through `game` fields or small `game:` methods named after the old local functions.

- [ ] **Step 1: Move** `applyEffects` and the game state it touches into `cnr/game.lua`. Keep `ipairs` order and the recursive call on a failed setup.
- [ ] **Step 2: Run** `make test` → PASS, and the golden gate is clean. `grep -n "e.kind ==" server/CopsAndRobbers/main.lua` prints nothing.
- [ ] **Step 3: Commit** with the message "cnr.game holds the round and its effect handling".

### Task 6: Effects use only the context

**Files:**
- Modify: `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_main.lua`, the golden traces

**Interfaces:**
- Consumes: `cars` and `spectators` (Task 4), the messages service, the settings snapshot (Task 3), and `roster:players()` and `roster:name()` (Task 1).
- Produces: `ctx.clock = { now = function() -> seconds, timer = function() -> MP timer }`, which wraps `MP.CreateTimer`.
- Produces: inside `cnr/game.lua`, every effect kind uses only `ctx` services:
  - `ctx.messages` for sends;
  - `ctx.roster` for players and names;
  - `ctx.clock` for the countdown's lightning timer;
  - `ctx.cars` and `ctx.spectators` for car and spectator work;
  - `ctx.traffic` for slots;
  - `roundEnd` calls `ctx.round:finish(endPayload, audience, scheduleNext)` (below), then clears its own state: `pendingAISetup`, `aiSpawnsLeft`, `partsBaseline`, `missingCount`, `aiCars` and the serials. None of these clears sends anything. `lastResult` is not cleared here: as today, it is set when a real round ends with a result (not practice, not cancelled, not issuer-only) and cleared only when a new round starts.
- Produces: `ctx.round:finish(endPayload, audience, scheduleNext)`, implemented in `main.lua` for now. In order:
  1. `spectators:releaseAll()`;
  2. `cnr_roundEnd` with `endPayload` to `audience` (`-1` or the issuer);
  3. `cars:clearRound()`;
  4. `cars:clearPublished()`;
  5. schedule the next round when `scheduleNext` is true and `settings:get("autoNextRound")` is true;
  6. switch `cfg` back to live.

  It then calls the game's `roundFinished()`, which sends `cnr_rules` if it changed (Task 3's rule).
- The `record` effect stays a separate game effect after it. The panel save calls the game's `settingsChanged(keys)`, which sends rules, calls `ctx.panel:push()`, then pushes its board: today's order after the reply. The automatic-rounds toggle and `reload` call the game's `rulesChanged()`, which sends `cnr_rules` unconditionally, at the point `pushRules` sits today.

- [ ] **Step 1: Test (characterization)**: `"a practice end unparks bystanders before the issuer's roundEnd"`. In a practice with a second player, `cnr_parkBystanderCars {on=false}` comes before `cnr_roundEnd` to the issuer in `env.sent`.
- [ ] **Step 2: Replace** the branches one effect kind at a time, running `make test` and the golden gate after each.
- [ ] **Step 3: Run** `make test` → PASS, and the golden gate is clean. `grep -nE "MP\.(TriggerClientEvent|GetPlayers|GetPlayerName|GetPlayerVehicles|GetPositionRaw|RemoveVehicle|CreateTimer)" server/CopsAndRobbers/cnr/game.lua` prints nothing.
- [ ] **Step 4: Commit** with the message "Cops and Robbers' effects use only the context".

### Task 7: The cycle, starting and finishing a round

**Files:**
- Create: `server/CopsAndRobbers/arcade/cycle.lua`
- Modify: `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/arcade/panel.lua`, `server/CopsAndRobbers/cnr/panel.lua`
- Test: `tests/test_arcade_cycle.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: the game module's static functions, read before anything is built:
  - `cnr.game.manifest(version) -> { id = "cnr", name = "Cops and Robbers", version, minPlayers = 1, commands = { exact = { "go", "reroll", "end", "stop", "test runner", "test cop", "sky" }, prefixes = { "start " } }, actions = { "build", "apply", "station", "stations" }, clientEvents = { … every `cnr_*` client event Cops and Robbers registers today except `cnr_panel` … } }`. `actions` are the structured panel actions the game handles itself; the manager keeps `open`, `close`, `command` and `settings`;
  - `cnr.game.settingsDeclaration() -> cnr.config.GAME`.

  `cnr/panel.lua` keeps only the game's commands; the manager adds its own.
- Produces: the construction order in `main.lua`. Each service is built before its first consumer:
  1. messages, roster, store and the clock (`ctx.clock`, Task 6);
  2. `gameModule = require("cnr.game")`;
  3. `manifest = gameModule.manifest(VERSION)`;
  4. `settings = settings.new(path, settings.combine(settings.GLOBAL, gameModule.settingsDeclaration()), log)`;
  5. traffic (`traffic.new(roster, messages)`);
  6. cars (`cars.new(roster, messages, traffic)`);
  7. spectators and player colours;
  8. the panel service and autoRounds;
  9. `cycle = cycle.new(services, manifest)`;
  10. `game = gameModule.new(cycle:context())`;
  11. `cycle:attach(game)`.

  The fake-game test in Task 11 uses the same order.
- Produces: `cycle.new(services, manifest) -> y`:
  - `y:context() -> ctx` holds the services plus `ctx.round` and `ctx.panel`;
  - `y:attach(game)`;
  - `y:state() -> "lobby" | "round" | "results"`;
  - `y:dispatch(hook, ...)` is the only place the manager calls a game instance. It calls `game[hook](game, ...)` and returns all its results; step 5 wraps it;
  - the panel allow-list is the manager's exact commands (`auto on`, `auto off`, `next`, `reload`) plus `manifest.commands.exact` and `manifest.commands.prefixes`. A prefix matches `^<prefix>%S`, as today's `start ` rule.
- `ctx.round:start(request) -> true | nil, reason`, in order:
  1. `prepared, reason = dispatch("canStart", request)`. `prepared.participants` is a dense, ascending list of pids (Cops and Robbers uses `roster:playingList`). On `nil`, return `nil, reason`: no snapshot, no state change, no `start`. The game has already sent any refusal.
  2. Refuse with `"Not enough players"` unless `prepared.solo` or `#prepared.participants >= manifest.minPlayers`.
  3. `snapshot = settings:snapshot()`.
  4. State → round; `cars:setPublishing(true)`.
  5. `dispatch("start", prepared, snapshot, now)`.
- `ctx.round:finish(...)`: as in Task 6, moved here. It ends with state → results and `cars:setPublishing(false)`, then `dispatch("roundFinished")`.
- `y:startNext()` builds `request = { issuer = <today's startNext choice>, command = "next" }` and calls `ctx.round:start`.
- `y:tick()`, in order:
  1. panel and lobby pushes: `dispatch("panelState")`, only while someone has the panel open, and `dispatch("lobbyFields")`;
  2. a due automatic start;
  3. stop if not in a round;
  4. `dispatch("tick", now)`. Cops and Robbers' `tick` runs, in order: the AI dispatch or timeout, position sampling, the lightning announcement, `current:tick`.
- Produces: in `cnr/game.lua`, the instance hooks:
  - `canStart(request)`: today's start sequence and texts, with `command = "next"` mapped to today's `start next`;
  - `start(prepared, snapshot, now)`;
  - `tick(now)`;
  - `panelState()` and `lobbyFields()`;
  - `roundFinished()`, `settingsChanged(keys)` and `rulesChanged()`.

  The game's `start`, `test runner` and `test cop` commands call `ctx.round:start({ issuer = pid, command = <word>, text = <rest> })`. Practice returns `prepared.solo = true`. A real round returns `prepared.participants` = the playing roster.

- [ ] **Step 1: Failing unit tests** in `tests/test_arcade_cycle.lua`, with a stub game module and instance:
  - a `canStart` returning `nil, "No runner"` leaves the state, the snapshot count and the `start` calls untouched, and returns the reason;
  - a non-solo start below `minPlayers` is refused, and `start` never runs;
  - a solo start with zero participants passes;
  - `start` receives a snapshot that later `settings:set` calls don't change;
  - a default only the stub game declares is visible through `settings:get` and in the first snapshot;
  - `finish` moves to results and dispatches `roundFinished`, then a new start moves to round;
  - `startNext` sends `command = "next"`;
  - `tick` calls `panelState` only while someone has the panel open, and `lobbyFields` every tick;
  - a real round with only player 7 connected passes the minimum-players check.
- [ ] **Step 2: Tests (characterization)** in `tests/test_main.lua`:
  - `"watch-only practice by a sitting-out player still starts"`, which pins `tests/test_main.lua:3131` through the cycle;
  - `"an automatic start after the issuer left is issued by the lowest player id"`.
- [ ] **Step 3: Run** `make test` → the unit tests FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** `make test` → PASS, and the golden gate is clean.
- [ ] **Step 6: Commit** with the message "arcade.cycle owns the lobby, round and results cycle".

### Task 8: Vehicle callbacks through the contract

**Files:**
- Modify: `server/CopsAndRobbers/arcade/cycle.lua`, `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_arcade_cycle.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `y:onVehicleSpawn(pid, vid, data)` and `y:onVehicleEdited(pid, vid, data)`:
  1. Decode the packet once, as `parseVehicleData` does.
  2. Build `facts = { permitted, placementPending, confirmed, replacementAllowed, activeVid, preRound, trafficOpen }` from `cars` and `traffic`.
  3. `verdict = dispatch("checkVehicle", kind, pid, vid, decoded, facts)`, where `verdict = { allow = bool, reason = string?, roundCar = bool?, notify = bool }`.
  4. A refusal logs today's text with the 10-second rate limit, replies `reason`, and returns `1`.
  5. For an allowed `roundCar` spawn, `cars:claim` runs; a `nil` claim refuses with today's text and returns `1`.
  6. When `notify` is true, `dispatch("onVehicle", kind, pid, vid, decoded, facts, now)` runs.
  7. Return `0`.

  `notify = false` covers today's early `return 0` paths: pre-round cars, and a non-active car of a confirmed driver that isn't an AI slot.
- `y:onVehicleDeleted(pid, vid)` and `y:onVehicleReset(pid, vid)` update the registry, publish as today, then run `dispatch("onVehicle", "delete" | "reset", pid, vid, nil, facts, now)`.
- When `cars:setActive` reports a replaced confirmed car, the cycle runs `dispatch("onVehicle", "replaced", pid, vid, nil, facts, now)`, so the game drops the old car's sight.
- `cnr_myVehicle` stays a game client event (Task 9). It calls `ctx.cars:confirm` (and drops sight when it reports `replaced`), `ctx.cars:acknowledgeRebuild(pid, rebuildId)` and `ctx.cars:publish()`, as today.
- Produces: in `cnr/game.lua`, `checkVehicle` and `onVehicle`. They hold today's policy:
  - `vehicleAllowed`'s rules;
  - `matchesRoundVehicle` with the missing-config-filename and evolving cases;
  - `roundCar` only outside practice;
  - the AI slots and `aiSpawnsLeft`;
  - `checkParts` on an accepted edit, using `decoded`;
  - reset scoring.

- [ ] **Step 1: Failing unit tests** in `tests/test_arcade_cycle.lua`, with a stub game:
  - a refused spawn returns 1 and logs once within 10 s;
  - a `roundCar` spawn with neither a permit nor a replacement right is refused with 1;
  - a replacement after a confirmed car's deletion returns 0 above the traffic cap and publishes at once;
  - a first `roundCar` spawn isn't published until `confirm`;
  - `notify = false` skips `onVehicle`, and an accepted edit gives `onVehicle` the decoded packet.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.**
- [ ] **Step 4: Run** `make test` → PASS, including `tests/test_main.lua:2470`, and the golden gate is clean.
- [ ] **Step 5: Commit** with the message "Vehicle callbacks reach the game only through checkVehicle and onVehicle".

### Task 9: Join, leave, panel and client events through the contract

**Files:**
- Modify: `server/CopsAndRobbers/arcade/cycle.lua`, `server/CopsAndRobbers/cnr/game.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_arcade_cycle.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces:
  - `y:onPlayerJoin(pid)` → `dispatch("join", pid, name, now)`. In 2.x the game's `join` sends the whole join sequence in the spec's order and calls `ctx` services for the manager's parts: own colour, the lobby push (`ctx.panel:pushLobby(pid)`) and `ctx.cars:publish(pid)`.
  - `y:onPlayerDisconnect(pid)`, in order: `roster:leaveEarly`, `dispatch("leave", pid, now)`, `roster:leaveLate`, `cars:publish()`. `publish` does nothing if `leave` finished the round.
  - `y:onPanel(pid, data)` handles these itself: `open`, `close`, the manager's commands, and settings saves. A save runs `settings:apply`, reloads (so config warnings log before the reply, as today), replies with the request ID, then `dispatch("settingsChanged", keys)`. A `command` whose text passes the allow-list, or an action named in `manifest.actions`, goes to `dispatch("panelAction", pid, action, payload)`. Anything else is dropped.
  - `y:onClientEvent(name, pid, data)` → `dispatch("clientEvent", name, pid, data)`, for each name in `manifest.clientEvents`.
- Produces: in `cnr/game.lua`, the hooks `join`, `leave`, `panelAction` and `clientEvent`. They hold today's Cops and Robbers logic from `main.lua`: colour paint, sit-out notices, grid, picked, `cnr_myVehicle`, setup, change, missing, sight, cover, stations, board, AI vehicles, traffic reports and the lightning clock.

- [ ] **Step 1: Failing unit tests** in `tests/test_arcade_cycle.lua`, with a stub game:
  - in the disconnect order, the stub `leave` sees `leaveEarly` done and `leaveLate` not yet;
  - a manifest prefix command and a manifest action reach `panelAction`, and an unknown command or action never does;
  - a declared client event reaches `clientEvent`;
  - a settings save dispatches `settingsChanged` after the reply.
- [ ] **Step 2: Test (characterization)** in `tests/test_main.lua`: `"a runner leaving mid-chase sends exactly one empty cnr_roundCars"`. Precondition: a non-empty `cnr_roundCars` was published before the disconnect.
- [ ] **Step 3: Run** → FAIL. **Step 4: Implement**, moving one handler group at a time, with `make test` and the golden gate after each.
- [ ] **Step 5: Run** `make test` → PASS, and the golden gate is clean.
- [ ] **Step 6: Commit** with the message "Join, leave, panel and client events reach the game only through the contract".

### Task 10: main.lua as wiring, hot reload and docs

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `tests/test_reload.lua`, `docs/DEPENDENCIES.md`, `docs/FEATURES.md`
- Test: `tests/test_reload.lua`

**Interfaces:**
- Produces: a `main.lua` that only does this:
  1. sets `package.path`;
  2. builds everything in Task 7's order;
  3. loads data;
  4. binds BeamMP's handler names: the `cnrOn*` globals, each one line calling the cycle, plus one registration per `manifest.clientEvents` name;
  5. starts the 250 ms timer;
  6. sends the start-up messages.

- [ ] **Step 1: Failing test** in `tests/test_reload.lua`: `"rebuild ids from before a reload don't complete the current rebuild"`:
  1. Boot and start an evolving round with two drivers, then start a rebuild.
  2. `env.reload()`.
  3. Start a new round and rebuild.
  4. Acknowledge driver 2 with the current ID.
  5. Replay the old ID for driver 1, and assert no `cnr_applied` and that `cars:pendingRebuild(1)` is still true.
  6. Send the current ID for driver 1, and assert `cnr_applied`.
- [ ] **Step 2: Failing test:** `"grid ids from before a reload don't release the current setup"`:
  1. Replay a `cnr_startGrid` response from the expected planner that is valid except for its old ID, and assert no `cnr_roundSetup`.
  2. Send the current ID, and assert `cnr_roundSetup`.
- [ ] **Step 3: Run** both. They fail only if the counters reset; if they pass at once, keep them as pins and say so in the report.
- [ ] **Step 4: Implement** the wiring. Checks:
  - `grep -n 'require("cnr' server/CopsAndRobbers/main.lua` prints only `cnr.game`;
  - `grep -n "current:\|e.kind" server/CopsAndRobbers/main.lua` prints nothing;
  - `grep -rn 'require("cnr' server/CopsAndRobbers/arcade/` prints nothing;
  - `wc -l server/CopsAndRobbers/main.lua` is under 200.
- [ ] **Step 5: Docs.**
  - `docs/DEPENDENCIES.md`: the arcade section names `cycle`, `cars`, `spectators` and `vec`, and says `main.lua` is wiring.
  - `docs/FEATURES.md`:
    - a round uses the settings from its start;
    - the auto toggle keeps disk edits;
    - a failed save keeps the file.
- [ ] **Step 6: Run** `make test`, `make vuecheck` and `make package` → PASS, and the golden gate is clean.
- [ ] **Step 7: Commit** with the message "main.lua is wiring; reload keeps grid and rebuild ids".

### Task 11: A fake game proves the contract

**Files:**
- Create: `tests/fake_game.lua`, `tests/test_contract.lua`
- Modify: `tests/server_boot.lua`: expose `serverBoot.fakes(env, opts)`, which installs the `MP`, `FS` and `Util` fakes without loading `main.lua`; `boot` keeps using it
- Test: `tests/test_contract.lua`

**Interfaces:**
- Consumes: `arcade.cycle`, `arcade.cars`, `arcade.spectators`, the settings service, and the hooks and static functions from Tasks 7 to 9.
- Produces: the `fake_game` module, a racing game:
  - `manifest(version) -> { id = "race", name = "Race", version, minPlayers = 2, commands = { exact = { "race" }, prefixes = {} }, actions = {}, clientEvents = { "race_lap" } }`;
  - `settingsDeclaration()` with one game setting, `{ DEFAULTS = { laps = 3 }, POSITIVE = { laps = true }, WHOLE = { laps = true } }`;
  - `new(ctx)` returns an instance with every hook, phases `grid` → `race`, a `ctx.cars:setup` for every racer, a targeted rebuild through `ctx.cars:rebuild({ racer }, payload, id)`, and finishing through `ctx.round:finish`.

  No runner, cop, practice or effect list. The test builds the services and `arcade.cycle` with this module in Task 7's construction order, on `serverBoot.fakes`.

- [ ] **Step 1: Write the tests:**
  - `"a race needs two players"`: refused with one, and no state change;
  - `"laps comes from the game's declaration"`: `settings:get("laps") == 3`, and the first `start` snapshot has `laps = 3`;
  - `"a race starts, ticks, finishes into results and schedules the next with auto on"`;
  - `"a racer joining mid-race and leaving keeps the cleanup order"`;
  - `"a car the race doesn't allow is refused with 1"`;
  - `"a rebuild targets only the chosen racer"`: with two racers, only one gets `cnr_rebuild`, and only that one is pending;
  - `"its client event reaches clientEvent"`;
  - `"its prefix-free command reaches panelAction, and an unknown one doesn't"`.
- [ ] **Step 2: Run** `make test`. A failure shows a Cops and Robbers assumption in the contract: fix it in `arcade/`, not in the fake game, and note it in the report.
- [ ] **Step 3: Run** `make test` → PASS, and the golden gate is clean.
- [ ] **Step 4: Commit** with the message "A fake racing game exercises the contract".

### Batch completion (controller)

- [ ] Each task gets a counterpart task review with the review rule above before the next task's review closes. Fixes go back to the implementer and are re-reviewed.
- [ ] On the final head: `make test`, `make vuecheck` and `make package` pass, and all five CI jobs are green.
- [ ] The whole-branch review is clean and posted on PR #94.
- [ ] Release notes: the PR body gets a "Release notes" section with the two settings changes (a round keeps its start settings; the auto toggle keeps disk edits) and the safe saves. The release publisher uses a fixed note plus GitHub's generated notes and doesn't read PR bodies. So after the next 2.x release is published (by the maintainer, or an agent with their release go), check its GitHub Release text. If the three changes are missing, add them with `gh release edit <tag> --notes-file`, with the maintainer's go.
- [ ] #72 moves to Review, and the playtest runs through the playtest extension with the step 1 checks. Merge after the maintainer's go.
