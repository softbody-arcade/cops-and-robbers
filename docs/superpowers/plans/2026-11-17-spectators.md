# Spectators and Sitting Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A player who joins mid-round, and every player with Sit out on when a round is set up, spectates the round (camera on any round car or free camera) instead of being placed into it.

**Architecture:** Spectators stay outside `round.players` (approach (a)), so every existing rule already skips them. The round snapshots the server's per-session Sit out set at Start and emits a `spectate` effect instead of a `setup` for sit-outs (at the vehicle pick) and new mid-round joiners; rejoins keep `leftPlayers`. The client's new `spectator.lua` parks the player's own cars (snapshot, then delete; BeamMP syncs) and respawns them at the round end, and redirects the game's own switch-vehicle cycle to round cars.

**Tech Stack:** Lua 5.3 server plugin, LuaJIT GE client extension, Vue 3 UI apps; `make test`, `make vuecheck`, `make package`.

**Spec:** `docs/superpowers/specs/2026-11-17-spectators-design.md`

## Global Constraints

- No code comments, no emojis; LuaJIT-safe client code (no `goto`, `//`, bit operators; `vec3` is cdata).
- No version bump, no `TODO.md` edit.
- `round.lua` changes stay in the joining, role and setup paths (`start`, `vehiclePicked`, `setupFor`, `playerJoined`, `playerLeft`).
- Copy, verbatim: "Sit out" (off) / "Play" (on); "Need two players who aren't sitting out"; "SPECTATING · <name>" with the name or "free camera".
- Practice rounds unchanged. The lobby's online count includes spectators.

## Review Focus

1. A sit-out player who is in free camera or watching someone else's car when the round is set up still has their own car parked (own cars come from `MPVehicleGE.getOwnMap`, not the player vehicle). Test in Task 4.
2. New car (reroll) re-sends the spectate event: the client must not park again and lose the snapshot. Test in Task 4.
3. Cycling from free camera or into a traffic car lands on a round car. Test in Task 4.
4. Sit out toggled during picking applies to the next round, not this one (the round's snapshot). Test in Task 1.
5. A spectator spawning a car mid-round through any menu is refused by the server. Test in Task 2.

---

### Task 1: Spectators in the round (`round.lua`)

**Files:**
- Modify: `server/CopsAndRobbers/cnr/round.lua` (`clear`, `setupFor`, `start`, `vehiclePicked`, `playerJoined`, `playerLeft`)
- Test: `tests/test_round.lua`

**Interfaces:**
- Produces: `Round:start(now, runnerId, issuerId, players, opts)` reads `opts.sittingOut` (set of pids), stored as `self.sittingOut`; round players never include them.
- Produces: effect `{ kind = "spectate", pid, phase, countdownRemaining?, headStartRemaining?, chaseElapsed?, heli? }` from `vehiclePicked` (for every pid in its `players` argument that sits out) and from `playerJoined` (a join from prep onward with no `leftPlayers` entry). `Round:timing(now, e)` fills phase, times and heli for both `setup` and `spectate`.

- [ ] **Step 1: Write the failing tests**
  - `a player sitting out is no round player and gets a spectate at the pick`: `start(0, 1, 2, players, { sittingOut = { [3] = true } })`; `players[3] == nil` in picking; after `vehiclePicked(..., players)`: no `setup` for 3, `spectate` for 3 with `phase == "prep"`, setups for 1 and 2.
  - `the sit-out snapshot holds for the whole round`: the caller's set changed after `start` (3 added, a sit-out removed) changes nothing at `vehiclePicked` and at a reroll's second pick.
  - `a mid-round joiner spectates with the current phase` (replaces the cop-setup join test): countdown → `spectate` with `countdownRemaining` 1; headstart → `headStartRemaining` 5; running → `chaseElapsed` 30 and `heli` when up; `players[pid] == nil`, no `setup`, no `placing`; idle and practice → `{}`.
  - `a join during picking is a player at the pick`: unchanged behaviour.
  - `a cop who leaves in prep or the countdown and rejoins resumes as a cop` (`leftPlayers` from prep onward).
  - Convert the placement-grace, `runnerShown`, chase-elapsed and sight-by-name tests that used a new joiner ("Dan", "Zed", "Cid") into rejoins (Ann leaves as pid 3, rejoins as pid 4) or spectate checks.

- [ ] **Step 2: Run** `make test` — the new tests fail (no `spectate` effect).
- [ ] **Step 3: Implement** `without(players, set)`, `self.sittingOut` (reset in `clear`), `Round:timing`, `Round:spectateFor(now, pid)`; `playerJoined` returns `{ spectateFor }` for a non-rejoin from prep onward; `playerLeft` records `leftPlayers` in every state after picking.
- [ ] **Step 4: Run** `make test` — all pass.
- [ ] **Step 5: Commit** `feat: sitting-out players and mid-round joiners spectate instead of joining the round`

### Task 2: Sit out on the server (`main.lua`)

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/cnr/panel.lua` (`playerRows` passes `sitOut`)
- Test: `tests/test_main.lua` (the `MP.GetPlayers` stub returns every `env.names` entry), `tests/test_panel.lua`

**Interfaces:**
- Consumes: Task 1's `opts.sittingOut` and `spectate` effect.
- Produces: client→server `cnr_sitOut` `{ on = boolean }`; server→client `cnr_sitOut` `{ on = boolean }` (the answer) and `cnr_spectate` `{ runnerId, runnerName, phase, countdownRemaining, headStartRemaining, chaseElapsed, heli, sky }`.

- [ ] **Step 1: Write the failing tests**
  - `Sit out is stored per player, answered and cleared on disconnect`: `cnr_sitOut {"on":true}` → answer `{"on":true}`; malformed (`{}`, `{"on":"yes"}`, not JSON) changes nothing and sends nothing; after `onPlayerDisconnect` the next Start includes them.
  - `Start needs two players who aren't sitting out`: two online, one sitting out → reply "Need two players who aren't sitting out", no round.
  - `a sitting-out player is never the runner`: three online, Kim sitting out with 0 runs → `start next` never picks Kim; `start kim` → "Kim is sitting out"; `start again` with Kim as the last runner → same.
  - `Sit out during a round applies next round and says so`: notice "You sit out from the next round" / "You play again from the next round"; this round keeps its players; the next Start excludes or includes them; the toggle persists across rounds.
  - `a sitting-out player gets cnr_spectate at the pick, with the round's sky`; `a mid-chase joiner gets cnr_spectate, round cars and no setup or traffic go-ahead` (replaces the setup-based joiner tests, which become rejoins).
  - `a spectator can't spawn a car until the round ends`: spawn returns 1 with the notice "You can't spawn a car while spectating"; allowed again after the round end; practice by someone else doesn't block anyone.
  - `New sky reaches spectators`; `the panel marks sitting-out players and Next skips them`; the traffic note counts only players who aren't sitting out.

- [ ] **Step 2: Run** `make test` — the new tests fail.
- [ ] **Step 3: Implement** `sitOut` table, `playing(players)`, `cnrOnSitOut` (registered as `cnr_sitOut`), the minimum and runner checks in `handlers.start`, `opts.sittingOut` copy, the `spectate` effect in `applyEffects`, `spectating(pid)` refusal at the top of `cnrOnVehicleSpawn`, `handlers.sky` to every online player in a real round, `sitOut` and `playing` in `panelState`/`playerEntries`/`nextRunnerName`.
- [ ] **Step 4: Run** `make test` — all pass.
- [ ] **Step 5: Commit** `feat: a per-session Sit out on the server, two players to start, spectators get the round's state`

### Task 3: The Sit out toggle and the spectating HUD

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/hud.lua`, `hudfeed.lua`, `client/lua/ge/extensions/copsAndRobbers.lua` (`M.ui` action `sitOut`, `cnr_sitOut` handler, reset on `cnr_mode`)
- Create: `client/ui/modules/apps/CopsAndRobbersHud/HudSpectate.vue`
- Modify: `HudLobby.vue`, Hud `app.vue`, `client/ui/modules/apps/CopsAndRobbersPanel/PanelRound.vue` ("sitting out" tag)
- Test: `tests/test_hud.lua`, `tests/test_client.lua`

**Interfaces:**
- Produces: `hudfeed.sitOut(on)`; `hudfeed.update(clock, info)` takes `info.spectate = { name = string|nil }`.
- Produces: payload `lobby.sitOut`; in round mode for a spectator, `payload.spectate = { name, time?, limit?, heli?, sitOut, apps }` and no `prep`, `status`, `change` or role centre; `driving` false.

- [ ] **Step 1: Write the failing tests**
  - hud: `a spectator's payload shows who is watched, the clock and the helicopter, and no role actions` (name "Bob", `nil` → "free camera"; `time` "3:12" and `limit` from rules; countdown in the centre; `status`, `prep`, `catch.visible` absent or false; `driving` false).
  - hud: `the lobby carries Sit out` and `a sitting-out lobby says so` ("You're sitting out").
  - client: `Sit out on the card goes to the server and the answer flips the button` (`M.ui({ action = "sitOut", on = true })` sends `cnr_sitOut { on = true }`; `cnr_sitOut {on=true}` → `hud().lobby.sitOut`); `a new cnr_mode clears Sit out`.
- [ ] **Step 2: Run** `make test` — fail.
- [ ] **Step 3: Implement** the payload, hudfeed state, the `sitOut` UI action and handler; `HudSpectate.vue` (a chase-style top line "SPECTATING · name", clock, helicopter; buttons Sit out/Play, How to play, Leaderboard, Host panel) and the lobby button next to Hide (`icons.pause` / `icons.play`).
- [ ] **Step 4: Run** `make test` and `make vuecheck` — pass.
- [ ] **Step 5: Commit** `feat: Sit out on the lobby card and a spectating card in the HUD`

### Task 4: Spectating on the client

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/spectator.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`, `inputs.lua`, `tests/client_stubs.lua` (`getJBeamFilename`, `MPVehicleGE.getOwnMap`, `be.enterVehicle`)
- Test: `tests/test_client.lua`

**Interfaces:**
- Produces: `spectator.park()` (no-op once parked), `spectator.restore()`, `spectator.drop()`, `spectator.parked()`; `spectator.carIds(owners, vehicles, exists) -> sorted game ids`; `spectator.cycleTarget(ids, fromId, toId, dir) -> id|nil` (nil when `toId` is already a round car or there are none); `spectator.watchedName() -> string|nil` (nil in free camera).
- Produces: `inputs.lock(on, requestReset, freeCam, spectator)`; with `spectator` the switch-vehicle and free-camera actions stay open.
- Consumes: Task 2's `cnr_spectate`, Task 3's `hudfeed.update` `spectate` field.

- [ ] **Step 1: Write the failing tests**
  - `a sitting-out player's car is parked on spectate and comes back where it stood at the round end` (snapshot model, config, upright pose; `delete`; free camera; at `cnr_roundEnd` `spawnNewVehicle(model, { config, pos, rot })`), `… and on a cancel`.
  - `the parked car is found while watching another car` (Review Focus 1); `a second spectate (New car) keeps the parked car` (2).
  - `a map change or leaving drops the parked car and leaves nothing behind` (no spawn on the next round end; locks, sky, heli and spectate HUD cleared; `onExtensionUnloaded` too).
  - `a spectator's locks leave switching cars and free camera open` (while the vehicle selector, walking and teleports stay locked; no `setGameCamera`).
  - `cycling lands on round cars only` (from free camera, from a traffic car, both directions, wraps; `be:enterVehicle` with the round car) (3).
  - `spectating shows the countdown, the chase clock and the helicopter, and the name of the car watched`; `a spectator sees the result card`.
- [ ] **Step 2: Run** `make test` — fail.
- [ ] **Step 3: Implement** `spectator.lua`; in `copsAndRobbers.lua` `onSpectate` (state, heli, sky, timers, locks, park), the `onVehicleCycleSwitchPerformedByUser` hook, `spectating` in `onSky`, `onRoundEnd`, `updateHeli`, `onUpdate` and `endRound` (restore unless leaving, drop when leaving); `onRoundSetup` clears spectating.
- [ ] **Step 4: Run** `make test` — pass.
- [ ] **Step 5: Commit** `feat: spectators watch any round car or free camera; a sitting-out player's car is parked for the round`

### Task 5: Docs

**Files:** `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`

- [ ] **Step 1:** README (HUD lobby card, spectating), FEATURES (round flow, late joiners, Sit out, spectating, locks), How to play (Basics: Sit out and spectating with Tab / Ctrl+Tab / Shift+C by default), DEPENDENCIES (the game and BeamMP calls spectating relies on and what to check on update).
- [ ] **Step 2: Run** `make test`, `make vuecheck`, `make package` — all pass.
- [ ] **Step 3: Commit** `docs: spectators and Sit out`
