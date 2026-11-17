# Practice While Sitting Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Starting practice with Sit out on runs an AI-only practice round (an AI runner against two AI cops) that the player spectates exactly as a sitting-out player spectates a real round.

**Architecture:** The server keeps practice as it is and adds one flag, `aiOnly`, taken from the issuer's Sit out at `test`. With it the round holds three AI players and no human; at the pick the issuer gets the existing `spectate` effect instead of a `setup`, and `setupAI` carries three AI cars and `aiOnly`. The client's existing spectator mode does the rest (parking, Tab/Ctrl+Tab, free camera, the SPECTATING card); `ai.lua` learns to place the cars around a given spot and to flee from the nearest AI cop when no player cop exists.

**Tech Stack:** Lua 5.3 server plugin, LuaJIT GE client extension, Vue 3 UI apps; `make test`, `make vuecheck`, `make package`.

**Spec:** the user's ask ("Sit out should work for practice as well, that way I can just spectate 3 AIs") and the decided design in the task brief; background in `docs/superpowers/specs/2026-11-17-spectators-design.md`.

## Global Constraints

- No code comments, no emojis; LuaJIT-safe client code (no `goto`, `//`, bit operators; `vec3` is cdata).
- No version bump, no `TODO.md` edit.
- AI names and colours as practice today: "AI runner" (`#d83a2c`), "AI cop 1" (`#1f6fe0`), "AI cop 2" (`#6fb0ff`); AI ids `AI_FIRST`, `AI_FIRST - 1`, `AI_FIRST - 2`.
- Everything else is practice as today: AI behaviour, round end, result card, Stop, no records or leaderboard entries, events only to the issuer.
- Placement: the AI runner goes on the nearest road to the parked car's spot (the camera's position when the player had no car), facing the car's heading; the AI cops search their spots 50–150 m by road around the runner's spot (`copSpawnMin`/`copSpawnMax`), indices 1 and 2.
- Panel copy: with Sit out on, the two practice buttons become one, "Practice: watch the AI".

## Review Focus

1. The issuer leaves during an AI-only practice: the round must cancel, though the issuer is not in `players`. Test in Task 1.
2. The sitting-out issuer's game spawns the AI cars: those spawns must not be refused as a spectator's. Test in Task 1.
3. Watching an AI car makes it the player vehicle and an own car: the HUD must name it "AI runner" (not the player), and the AI runner must never be told to flee from itself. Test in Task 2.
4. New car in an AI-only practice: the parked car is kept and the new AI cars spawn around the same spot. Test in Task 2.
5. New sky in an AI-only practice reaches the issuer, who is not a round player. Test in Task 1.

---

### Task 1: AI-only practice on the server

**Files:**
- Modify: `server/CopsAndRobbers/cnr/round.lua` (`clear`, `start`, `vehiclePicked`, `playerLeft`)
- Modify: `server/CopsAndRobbers/main.lua` (`handlers.test`, `applyEffects` `spectate` and `setupAI`, `handlers.sky`, `lobbyState`)
- Test: `tests/test_round.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `Round:start(now, nil, issuerId, players, { test = true, aiOnly = true, ... })`; `self.aiOnly`; `players` holds only the three AI ids; no role is needed.
- Produces: at `vehiclePicked`, effect `spectate` for the issuer (phase "prep") and `{ kind = "setupAI", pid, ai, aiOnly = true }` with three entries (runner index 1, cops index 2 and 3).
- Produces: client events `cnr_spectate { ..., practice = true }` and `cnr_setupAI { ..., aiOnly = true }`.

- [ ] **Step 1: Write the failing tests**
  - round: `practice while sitting out: an AI runner and two AI cops, the issuer spectates` — `start(0, nil, 1, players, { test = true, aiOnly = true })` without a role → picking; `vehiclePicked` → no `setup`, `spectate` for 1 with phase "prep", `setupAI.aiOnly == true`, three AI with the names, roles and colours above; `players[1] == nil`; `runnerId == AI_FIRST`.
  - round: `an AI-only practice is caught by its AI cops and records nothing`, and `the issuer leaving cancels an AI-only practice` (Review Focus 1).
  - main: `practice while sitting out runs the AI alone and the issuer spectates` — `sitOut 1`, `test runner` and `test cop` both → `cnr_spectate` to 1 with `practice == true`, no `cnr_roundSetup`, `cnr_setupAI` with 3 AI and `aiOnly`; the issuer's AI spawns are allowed (Review Focus 2); `cnr_aiVehicles` → caught → `cnr_roundEnd` only to 1, no leaderboard file.
  - main: `New sky reaches whoever watches an AI-only practice` (Review Focus 5); `the lobby names whoever watches the AI practise` (`"practice":"Reinder"`).
- [ ] **Step 2: Run** `make test` — the new tests fail.
- [ ] **Step 3: Implement** the `aiOnly` branch in `start` and `vehiclePicked`, the issuer check at the top of `playerLeft`, `aiOnly = sitOut[pid] == true` in `handlers.test`, `practice` in the spectate payload and no `spectators` mark for a practice issuer, `aiOnly` in the `setupAI` payload, `handlers.sky` sending to the issuer in practice, `MP.GetPlayerName` fallback in `lobbyState`.
- [ ] **Step 4: Run** `make test` — all pass.
- [ ] **Step 5: Commit** `feat: practice with Sit out on runs the AI alone and the issuer spectates`

### Task 2: Watching the AI on the client

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/ai.lua`, `spectator.lua`, `client/lua/ge/extensions/copsAndRobbers.lua`
- Test: `tests/test_client.lua`

**Interfaces:**
- Consumes: Task 1's `cnr_spectate` and `cnr_setupAI.aiOnly`.
- Produces: `ai.setup(d, center, heading)` (center and heading optional, own vehicle otherwise); `ai.nameOf(gameId) -> string|nil`; `spectator.spot() -> pos, dir` (the first parked car, nil when none).

- [ ] **Step 1: Write the failing tests**
  - `watching AI practice: the runner starts on the road where the parked car stood and the cops around it` — spectate then `cnr_setupAI` with `aiOnly`: runner spawned at the road node `(0, 60, 0)` from a car at `(0, 20, 0)`, cops' spot searches centred on the runner's spot with indices 1 and 2; with no car, the camera's position is the centre.
  - `the AI runner flees from the nearest AI cop and switches to a nearer one`, never from the watched car (Review Focus 3).
  - `Tab goes through the AI cars and the card names them` ("AI runner", "AI cop 1") (Review Focus 3).
  - `New car in AI practice keeps the parked car and respawns the AI around the same spot` (Review Focus 4); `the round end puts the car back and removes the AI cars`.
  - `the AI cars get their lights while you watch`.
- [ ] **Step 2: Run** `make test` — fail.
- [ ] **Step 3: Implement** the placement and flee targeting in `ai.lua` (nearest cop re-checked once a second while fleeing), `spectator.spot()`, the centre in `onSetupAI`, AI ids in `roundCarIds`, `ai.nameOf` before `spectator.watchedName` in the HUD feed, AI lights and light sync while spectating.
- [ ] **Step 4: Run** `make test` — pass.
- [ ] **Step 5: Commit** `feat: watch an AI-only practice: placement around your car, the runner flees the nearest cop, Tab goes through the AI`

### Task 3: The panel button and the docs

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/PanelRound.vue`, `client/lua/ge/extensions/copsAndRobbers.lua` (`onPanelState` adds `sitOut`), `copsAndRobbers/hudfeed.lua` (`sittingOut()`)
- Modify: `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, `client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`
- Test: `tests/test_client.lua`

- [ ] **Step 1: Write the failing test** `the panel knows you sit out` — after `cnr_sitOut {on=true}`, `cnr_panelState` reaches `CnRPanel` with `sitOut == true`; after `{on=false}`, `sitOut == nil`.
- [ ] **Step 2: Run** `make test` — fail.
- [ ] **Step 3: Implement** the flag and the single "Practice: watch the AI" button (sends `test cop`); docs: README (Sit out, panel, MaxCars note), FEATURES (Spectators and Sit out, practice table, traffic), How to play (the Sit out paragraph: practice with Sit out on lets you watch the AI), DEPENDENCIES (the in-game check and the AI flee target).
- [ ] **Step 4: Run** `make test`, `make vuecheck`, `make package` — all pass.
- [ ] **Step 5: Commit** `feat: the panel offers Practice: watch the AI while you sit out; docs`
