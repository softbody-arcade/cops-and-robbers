# Split step 2: the server contract

Ticket: [#72](https://github.com/softbody-arcade/cops-and-robbers/issues/72), under [#69](https://github.com/softbody-arcade/cops-and-robbers/issues/69) and arcade-base#1. The authority is the arcade manager spec, arcade-base `docs/superpowers/specs/2026-11-27-arcade-manager-design.md` ("the spec"). The roadmap and seam map are in [the step 1 plan](../plans/2026-11-27-manager-game-split.md) ("The seam", "The 2.x steps"). The maintainer's decisions for this step are on #72 (2026-11-28).

## Why

Games become plugins of one manager (arcade-base#1). Step 1 moved the manager's services (store, messages, roster, colours, settings, traffic, panel plumbing, automatic rounds) into `server/CopsAndRobbers/arcade/`. `main.lua` is still where the manager and Cops and Robbers meet: 1,434 lines that start rounds, interpret every round effect, answer BeamMP's vehicle callbacks, track round cars, run spectating and drive the tick.

This step draws the line between them as a contract. The manager calls the game through hooks; the game uses the manager's services. Then `main.lua` is only wiring. At 3.0.0 the manager half moves to arcade-base mostly as files, and later games such as Street racing (grid, race, series, per-player upgrades) and Wheel racing (changes for everyone except last place) use the same contract.

## Goals

- **A game interface** (`cnr.game`) the manager reaches Cops and Robbers through, and nothing else.
- **The manager's remaining parts** move to `arcade/`: the cycle (lobby, round, results), the timer, spectating and parked bystanders, car tools and the round-vehicle registry, and the BeamMP vehicle and player callbacks.
- **`main.lua`** builds the manager and the game, binds BeamMP's handler names and loads data. Nothing else.
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

The maintainer's, recorded on #72 (2026-11-28):

1. **Hooks plus services** (see Approaches). The game is an object with hooks. The manager hands it a context of services. Cops and Robbers' effect list stays private to the game.
2. **Settings snapshot at round start.** A round uses the gameplay settings as they were when it started. Only the automatic-next setting stays live during a round. This is the one deliberate behaviour change (see "Behaviour change").
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
| `manifest()` | → `{ id, name, version, minPlayers }` | Cops and Robbers: `id = "cnr"`, `version` = `CNR_VERSION` handed in by `main.lua`, `minPlayers = 1` |
| `settingsDeclaration()` | → the game's declaration (`cnr.config.GAME`) | The manager combines it with `arcade.settings.GLOBAL` |
| `canStart(request)` | → `prepared` or `nil, reason` | `request` = `{ issuer, kind, text }` from the panel or automatic rounds. `prepared` carries the resolved choice (Cops and Robbers: the runner), so checking and starting never draw twice. The game runs first and keeps today's start sequence: ending a running practice, the build check, cancelling a pending automatic start, refusing with today's texts, watch-only practice for a player who sits out. The manager's own check of `minPlayers` (playing, not sitting-out players) runs after it, only for real rounds. For Cops and Robbers (`minPlayers = 1`) it can't fire, because the game already refuses with "Everyone is sitting out" |
| `start(prepared, snapshot, now)` | → nothing | `snapshot` is the copied effective settings for this round |
| `tick(now)` | → nothing | Called every 250 ms while the manager is in a round |
| `join(pid, name, now)` / `leave(pid, now)` | → nothing | `leave` sits at a fixed point in the manager's disconnect order. In 2.x, `join` drives the whole join sequence (see "Ordering") and calls the manager's services for the manager's parts, because today's order interleaves game and manager messages. At 3.0.0, when message order may change, the manager takes the generic parts (own colour, lobby, round-car list) |
| `checkVehicle(kind, pid, vid, decoded, facts)` | → `allow`, `reason` | Synchronous. `kind` is `"spawn"` or `"edit"`. Only the manager returns BeamMP's `0` or `1` and logs refusals. Whether an allowed spawn fulfils an expected round car is the manager's: when the game sends a setup it registers the expectation (`ctx.cars.expect(pid, model, config)`), and the car tools match a spawn against it, consume it and update the registry. Today's `roundSpawn` result of `vehicleAllowed` (`main.lua:971`) becomes that match |
| `onVehicle(kind, pid, vid, facts, now)` | → nothing | Placement, replacement, deletion and reset notices at their current points |
| `panelState()` / `lobbyFields()` | → data | `panelState` is built lazily, only when someone has the panel open, because computing it can pick the next runner. `lobbyFields` is computed every tick, as `lobbyState` is today; it draws nothing, and the lobby goes out when its content changes |
| `panelAction(pid, action, payload)` | → nothing | The game's panel actions and round commands. The manager keeps the subscriptions, the allow-list, the reply mirroring and the common commands (`auto`, `next`, `reload`) |
| `clientEvent(name, pid, data)` | → nothing | The game's own client events (`cnr_sight`, `cnr_setup`, …). The manager registers them on BeamMP and routes them here |

**The context (`ctx`)** the game gets holds the manager's services:
- messages, which return the delivery result;
- the roster, with sit-out queries and the sit-out snapshot accessor;
- the settings service;
- the clock;
- player colours and traffic;
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
- **#89 lands first** (validating a game's override values like config values: ranges, list shapes, both ends of each range), before the contract advertises overrides. Cops and Robbers declares none today.

### Behaviour change

Today, turning automatic rounds on or off with the panel during a round re-reads the whole `config.json` and replaces the running round's settings (`refreshConfig`, `main.lua:1365`). A gameplay setting edited on disk during a round can therefore take effect mid-round.

After this step, the round keeps its snapshot. The automatic-next setting is read live when the round ends, so `auto off` during a chase still prevents that round's next countdown. Panel saves and reloads stay locked during a round, as now.

A second, smaller fix: today the toggle writes the server's cached copy of `config.json` before reloading it, which silently erases a setting the host edited on disk. After this step, `set(key, text)` re-reads the file, changes only that key and saves, so the host's edit is kept and used from the next round on.

The golden traces don't edit `config.json` mid-round, so they stay identical. A new test pins the new behaviour, and the PR and release notes mention it.

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
- **Round end:** the end message, the empty car list, saving, the board update, then each player's top rows, as `tests/traces/round_caught.txt` shows. `Round:finish` has already cleared its state by then, so the end handling works from the captured end effect.
- **Effects:** handled in `ipairs` order, including the recursive handling when a setup fails.

Counters that must outlive a round object, such as grid and rebuild IDs, keep their current lifetime. Resetting them when a round object is created could make an old acknowledgement look current.

### Hot reload

As in step 1: `main.lua` builds fresh manager services and a fresh game on every load. No `arcade/` or `cnr/` module keeps state at module level. One 250 ms timer, and the start-up messages repeat. `tests/test_reload.lua` covers it.

### Checking the contract

- **Fake game (tests only):** a few dozen lines in `tests/` implementing the hooks with grid and race phases, a minimum of two players and a targeted rebuild of one player's car. Tests drive it through the manager: start, tick, finish, join and leave mid-round, a refused vehicle, an end with automatic next. Nothing ships.
- **Review rule:** every task review and the final review ask, for each hook or service the task touches: would Street racing or Wheel racing need this the same way, and is it on the right side? A reviewer flags any Cops and Robbers concept in `arcade/`.

## Automated acceptance

- Every golden trace in `tests/traces/` matches, unchanged.
- `make test`, `luajit`, `vuecheck`, `privacy` and `package` pass.
- A grep shows `arcade/` requires no `cnr.` module, and `main.lua` holds no game logic: no `current:` calls and no effect kinds.
- The fake game's tests pass.
- The snapshot test: a mid-round `auto off` still stops the next countdown, and a mid-round disk edit doesn't change the running round but is kept and used by the next round.
- The fake game's start with too few players is refused by the manager's `minPlayers` check.
- The reload test passes.

## In-game checks

The six checks from step 1, run by the playtest extension (the shared rules: an extension drives what it can):
1. a full round with a catch;
2. practice as runner with an AI catch;
3. a late joiner who spectates (with a second client, or deferred as before);
4. saving a setting;
5. the Rounds tab;
6. automatic rounds on, one round, off.

## Calls made after the builder check

A fresh reader checked this design for gaps on 2026-11-28. Four answers came from the parity rule and the code; they are my calls, marked here for the maintainer to check:
- the start order, with the manager's `minPlayers` check after `canStart`;
- the game's `join` hook driving the join sequence in 2.x;
- expected spawns owned by the car tools through `ctx.cars.expect`;
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
