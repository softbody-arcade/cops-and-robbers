# Leaderboard App and Player Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A clickable leaderboard app with Runners, Cops and Players tabs, backed by a fresh format-2 leaderboard. Each run records cops, sight and hidden time.

**Spec:** `docs/superpowers/specs/2026-11-15-leaderboard-stats-design.md`. Branch `feature/cop-sight` (all of this ships as 1.7.0).

## Global Constraints
- **Leaderboard file:** `{format=2, runs}`. An older file is moved to `data/leaderboard-1.6.json`, or to `leaderboard-1.6-<time>.json` if that name is taken, and never deleted.
- **Practice rounds** are never recorded.
- **Sight stats** (hidden %, lost them) only come from runs that have `hiddenSeconds`. Otherwise they show "–".
- **Do not deploy** until the user says the server is empty.

## Review Focus
1. **Old leaderboard:** an old or format-1 file on the real server must be moved aside, not lost and not merged. Tested in Task 3.
2. **Name changes:** a player whose name changed shows their latest name in every tab. Tested in Task 1.
3. **Map filter:** a filter naming a map with no runs gives empty lists, not an error. Tested in Task 1.
4. **Run records:** a cop who left mid-round is still in `cops`, but only if they were in the round at the end. Tested in Task 2.
5. **Subscribers:** a board subscriber who disconnects gets no pushes. Tested in Task 3.

### Task 1: leaderboard stats (pure)
**Files:** `server/CopsAndRobbers/cnr/leaderboard.lua`, `tests/test_leaderboard.lua`.

**Produces:**
- `M.load(decoded) -> {format=2, runs}`
- `M.isCurrent(decoded) -> bool`
- `M.maps(board) -> {sorted map names}`
- `M.runners(board, map, limit) -> {{player, survivedSeconds, model, map}}`: wraps `best`.
- `M.cops(board, map, limit) -> {{name, catches, fastest}}`: sorted by catches descending, then fastest.
- `M.players(board, map) -> {{key, name, runs, best, average, escapes, catches, assists, hiddenPct|nil, lostThem|nil}}`: sorted by name.

**Names:** the latest name per key across all roles. Runner names come from `player`/`key`, cop names from `copNames`/`cops`, and catcher names from `catchers`/`catcherKeys`.

**Tests:**
- stats over 3 runs (2 maps)
- assists
- hidden % over only the runs that have it
- a renamed key shows the latest name
- an unknown map gives empty lists
- isCurrent

### Task 2: round records sight stats
**Files:** `cnr/round.lua`, `tests/test_round.lua`.

**What `round.lua` tracks:**
- `self.hiddenSeconds` accumulates per running tick while not in sight, but only when sight is on.
- `self.lostCount` counts lost transitions.
- `self.copSight[pid]` accumulates the running-tick seconds while `sight.sees(pid)`. This replaces sightedBy: assists need `copSight / chase ≥ assistMinSightPercent` (config default 20, 0–100, also in the panel).

**The record gets:**
- `hiddenSeconds` and `lostCount`, which are nil when sight is off.
- `copIds`: sorted human cop pids still in `players` at the finish.
- `copSight`: their sight seconds, in the same order.

**Tests:**
- hidden time with sight lost from 20 to 30 → the record has about that amount of hidden time
- lostCount = 1
- sightedBy = {2}
- copIds = {2, 3}
- with sight off, hiddenSeconds is nil

### Task 3: server wiring
**Files:** `main.lua`, `tests/test_main.lua`.

**Record:** `copIds` → `cops` (keys) + `copNames` + `copSightSeconds`. The pid lists are dropped before saving. `M.players(board, map, assistPercent)` takes `cfg.assistMinSightPercent`.

**Loading:** a file that isn't current is moved aside and the board starts empty, with a log line.

**Board events:**
- `cnr_board {action="open"|"close"|"filter", map}`. `boardSubs[pid] = filter`, where the default filter is the current map; `"all"` means all maps.
- `cnr_boardState {map, maps, filter, runners, cops, players}` is sent on open and on filter change, and to every subscriber after a recorded run.
- Subscribers are dropped on disconnect.

**Tests:**
- An old file (no format) is moved to `leaderboard-1.6.json` and the board starts empty.
- open → state with an empty runners list.
- After a recorded round, the subscriber gets pushed state with that runner.
- A filter of "all" changes the reported filter.
- Disconnect stops pushes.
- The record has `cops` keys.

### Task 4: client bridge
**Files:** `copsAndRobbers.lua`, `tests/test_client.lua`.
- `M.board(msg)`.
- `cnr_boardState` → `CnRBoard`, with `runners[i].car = game.carName(model)`.
- Reset to `CnRBoard {}` on mode/leave.

**Test:** state forwarded with car names; reset on leave.

### Task 5: Vue app
**Files:** `client/ui/modules/apps/CopsAndRobbersLeaderboard/{app.json, app.vue, app.png}`.
- `app.json`:
  - directive `copsAndRobbersLeaderboard`, interactive "required"
  - css in em (left 1.25em, top 36em, width 27.5em, height 25em, mins)
- `app.vue`:
  - open with retry, like the panel
  - tabs and a map dropdown (This map / All maps / maps)
  - lists, a player detail on click
  - collapse toggle, rem units, "–" for nil stats

**Verify:** `node --check`, `json.tool`, `make package` lists the files.

### Task 6: docs and TODO
- FEATURES: a Leaderboard section and the stats definitions.
- README: a short section.
- TODO: remove the "Leaderboard UI app" and "Player stats" items.
- Test counts.

### Task 7: final review (opus) of the leaderboard work. Fix pass, then ask about deploy (server empty) and merge.
