# Split step 2: the server contract

Ticket: [#72](https://github.com/softbody-arcade/cops-and-robbers/issues/72), under [#69](https://github.com/softbody-arcade/cops-and-robbers/issues/69) and arcade-base#1. The authority is the arcade manager spec, arcade-base `docs/superpowers/specs/2026-11-27-arcade-manager-design.md` ("the spec"). The roadmap and seam map are in [the step 1 plan](../plans/2026-11-27-manager-game-split.md) ("The seam", "The 2.x steps"). The maintainer's decisions for this step are on #72 (2026-11-28).

## Why

Games become plugins of one manager (arcade-base#1). Step 1 moved the manager's services (store, messages, roster, colours, settings, traffic, panel plumbing, automatic rounds) into `server/CopsAndRobbers/arcade/`. `main.lua` is still where the manager and Cops and Robbers meet: 1,434 lines that start rounds, interpret every round effect, answer BeamMP's vehicle callbacks, track round cars, run spectating and drive the tick.

This step draws the line between them as a contract. The manager calls the game through hooks; the game uses the manager's services. Then `main.lua` is only wiring. At 3.0.0 the manager half moves to arcade-base mostly as files, and later games such as Street racing (grid, race, series, per-player upgrades) and Wheel racing (changes for everyone except last place) use the same contract.

## Goals

- **A game interface** (`cnr.game`) the manager reaches Cops and Robbers through, and nothing else.
- **The manager's remaining parts** move to `arcade/`: the cycle (lobby, round, results), the timer, spectating and parked bystanders, car tools and the round-vehicle registry, and the BeamMP vehicle and player callbacks.
- **`main.lua`** builds the manager and the game, binds BeamMP's handler names and loads data. Nothing else.
- **Saves never lose a file** (#92, folded into this step: the settings and car code this step touches rely on saves).
- **The contract is right for other games**, not just Cops and Robbers. A small fake game in the tests and a review rule check this (see "Checking the contract").

## Non-goals

- Game switching, more than one installed game, game discovery and version checks: these come with the base move (#37) and 3.0.0.
- The client side, round conditions (sky, weather, climate, lightning), the leaderboard store and per-viewer views: steps 3 and 4.
- Session and sequence numbers, `pcall` around game calls, cleanup without the game, and tagged reset scoring: step 5. This step only prepares for them (one dispatch point).
- Splitting `config.json` into a global file and a per-game file: 3.0.0 (maintainer, 2026-11-28).
- Renaming events, apps or files players or hosts see.

## Anti-goals

- **A contract shaped like Cops and Robbers.** No hook or service may assume runners, cops, catches, practice or evolving builds. Those stay inside `cnr/`.
- **A changed round.** A trace that differs, a message that moves in a tick, a lost log line or a different random draw is a failure, even if the game still plays.
- **A half move.** The manager may not reach into Cops and Robbers' state or effect kinds "for now". No `arcade/` module requires `cnr/`.

## Decisions

The maintainer's, recorded as decision comments on #72 (2026-11-28):

1. **Hooks plus services** (see Approaches). The game is an object with hooks. The manager hands it a context of services. Cops and Robbers' effect list stays private to the game.
2. **Settings snapshot at round start.** A round uses the gameplay settings as they were when it started. Only the automatic-next setting stays live during a round. It is one of two deliberate behaviour changes (see "Behaviour change").
3. **Checking the contract:** a small fake game in the tests only, plus a review rule: every task review and the final review check each contract item against Street racing and Wheel racing.
4. **Order:** this design and its plan are written now. Step 1 and the #84 batch are released before step 2's build starts.
5. **One `config.json`** through 2.x. The split into global and per-game files, stored outside the install folders, is part of 3.0.0.
6. **A host's disk edit survives a panel toggle.** Turning automatic rounds on or off re-reads `config.json` and changes only that key, so a setting the host edited on disk is kept and used from the next round on (see "Behaviour change").

The live server stays on 2.15.1 until 3.0.0, so 2.x releases are playtested locally and not deployed.

## How it works

### The contract

The game is built with `cnr.game.new(ctx)` and returns an object. The manager calls only these hooks, always through one dispatch function. Step 5 wraps that function in `pcall` and adds session tagging in one place.

| Hook | Arguments and return | Notes |
|---|---|---|
| `manifest(version)` (module function) | → `{ id, name, version, minPlayers, commands = { exact, prefixes }, actions, clientEvents }` | Read before anything is built. Cops and Robbers: `id = "cnr"`, `version` = the `VERSION` local `main.lua` passes, `minPlayers = 1`. The manager builds its panel allow-list and BeamMP registrations from `commands`, `actions` and `clientEvents` |
| `settingsDeclaration()` (module function) | → the game's declaration (`cnr.config.GAME`, functions-free) | The manager combines it with `arcade.settings.GLOBAL` and builds the settings service before the game |
| `new(ctx)` (module function) | → the game instance | Every hook below is called on it through the one dispatch function |
| `canStart(request)` | → `prepared` or `nil, reason` | A round starts only through `ctx.round:start(request)`: from a game start command, or from the manager for an automatic start with `command = "next"`. `ctx.round:start` runs `canStart`, the minimum-players check (`#prepared.participants`, a dense pid list, unless `prepared.solo`), the snapshot, then `start`. The game runs first and keeps today's start sequence and texts |
| `start(prepared, snapshot, now)` | → nothing | `snapshot` is the copied effective settings for this round |
| `tick(now)` | → nothing | Every 250 ms while the manager is in a round |
| `join(pid, name, now)` / `leave(pid, now)` | → nothing | `leave` sits at a fixed point in the disconnect order. In 2.x `join` drives the whole join sequence and calls the manager's services for the manager's parts |
| `checkVehicle(kind, pid, vid, decoded, facts)` | → `{ allow, reason, roundCar, notify }` | Synchronous. The game decides the policy and matching; the manager owns the round-car permissions (one-use permit, replacement right), returns BeamMP's `0` or `1` and logs refusals |
| `onVehicle(kind, pid, vid, decoded, facts, now)` | → nothing | `kind` is `spawn`, `edit`, `delete`, `reset` or `replaced`; called only when the verdict said `notify` (or for delete, reset and replaced) |
| `panelState()` / `lobbyFields()` | → data | `panelState` only while someone has the panel open; `lobbyFields` every tick |
| `panelAction(pid, action, payload)` | → nothing | A command that passes the allow-list, or an action named in `manifest.actions` |
| `clientEvent(name, pid, data)` | → nothing | For each name in `manifest.clientEvents` |
| `roundFinished()` / `settingsChanged(keys)` / `rulesChanged()` | → nothing | Notifications at today's positions: after a round ends (rules if changed), after a settings save (rules, panel push, board), after the automatic-rounds toggle or a reload (rules, unconditionally) |

**The context (`ctx`)** the game gets holds the manager's services:
- messages, which return the delivery result;
- the roster, with sit-out queries and the sit-out snapshot accessor;
- the settings service;
- the clock;
- player colours;
- traffic, where the caller passes the number of car slots to keep free instead of today's `practice` flag (`arcade/traffic.lua:8`). Cops and Robbers passes 3 only for the practice issuer's own allowance (`main.lua:212`). The traffic count in `cnr_rules` keeps 1, as today (`main.lua:687`), so How to play shows the same number;
- the car tools;
- spectating and parking;
- panel and lobby pushes;
- `ctx.round:finish(result, audience, scheduleNext)`.

**Car tools** take explicit owners, vehicle IDs, targets, poses and configs. Cops and Robbers maps its negative AI IDs to an owner and a vehicle itself.

### Who owns what after this step

| Today in `main.lua` | Moves to `arcade/` (manager) | Stays in or moves to `cnr/` (game) |
|---|---|---|
| `reply`, `broadcast`, `pickVehicle`, `planStart`, `setup`, `requestSetup`, `rebuild`, `applied` effects | Message transport, the car-pick request, placement and its delivery result, expected spawns, targeted rebuild and its acknowledgement | Interpreting each effect: recipients, grid, roles, allowed changes, payloads. Handling a failed setup at once (today `current:setupFailed`, `main.lua:436`). `applied` stays the evolving mode's acknowledgement |
| `spectate`, `setupAI`, `roundEnd` effects | Spectator delivery and the parked-player set, vehicle capacity and outstanding operations, normal end cleanup, scheduling the next round | Who watches whom, timing and sky fields, AI roles and the timeout wording, the outcome, the audience (practice ends go to the issuer only) and whether the end allows an automatic next |
| `countdown`, `runnerGo`, `release`, `state`, `penalty`, `penaltyEnd`, `live`, `spotted`, `lastSeen`, `heli`, `runnerShown`, `nearestCop`, `record` effects | Only the existing message and storage primitives | All of it. Lightning stays with the current countdown and tick logic until step 3; leaderboard storage and views stay with the game until step 4 |
| `firstVid`, `vidFor`, `confirmedVid`, `setRoundVid`, `roundCarKeys`, `pushRoundCars`, `clearRoundCars`, `carFor`, the four vehicle callbacks | The round-vehicle registry: physical `(owner, vid)` identity, provisional, confirmed and expected status, pre-round exclusions, position sampling, traffic exclusions, and publishing the sorted, de-duplicated `cnr_roundCars` list (only confirmed participant cars, as today) | Which models and configs are allowed, AI slot policy, sight invalidation, the evolving mode's part-change rules, reset scoring |
| `cnrTick`, start, stop, automatic rounds, join, leave, the panel and start-up | The cycle and its timer, lifecycle ordering, common commands and BeamMP registration | Runner selection, practice, gas stations, builds, panel content and the round commands (`start`, `test`, `go`, `stop`, `end`, `reroll`, `sky`, `addstation`, `removestation`, build and apply) |

The manager's cycle has three states: **lobby**, **round** and **results**. Cops and Robbers' own phases (picking, prep, countdown, head start, chase) stay inside `cnr.round`. Its panel may keep showing `idle` after a round while the manager is in results.

### Settings

- The settings service (`arcade.settings.new(...)`) owns the raw and effective config. It gains `get(key)`, `set(key, text)`, `apply(values)`, `load()` and `snapshot()`, reusing today's validators, load and save. `autoRounds.register` receives this service directly. The ad-hoc `ctx.settings` `{get, set}` adapter in `main.lua` goes (#72, moved from #82).
- `snapshot()` returns a deep copy of the effective settings, with list values copied too. The manager takes one at round start and hands it to `game:start`.
- `set(key, text)` re-reads `config.json` first and changes only that key, apart from dropping retired entries (`RETIRED_KEYS`, `RETIRED_VALUES`), as every save does today (`tests/test_main.lua:514`). If the file is missing it starts from an empty table, as today. If the file can't be read or parsed, `set` writes nothing, keeps the live value and returns an error the panel shows. It never saves a table it couldn't load.
- **Saving never loses the file.** `store.write` today removes the original before the new file is in place, and ignores write, close and rename failures. That is #92, which this step fixes, because the settings and car code it touches rely on saves. A save writes a temporary file, checks every step, and replaces the original only when the new file is complete. A failed save keeps the original bytes and the live value, and returns an error the panel shows.
- **No game code in the declaration.** Today Cops and Robbers' declaration carries a function, `GAME.fix`, which the settings service calls directly (`arcade/settings.lua:133`), outside the single dispatch point. It becomes a declarative `RANGES` table: pairs whose maximum may not be below their minimum, like `TIMING_RANGES` without the whole-number and positive rules. Cops and Robbers declares `copSpawnMinMeters = "copSpawnMaxMeters"`. `merge` checks `RANGES` where it called `fix`, before `TIMING_RANGES`, with the same warning text, so the warnings and their order are unchanged.
- **What clients see:** the rules message (`cnr_rules`, gameplay settings only) carries the round's snapshot while a round runs, and the live settings in the lobby and results. It goes out on join and on the toggle unconditionally, as today. The `auto_next` golden needs the toggle's unchanged rules broadcast (`tests/traces/auto_next.txt:388`). It also goes out once more when a round ends, and only that new send is skipped when it equals what was last sent. A change held back by the snapshot therefore reaches connected players right after the round. The goldens stay identical, because no golden changes settings mid-round.
- **#89 lands first** (validating a game's override values like config values: ranges, list shapes, both ends of each range), before the contract advertises overrides. Cops and Robbers declares none today.

### Behaviour change

Today, turning automatic rounds on or off with the panel writes the server's cached copy of `config.json` first, then re-reads it and replaces the running round's settings (`main.lua:1356-1366`). A setting the host edited on disk is therefore silently erased, and the running round's settings are swapped for the reloaded ones.

After this step:
- **The disk edit is kept** (decision 6). `set` re-reads the file, changes only the toggled key and saves.
- **The running round keeps its snapshot** (decision 2), so the kept edit doesn't change it. The next round uses the edit.
- **The automatic-next setting is read live** when the round ends, so `auto off` during a chase still prevents that round's next countdown.
- Panel saves and reloads stay locked during a round, as now.

The golden traces don't edit `config.json` mid-round, so they stay identical. A regression test shows the edit surviving a mid-round toggle, the running round keeping its rules, and the next round using the edit. The PR and release notes mention both changes.

### Ordering

The traces pin message order. The new code keeps these orders exactly:

- **Tick:**
  1. panel and lobby pushes;
  2. a due automatic start;
  3. stop if no round is running;
  4. pending AI setup, or its timeout with the notice;
  5. position sampling for the round's players;
  6. lightning announcement;
  7. the game's tick.
- **Join** (driven by the game's `join` hook in 2.x):
  1. `cnr_mode`;
  2. own colour;
  3. rules;
  4. lobby;
  5. station request;
  6. the game's join;
  7. park a bystander during practice;
  8. queued change;
  9. the round-car list if a round is running.
- **Disconnect:**
  1. the roster's early cleanup;
  2. the game's leave;
  3. the roster's late cleanup;
  4. the round-car list push.
- **Round end** (the `roundEnd` effect, then any `record` effect):
  1. each parked bystander gets `cnr_parkBystanderCars` with `on = false`;
  2. `cnr_roundEnd` to the end's audience: everyone, or only the issuer for a practice end;
  3. the per-round tables are cleared;
  4. the empty `cnr_roundCars` goes out only if a non-empty list was published before;
  5. the next round is scheduled if allowed.

  A recorded round (not practice, not cancelled) then has its separate `record` effect: save, board update, each player's top rows. `tests/traces/round_caught.txt` shows the recorded case, and `tests/traces/practice_runner.txt` the practice case. `Round:finish` has already cleared its state by then, so the end handling works from the captured end effect.
- **Effects:** handled in `ipairs` order, including the recursive handling when a setup fails.

**Grid and rebuild IDs keep their current lifetime.** They are module-level counters in `cnr/round.lua` (`round.lua:33`), so they survive a new round object and a hot reload of `main.lua`, because the module stays cached. Resetting them could make an acknowledgement from before the reset look current. They are the one deliberate exception to "no module-level state". A test replays an old grid and rebuild acknowledgement after a reload. The old rebuild ID must not mark the player ready for the current rebuild, which stays pending. The rest of the `cnr_myVehicle` report (registering the car, placement log, traffic, car list) behaves as today.

### Hot reload

As in step 1: `main.lua` builds fresh manager services and a fresh game on every load. No `arcade/` module keeps state at module level, and no `cnr/` module either, apart from the grid and rebuild counters above. One 250 ms timer, and the start-up messages repeat. `tests/test_reload.lua` covers it.

### Checking the contract

- **Fake game (tests only):** a few dozen lines in `tests/` implementing the hooks with grid and race phases, a minimum of two players and a targeted rebuild of one player's car. Tests drive it through the manager: start, tick, finish, join and leave mid-round, a refused vehicle, an end with automatic next. Nothing ships.
- **Review rule:** every task review and the final review ask, for each hook or service the task touches: would Street racing or Wheel racing need this the same way, and is it on the right side? A reviewer flags any Cops and Robbers concept in `arcade/`.

## Automated acceptance

- Every golden trace in `tests/traces/` matches, unchanged.
- `make test`, `luajit`, `vuecheck`, `privacy` and `package` pass.
- A grep shows `arcade/` requires no `cnr.` module, and `main.lua` holds no game logic: no `current:` calls and no effect kinds.
- The fake game's tests pass.
- The snapshot test: a mid-round `auto off` still stops the next countdown, and a mid-round disk edit doesn't change the running round but is kept and used by the next round.
- The fake game's start with too few players is refused by the manager's `minPlayers` check, and a solo start passes it. A Cops and Robbers watch-only practice by a player who sits out still starts.
- Round-car replacement after a deletion (`tests/test_main.lua:2470`) still passes: wrong config refused, replacement published at once, second spawn refused.
- `set` on an unreadable or corrupt `config.json` writes nothing and keeps the live value. A save whose write, close or rename fails keeps the original file and the live value, and the panel shows the error (#92).
- `auto on` on a legacy config still drops the retired entries (`tests/test_main.lua:514`).
- In driven practice, a human's spawn followed by a tick before `cnr_myVehicle` doesn't send `cnr_setupAI` early.
- An automatic start goes through `ctx.round:start` with `command = "next"` and draws the same runner as today.
- `cnr.config`'s declaration holds no functions, and a `copSpawnMaxMeters` below `copSpawnMinMeters` gives today's warning.
- An old grid or rebuild acknowledgement replayed after a reload doesn't complete the current grid or rebuild.
- A reroll's replacement while the old car still exists is accepted once and published at once (`tests/test_main.lua:2470`), and a first round car is published only after `cnr_myVehicle`.
- The reload test passes.

## In-game checks

The six checks from step 1, run by the playtest extension (the shared rules: an extension drives what it can):
1. a full round with a catch;
2. practice as runner with an AI catch;
3. a late joiner who spectates (with a second client, or deferred as before);
4. saving a setting;
5. the Rounds tab;
6. automatic rounds on, one round, off.

## Refinements from planning

The plan review on 2026-11-28 settled these contract details. They refine the hook table above without changing the approach:

- **Static game functions.** `manifest(version)` and `settingsDeclaration()` are functions of the game module, not of an instance, because the settings service must exist before the game is built. The manifest also lists `commands` (`exact` words and `prefixes`) and `clientEvents`.
- **Two notification hooks.** `roundFinished()` and `settingsChanged(keys)` let the game send its own output at today's positions: the rules after a round ends, and the rules, a panel push and the board after a settings save.
- **Vehicle verdicts.** `checkVehicle` returns a table `{ allow, reason, roundCar, notify }`. `onVehicle(kind, pid, vid, decoded, facts, now)` also receives the decoded packet. `notify = false` covers today's early accepts. A replaced confirmed car is reported as `onVehicle("replaced", …)`, so sight invalidation goes through dispatch too.
- **Car tools.** `setup`, `requestPick`, `rebuild` with a per-target delivery map and pending acknowledgements, the round-car permissions, identity and publication. Spectating and parking are one `spectators` service.
- **Safe saves keep today's file-system order.** The new file is written and checked first, then the original is removed and the new file renamed into place. If the rename fails, the original bytes are restored. So the golden traces still show `fs remove` then `fs write`.
- **The panel's automatic-next indicator** reads the live setting, and the delay before the next round comes from the round's snapshot.

## Calls made after the builder check

A fresh reader checked this design for gaps on 2026-11-28. Four answers came from the parity rule and the code; they are my calls, marked here for the maintainer to check:
- the start order, with the manager's `minPlayers` check after `canStart`;
- the game's `join` hook driving the join sequence in 2.x;
- round-car permissions owned by the car tools (`ctx.cars.permit` and the replacement right);
- only `panelState` lazy.

The disk-edit fix (decision 6) was the maintainer's.

## Choices left to the builder

- Module names inside `arcade/` (for example `arcade.cycle`, `arcade.cars`, `arcade.spectate`), and the exact field names in `facts`, `request` and `prepared`.
- How the work is cut into tasks, as long as every task keeps the traces green. Suggested order:
  1. `arcade.vec` (`git mv`, with `cnr.vec` left as a re-export, and the copied helpers in `arcade/traffic.lua` removed) and the sit-out accessor;
  2. settings service methods and the snapshot;
  3. car identity and spectating behind today's callers;
  4. move the effect handling into `cnr.game` intact, then replace its branches with service calls one by one;
  5. the cycle and the entry points;
  6. the fake game.
- Whether `cnr.round` stays a separate module that `cnr.game` drives (expected), or merges.

## Approaches

1. **Shared effect list.** `cnr.round` keeps emitting effects; the manager handles a fixed set of "manager" effect kinds and passes the rest to the game.
   - Smallest first move.
   - But setup, AI setup and round end each mix a game decision with manager work, so the manager would need callbacks into the game halfway through an effect.
   - Every later game would have to speak Cops and Robbers' effect language.
2. **Hooks plus services** (chosen). The game is called through hooks and uses services. Its effects stay private.
   - Fits the spec's "the manager calls the game, the game uses tools".
   - Fits the existing flow: a failed setup send is handled at once (`main.lua:436`).
   - One car-tool call covers all of Cops and Robbers' players, one racer's upgrade, or everyone except last place.
3. **Hooks returning data.** As 2, but hooks return actions instead of calling services.
   - Easy to inspect as data.
   - But a setup's delivery decides whether the next car may be touched, so the interpreter needs results and continuations, and vehicle checks need immediate answers.
   - The largest rewrite for the least gain. Worth revisiting only if validating a whole batch before any world change becomes a requirement.

A research agent compared the three against the spec and the code on 2026-11-28; the maintainer accepted its pick.
