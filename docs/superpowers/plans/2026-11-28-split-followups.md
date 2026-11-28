# Split step 1 follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the five follow-ups the final review of #71 deferred (#78–#82), as the fix batch #84.

**Architecture:** Task 1 widens what the golden traces record and adds the uncovered paths, then re-records the goldens once. Every later task leaves the goldens byte-identical. Tasks 2–4 make `arcade/` game-neutral and harden settings. Tasks 5–6 are tidy-ups.

**Tech Stack:** server Lua 5.3 (BeamMP), the repo's test runner (`make test`, `tests/run.lua`), golden traces (`tests/trace.lua`, `tests/test_traces.lua`, `tests/traces/*.txt`).

**Spec:** none; this is a fix batch. The ticket is #84, and each sub-issue's "Done when" is the requirement. The maintainer decided the batch and #81's behaviour on 2026-11-28 (decision comment on #84).

## Global Constraints

- No source comments. Server Lua runs on Lua 5.3; check each changed server file with `luac5.3 -p` if available, otherwise `luajit -bl`.
- Players see no change. Hosts see one: #81's copy of a broken `config.json` and its log line.
- After Task 1, every task passes `git diff --exit-code <Task 1 head> -- tests/traces`.
- Event names stay `cnr_*`; only the `/cnr` command prefix and the `config.json` literal leave `arcade/` (#79).
- `make test` must pass at the end of each task.

## Review Focus

- A re-record that silently changes an existing golden line: Task 1's re-record must only add lines.
- Chat commands: typing `/cnr ...` in chat must still produce "Chat commands are gone: ...", and other chat must not.
- A broken `config.json` must never be deleted or replaced by the copy step itself, and a second load in the same second must not fail.
- A game declaration with a wrong-typed override or an invalid choice must fail at `combine`, with the key in the message.
- Renames in Task 5 (`schedule` → `nextRound`, roster `r`) must not change behaviour; the goldens prove it.

---

### Task 1: Trace coverage for the paths step 2 moves (#78)

**Files:**
- Modify: `tests/server_boot.lua` (the `MP` and `FS` fakes in `initialize`)
- Modify: `tests/trace.lua` (render non-send entries)
- Modify: `tests/test_traces.lua` (new scenarios)
- Re-record: `tests/traces/*.txt`; create the new scenarios' files

**Interfaces:**
- Produces: stream entries `{ kind = "op", t = <clock>, text = <line> }`. `render` already prints `entry.text` for non-send, non-log entries; ops print as `string.format("%.3f %s", t, detail)`.

- [ ] **Step 1: Write the failing test** in `tests/test_traces.lua`: `test("trace records vehicle removal, chat, timer operations and file writes", ...)`. Boot with `serverBoot.boot()`, then directly call `MP.RemoveVehicle(1, 3)`, `MP.SendChatMessage(2, "hi")`, `MP.CreateEventTimer("x", 100)`, `MP.CancelEventTimer("x")`, `FS.Remove(env.dir .. "a")`, `FS.Rename(env.dir .. "a.tmp", env.dir .. "a")` and `FS.CreateDirectory(env.dir .. "d")`. Assert that the stream's last seven entries are `kind == "op"` with these texts:
  - `0.000 remove 1-3`
  - `0.000 chat 2 hi`
  - `0.000 timer create x 100`
  - `0.000 timer cancel x`
  - `0.000 fs remove <env.dir>a`
  - `0.000 fs rename <env.dir>a.tmp <env.dir>a`
  - `0.000 fs mkdir <env.dir>d`

  `<env.dir>` is the literal directory in the stream; `traceRun` replaces it with `<dir>`.
- [ ] **Step 2: Run** `make test` → that test FAILS (no op entries).
- [ ] **Step 3: Implement.** In each fake, append the op entry first, then keep its current behaviour (`env.removed`, `env.chats`, `env.timerOps`, `env.timers`, the real file operations, `renameFails`) unchanged.
- [ ] **Step 4: Run** `make test`. The new test passes, and every golden scenario FAILS, because the goldens lack the op lines. That is expected.
- [ ] **Step 5: Add scenarios** to `tests/test_traces.lua`, each with assertions that pin the path:
  - `practice_setup_car_late`:
    - `env.panel(1, "test runner")`, `cnr_vehiclePicked`, and no `cnr_myVehicle` afterwards.
    - Tick past the AI-setup deadline.
    - Assert a `cnr_notice` to 1 whose `msg` contains "did not register in time", and a `cnr_roundEnd`.
  - `practice_setup_no_slots`:
    - Player 1 sits out (`cnr_sitOut` on), `test runner`, `cnr_vehiclePicked`, and no `cnr_aiVehicles`.
    - Tick past the deadline.
    - Assert a notice containing "too few free vehicle slots".
  - `disconnect_picking`: three sub-cases in one scenario, each starting a fresh round with `env.panel(2, "start rein")`, so player 2 is the issuer and player 1 the runner:
    - the runner disconnects before `cnr_vehiclePicked`;
    - the issuer disconnects while picking;
    - a cop disconnects while picking.

    Reconnect the player (`env.names` and `onPlayerJoin`) between cases. Assert what the current code does: the round's end reason, or that it carries on. Read it from the code; the golden pins it.
- [ ] **Step 6: Re-record** with `UPDATE_TRACES=1 make test`, then `make test`, which must pass.
- [ ] **Step 7: Gate.** `git diff -U0 HEAD -- tests/traces | grep '^-[^-]'` must print nothing: existing files only gain lines. Paste its (empty) output and `git diff --stat HEAD -- tests/traces` in the report.
- [ ] **Step 8: Commit** with the message "Traces: record removals, chat, timers and file writes; cover setup cancels and picking disconnects".

### Task 2: arcade/ no longer names the game (#79)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/commands.lua`, `arcade/panel.lua`, `arcade/settings.lua`, `server/CopsAndRobbers/main.lua` (chat detection)
- Test: `tests/test_commands.lua` or `tests/test_arcade_panel.lua` (whichever covers `arcade.commands`), `tests/test_arcade_settings.lua`

**Interfaces:**
- Produces: `commands.parseText(text) -> {name, args, rest} | nil`, which parses a command with no prefix ("" → `{name = "help", args = {}, rest = ""}`). `commands.parse(msg, prefix) -> same | nil` requires `prefix` and compares case-insensitively. `panel:run` uses `parseText`. `main.lua` calls `commands.parse(msg, "/cnr")`.
- Produces: `settings.new(path, decl, log)` logs a corrupt file as `<basename of path> is not valid JSON, using defaults`.

- [ ] **Step 1: Failing tests:**
  - `parseText("start rein")` gives name `start`, rest `rein`.
  - `parse("/CNR stop", "/cnr")` gives name `stop`.
  - `parse("/cnr stop", "/other")` is nil.
  - `settings.new("<tmp>/game.json", decl, log):load()` on invalid JSON logs `game.json is not valid JSON, using defaults`.
- [ ] **Step 2: Run** `make test` → those tests FAIL.
- [ ] **Step 3: Implement.** `grep -n '/cnr\|config\.json' server/CopsAndRobbers/arcade/*.lua` must print nothing afterwards.
- [ ] **Step 4: Run** `make test` → PASS. Run the golden gate against Task 1's head.
- [ ] **Step 5: Commit** with the message "arcade: no /cnr prefix or config.json name inside the services".

### Task 3: Game declarations get the same checks as the global ones (#80)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/settings.lua` (`combine`)
- Test: `tests/test_arcade_settings.lua`

**Interfaces:**
- Produces: `combine(global, game)` marks every `minKey` and `maxKey` of the combined `TIMING_RANGES` as `WHOLE` and `POSITIVE`. It asserts, for each `game.OVERRIDES[key]`, that the type matches `global.DEFAULTS[key]`'s type and, if `global.CHOICES[key]` exists, that the value is one of its choices. The assertion messages contain the key.

- [ ] **Step 1: Failing tests:**
  - A game declaring `TIMING_RANGES = { fooMinSeconds = "fooMaxSeconds" }`, with defaults 2 and 4, gets `decl.WHOLE.fooMinSeconds == true` and `decl.POSITIVE.fooMaxSeconds == true`. `merge` with `{ fooMinSeconds = 1.5 }` warns and falls back to 2.
  - `OVERRIDES = { autoNextRound = "yes" }` fails with a message containing `autoNextRound`.
  - `OVERRIDES = { weather = "hail" }` fails with a message containing `weather`.
  - `OVERRIDES = { weather = "rain" }` passes.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `make test` → PASS; golden gate.
- [ ] **Step 5: Commit** with the message "Settings: range and override checks for a game's own declarations".

### Task 4: Keep a copy of a broken config.json (#81)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/settings.lua` (`s:load`), and `arcade/store.lua` only if a copy helper is needed
- Test: `tests/test_arcade_settings.lua`, `tests/test_main.lua:21`

**Interfaces:**
- Produces: when `store.decode(path)` reports a corrupt file, `s:load()` writes the file's exact bytes to `path .. ".corrupt-" .. os.date("%Y%m%d-%H%M%S")` with `store.write`. It then logs `<basename> is not valid JSON, using defaults; kept a copy as <basename of copy>`, and returns the defaults as now. If the copy fails, it logs `could not keep a copy of <basename>: <err>` and still loads defaults.

- [ ] **Step 1: Failing tests** in `test_arcade_settings.lua`. Stub `os.date` to return `20261128-101500`, and restore it afterwards.
  - A corrupt file leaves `<path>.corrupt-20261128-101500` with identical bytes.
  - The original file is still there, unchanged, until a save.
  - The log line matches exactly.
  - A second `load()` in the same second succeeds; the copy is overwritten with the same bytes.
  - A valid file makes no copy.
  - Update `test_main.lua:21` to the new log text.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `make test` → PASS; golden gate.
- [ ] **Step 5: Commit** with the message "Settings: keep a timestamped copy of a broken config.json".

### Task 5: Code tidy-ups (#82, part 1)

**Files:** `server/CopsAndRobbers/arcade/messages.lua`, `arcade/roster.lua`, `main.lua`; tests: `tests/test_arcade_messages.lua`, `tests/test_arcade_roster.lua`, `tests/test_arcade_auto_rounds.lua`

- [ ] **Step 1: Failing tests:**
  - `messages.new({})` errors at once with a message containing `prefix`.
  - `m.log("x")` prints `<prefix>x`, captured by replacing `print`.
  - `r:clear("nope")` errors with a message containing `nope`.
  - `r:perPlayer("a", "early")` then `r:perPlayer("a", "late")` errors with a message containing both groups. The same group twice returns the same table.
  - `autoRounds.register(...)` returns a function that cancels the schedule and starts the next round only when no round is active. Use a fake `ctx` with `isActive`, `startNext` and `a`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**, plus three mechanical changes in `main.lua`:
  - rename the `autoRounds.new()` instance `schedule` → `nextRound`;
  - rename the roster local `r` → `roster`;
  - remove the unused `warnings` local in `loadConfig`.
- [ ] **Step 4: Run** `make test` → PASS; golden gate.
- [ ] **Step 5: Commit** with the message "Tidy: early prefix check, clearer roster errors, autoRounds test, main.lua names".

### Task 6: Test and docs tidy-ups (#82, part 2)

**Files:** `tests/test_arcade_store.lua`, `tests/test_main.lua` (the `panelState` fault injection), `tests/trace.lua`, `tests/test_reload.lua`, `docs/DEPENDENCIES.md`

- [ ] **Step 1: Store test.** `test_arcade_store.lua` builds its own minimal `FS` and `Util` fakes instead of booting the server. The fake `FS.Rename` returns false when the target exists, so a store that skips `FS.Remove` fails the write test. Show the test failing with `FS.Remove(path)` temporarily removed from `store.write`, then restore it.
- [ ] **Step 2: Fault injection.** The test in `tests/test_main.lua` that makes the panel update fail must not depend on the parameter name `panelState` in `arcade/panel.lua`. Make it fail through state main.lua reads, for example a player list or config value that makes `panelState()` raise, or through a hook on `MP.GetPlayers` that raises once. Keep its assertions: one log line per distinct error, and recovery.
- [ ] **Step 3: Trace robustness.** A send whose data isn't JSON renders as `<t> <to> <ev> raw:<data>` instead of aborting the run. Test it with a direct `traceLine` call.
- [ ] **Step 4: Reload cleanup.** `tests/test_reload.lua` runs its cleanup even when an assertion fails. Wrap the body and re-raise.
- [ ] **Step 5: Docs.** In `docs/DEPENDENCIES.md`'s arcade section:
  - Restore that `cnr/*.lua` call no BeamMP API.
  - Say the generic server services moved from `main.lua` to `server/CopsAndRobbers/arcade/`.
  - Use a bold lead-in like the rest of the file instead of a `###` heading.
- [ ] **Step 6: Run** `make test` → PASS; golden gate.
- [ ] **Step 7: Commit** with the message "Tidy: standalone store test, name-independent fault test, raw trace payloads, reload cleanup, docs".

**Ruled out of #82:** these stay as they are.
- The `ctx.settings` adapter. Step 2 (#72) redesigns the game interface it belongs to, so it is noted on #72 instead.
- The trace's plain version replace. A literal replace of `CNR_VERSION` is correct today; changing it is speculative.
