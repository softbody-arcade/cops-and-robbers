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
- A broken `config.json` must never be deleted or changed by the copy step, a failed copy must never be logged as kept, and two different broken versions must both be kept.
- A game declaration with a wrong-typed override or an invalid choice must fail at `combine`, with the key in the message.
- Renames in Task 5 (`schedule` → `nextRound`, roster `r` → `roster`) must not change behaviour; the goldens prove it.

---

### Task 1: Trace coverage for the paths step 2 moves (#78)

**Files:**
- Modify: `tests/server_boot.lua` (the `MP` and `FS` fakes in `initialize`)
- Modify: `tests/test_traces.lua` (a fake-level test and new scenarios)
- Re-record: `tests/traces/*.txt`; create the new scenarios' files

**Interfaces:**
- Produces: stream entries `{ kind = "op", t = <clock>, text = <line> }`, where `text` already starts with the timestamp: `string.format("%.3f %s", env.clock, detail)`. `render` in `tests/trace.lua` prints a non-send, non-log entry's `text` verbatim, so `trace.lua` needs no change.
- Op details:
  - `MP.RemoveVehicle(pid, vid)` → `remove <pid>-<vid>`
  - `MP.SendChatMessage(pid, msg)` → `chat <pid> <msg>`
  - `MP.CreateEventTimer(ev, ms)` → `timer create <ev> <ms>`
  - `MP.CancelEventTimer(ev)` → `timer cancel <ev>`
  - `FS.CreateDirectory(p)` → `fs mkdir <p>`
  - `FS.Remove(p)` → `fs remove <p>`
  - `FS.Rename(a, b)` → `fs write <b> <content>`. The content is the source file's bytes, read before the rename, and canonicalized with `serverBoot.encode(decodeJson(text), true)` when it decodes as JSON, otherwise raw. Then the rename happens as now, including `renameFails`. `store.write` always writes a temp file and renames it, so this records every saved file's destination and content.

- [ ] **Step 1: Write the failing test** in `tests/test_traces.lua`: `test("trace records vehicle removal, chat, timer operations and file writes", ...)`.
  - Boot with `serverBoot.boot()` and write the file `env.dir .. "a.tmp"` containing `{"b":1,"a":2}`.
  - Call `MP.RemoveVehicle(1, 3)`, `MP.SendChatMessage(2, "hi")`, `MP.CreateEventTimer("x", 100)`, `MP.CancelEventTimer("x")`, `FS.CreateDirectory(env.dir .. "d")`, `FS.Remove(env.dir .. "a")` and `FS.Rename(env.dir .. "a.tmp", env.dir .. "a")`.
  - Assert that the last seven stream entries are `kind == "op"` with these texts:
    - `0.000 remove 1-3`
    - `0.000 chat 2 hi`
    - `0.000 timer create x 100`
    - `0.000 timer cancel x`
    - `0.000 fs mkdir <env.dir>d`
    - `0.000 fs remove <env.dir>a`
    - `0.000 fs write <env.dir>a {"a":2,"b":1}`

    Here `<env.dir>` stands for the literal directory string.
  - Assert that `env.dir .. "a"` now exists, and clean up.
- [ ] **Step 2: Run** `make test` → that test FAILS (no op entries).
- [ ] **Step 3: Implement.** In each fake, append the op entry first, then keep its current behaviour (`env.removed`, `env.chats`, `env.timerOps`, `env.timers`, the real file operations, `renameFails`) unchanged.
- [ ] **Step 4: Run** `make test`. The new test passes, and the golden scenarios FAIL because the goldens lack the op lines. That is expected.
- [ ] **Step 5: Add scenarios** to `tests/test_traces.lua`. In the two setup scenarios, take the send index after the pick (`local picked = #env.sent`); in the disconnect cases, take it right before each `onPlayerDisconnect`. Look for later events only from there, so boot's own `cnr_roundEnd` can't satisfy an assertion.
  - `practice_setup_car_late`, booted with `{ vehicles = { [1] = { [0] = "x" } } }`:
    - `env.panel(1, "test runner")`, then `cnr_vehiclePicked` from 1 with the `pick` payload, and no `cnr_myVehicle`.
    - Tick until a `cnr_roundEnd` after `picked` and assert `reason == "cancelled"`. The server first sends the notice "Round cancelled", then `cnr_roundEnd`, then the notice that explains the timeout.
    - Assert the next `cnr_notice` to 1 after that `cnr_roundEnd` contains "did not register in time".
  - `practice_setup_no_slots`, booted with `{ maxCars = 3 }` (player 1 keeps the default occupied vehicle):
    - `cnr_sitOut` on for 1, `env.panel(1, "test runner")`, then `cnr_vehiclePicked`, and no `cnr_aiVehicles`.
    - Tick until a `cnr_roundEnd` after `picked` (about 15 s of ticks) and assert `reason == "cancelled"`.
    - Assert the next `cnr_notice` to 1 after that `cnr_roundEnd` contains "too few free vehicle slots".
  - `disconnect_picking`. Set `env.names = { "Reinder", "Bob", "Kim" }` and call `onPlayerJoin` for 3 first. Then three cases, each starting a fresh round with `env.panel(2, "start rein")`, so 2 is the issuer, 1 the runner and 3 a cop. Before each `onPlayerDisconnect(pid)`, remove that pid from `env.names`, and restore it with `onPlayerJoin` before the next case.
    - **Runner leaves:** 1 disconnects before any pick. Assert `cnr_roundEnd` with `reason == "cancelled"`, and a notice "Runner left, round cancelled".
    - **Issuer leaves:** 2 disconnects while picking. Assert `cnr_roundEnd` with `reason == "cancelled"`, and a notice "Round cancelled".
    - **Cop leaves:** 3 disconnects while picking. Assert no `cnr_roundEnd` after it. Then 2 sends `cnr_vehiclePicked`, and `cnr_roundSetup` goes out to 1 and 2.
- [ ] **Step 6: Re-record** with `UPDATE_TRACES=1 make test`, then `make test`, which must pass.
- [ ] **Step 7: Gate.**
  - `git diff -U0 HEAD -- tests/traces | grep '^-[^-]'` must print nothing: existing files only gain lines.
  - `git status --short tests/traces` must list exactly the three new files as untracked before the commit.
  - Paste both outputs and `git diff --stat -- tests/traces` in the report.
- [ ] **Step 8: Commit** all changed and new files (the three new goldens included) with the message "Traces: record removals, chat, timers and file writes; cover setup cancels and picking disconnects".

### Task 2: arcade/ no longer names the game (#79)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/commands.lua`, `arcade/panel.lua`, `arcade/settings.lua`, `server/CopsAndRobbers/cnr/commands.lua`
- Test: a new `tests/test_arcade_commands.lua` (listed in `tests/run.lua` if the runner needs it), `tests/test_arcade_settings.lua`; `tests/test_commands.lua` must keep passing unchanged

**Interfaces:**
- Produces: `arcade.commands.parseText(text) -> {name, args, rest} | nil` parses a command with no prefix. An empty or blank text gives `{ name = "help", args = {}, rest = "" }`, as `/cnr` alone does now.
- Produces: `arcade.commands.parse(msg, prefix) -> same | nil` requires `prefix`, compares it case-insensitively, and uses `parseText` for the rest.
- `arcade/panel.lua`'s `p:run(pid, text)` uses `parseText(text)`.
- `cnr/commands.lua` keeps its one-argument `M.parse(msg)` as a wrapper: `return arcadeCommands.parse(msg, "/cnr")`. `main.lua`'s chat detection keeps calling `cnr.commands.parse(msg)` unchanged.
- Produces: `settings.new(path, decl, log)` logs a corrupt file starting with `<basename of path> is not valid JSON, using defaults`, where the basename is `path:match("[^/\\]+$")`.

- [ ] **Step 1: Failing tests:**
  - `arcade.commands.parseText("start rein")` gives name `start` and rest `rein`.
  - `parseText("")` gives name `help`.
  - `arcade.commands.parse("/CNR stop", "/cnr")` gives name `stop`.
  - `arcade.commands.parse("/cnr stop", "/other")` is nil.
  - `settings.new(<tmp dir> .. "game.json", decl, log):load()` on invalid JSON logs a line that starts with `game.json is not valid JSON, using defaults`.
- [ ] **Step 2: Run** `make test` → those tests FAIL.
- [ ] **Step 3: Implement.** Afterwards `grep -n '/cnr\|config\.json' server/CopsAndRobbers/arcade/*.lua` must print nothing.
- [ ] **Step 4: Run** `make test` → PASS, `tests/test_commands.lua` included. Run the golden gate against Task 1's head.
- [ ] **Step 5: Commit** with the message "arcade: no /cnr prefix or config.json name inside the services".

### Task 3: Game declarations get the same checks as the global ones (#80)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/settings.lua` (`combine`)
- Test: `tests/test_arcade_settings.lua`

**Interfaces:**
- Produces: `combine(global, game)` marks every `minKey` and `maxKey` of the combined `TIMING_RANGES` as `WHOLE` and `POSITIVE`.
- For each `game.OVERRIDES[key]`, it asserts that the type matches `global.DEFAULTS[key]`'s type and, when `global.CHOICES[key]` exists, that the value is one of its choices. Both assertion messages contain the key.

- [ ] **Step 1: Failing tests:**
  - A game declaring `TIMING_RANGES = { fooMinSeconds = "fooMaxSeconds" }`, with defaults 2 and 4, gets `decl.WHOLE.fooMinSeconds == true` and `decl.POSITIVE.fooMaxSeconds == true`. `merge` with `{ fooMinSeconds = 1.5 }` warns and falls back to 2.
  - `OVERRIDES = { autoNextRound = "yes" }` fails with a message containing `autoNextRound`.
  - `OVERRIDES = { weather = "hail" }` fails with a message containing `weather`.
  - `OVERRIDES = { weather = "rain" }` passes.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `make test` → PASS; golden gate.
- [ ] **Step 5: Commit** with the message "Settings: range and override checks for a game's own declarations".

### Task 4: Keep a copy of a broken config.json (#81)

**Files:**
- Modify: `server/CopsAndRobbers/arcade/store.lua` (new `copy`), `arcade/settings.lua` (`s:load`)
- Test: `tests/test_arcade_store.lua`, `tests/test_arcade_settings.lua`, `tests/test_main.lua:21`

**Interfaces:**
- Produces: `store.copy(src, dst) -> true | nil, err`. It reads `src` in binary (`"rb"`) and writes `dst` with `io.open(dst, "wb")`, checking the results of `open`, `write` and `close`. It returns `nil, err` on any failure and never touches `src`.
- Produces: `s:load()` handles a broken file like this. Broken means `store.decode` reports it corrupt, or the file exists but is empty: `store.decode` returns `nil, false` for both an empty and a missing file, so check `store.read(path) == ""`. A missing file stays as now, with no copy and no message.
  1. Read its bytes.
  2. Choose the copy name: start with `<path>.corrupt-<os.date("%Y%m%d-%H%M%S")>`. If that file exists with the same bytes, reuse it and write nothing. If it exists with different bytes, try `-2`, `-3`, and so on, until a free name or one with the same bytes.
  3. Call `store.copy`.
  4. On success, log `<basename> is not valid JSON, using defaults; kept a copy as <basename of copy>`. On failure, log `<basename> is not valid JSON, using defaults; could not keep a copy: <err>`.
  5. In both cases, return the defaults as now.

- [ ] **Step 1: Failing tests.** Stub `os.date` to return `20261128-101500` in these tests, and restore it afterwards.
  - `store.copy` copies bytes exactly, including a `\0` and `\r\n`. It returns nil and an error when `dst` is a directory.
  - A corrupt file leaves `<path>.corrupt-20261128-101500` with identical bytes. The original is unchanged, and the log line matches exactly.
  - A second load of the same bytes in the same second writes nothing new and logs the same copy name.
  - A second load after the file's bytes changed (still invalid) keeps both: the first copy is unchanged, and the new one is `<path>.corrupt-20261128-101500-2`.
  - Make the copy fail by stubbing `store.copy` to return `nil, "denied"` for a free destination, and restore it afterwards. Assert the stub was called, the log ends `could not keep a copy: denied`, the defaults load, and the original bytes are unchanged.
  - An existing zero-byte `config.json` gets a zero-byte copy and the same log line. A missing `config.json` makes no copy and no "not valid JSON" line.
  - A valid file makes no copy.
  - Strengthen `test_main.lua:21` so it checks the logged copy name, and that the copy file exists in `env.dir`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `make test` → PASS; golden gate.
- [ ] **Step 5: Commit** with the message "Settings: keep a timestamped copy of a broken config.json".

### Task 5: Code tidy-ups (#82, part 1)

**Files:** `server/CopsAndRobbers/arcade/messages.lua`, `arcade/roster.lua`, `main.lua`; tests: `tests/test_arcade_messages.lua`, `tests/test_arcade_roster.lua`, `tests/test_arcade_auto_rounds.lua`

- [ ] **Step 1: Failing tests:**
  - `messages.new({})` errors at once with a message containing `prefix`.
  - `m.log("x")` prints `<prefix>x`, captured by replacing `print`.
  - `r:clear("nope")` errors with a message containing `nope`.
  - `r:perPlayer("a", "early")` then `r:perPlayer("a", "late")` errors with a message containing both groups. The same group twice returns the same table.
  - `autoRounds.register(p, ctx)` returns a function that cancels the schedule and starts the next round only when no round is active. Use a fake `p` with `command` and a fake `ctx` with `isActive`, `startNext` and `a`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**, plus three mechanical changes in `main.lua`:
  - Rename the `autoRounds.new()` instance `schedule` → `nextRound`.
  - Rename the roster local `r` → `roster`.
  - In `readSettings()`, drop the unused `warnings` local, keeping `cfg` and `rawConfig` bound to the first and third results of `settings:load()`.
- [ ] **Step 4: Run** `make test` → PASS; golden gate.
- [ ] **Step 5: Commit** with the message "Tidy: early prefix check, clearer roster errors, autoRounds test, main.lua names".

### Task 6: Test and docs tidy-ups (#82, part 2)

**Files:** `tests/test_arcade_store.lua`, `tests/test_main.lua` (the test "a lobby change still goes out when the panel push errors"), `tests/trace.lua`, `tests/test_traces.lua`, `tests/test_reload.lua`, `docs/DEPENDENCIES.md`

- [ ] **Step 1: Store test.**
  - `test_arcade_store.lua` builds its own minimal `FS` and `Util` fakes instead of booting the server.
  - The fake `FS.Rename` returns false when the target exists, so a store that skips `FS.Remove` fails the write test.
  - Show the test failing with `FS.Remove(path)` temporarily removed from `store.write`, then restore it.
  - Keep Task 4's `store.copy` tests.
- [ ] **Step 2: Fault injection.** In "a lobby change still goes out when the panel push errors", replace the caller-name check with a one-shot failure: the first `MP.GetPlayers` call during that tick raises, and later calls return the real players. The panel push is the first caller in `cnrTick`. Assert that exactly one call failed, and that the same tick publishes `cnr_lobby` with `"online":1`.
- [ ] **Step 3: Raw payloads.**
  - In `tests/trace.lua`, a send whose data isn't JSON renders as `<t> <to> <ev> raw:<data>` instead of aborting the run.
  - Test it in `tests/test_traces.lua` with a `traceRun` scenario: a probe handler calls `MP.TriggerClientEvent(1, "cnr_probe", "not json")`. Assert the output contains `0.000 1 cnr_probe raw:not json`.
- [ ] **Step 4: Version substitution.**
  - `traceRun` replaces `CNR_VERSION` only where it stands as its own token: not preceded or followed by `[%w.]`.
  - Test it in `tests/test_traces.lua`: a probe sends `encode({ v = CNR_VERSION, name = "x" .. CNR_VERSION })`. The trace shows `"v":"<version>"` and keeps `"name":"x<CNR_VERSION>"` literally.
  - The goldens must stay unchanged.
- [ ] **Step 5: Reload cleanup.** `tests/test_reload.lua` runs its cleanup even when an assertion fails. Wrap the body and re-raise.
- [ ] **Step 6: Docs.** In `docs/DEPENDENCIES.md`'s arcade section:
  - Restore that `cnr/*.lua` call no BeamMP API.
  - Say the generic server services moved from `main.lua` to `server/CopsAndRobbers/arcade/`.
  - Use a bold lead-in like the rest of the file instead of a `###` heading.
- [ ] **Step 7: Run** `make test` → PASS; golden gate.
- [ ] **Step 8: Commit** with the message "Tidy: standalone store test, name-independent fault test, raw payloads and token-safe version in traces, reload cleanup, docs".

**#82 item handed to #72:** the ad-hoc `ctx.settings` `{get, set}` adapter. Step 2 (#72) redesigns the game interface it belongs to. The controller records the handoff on #72 and #82 (the maintainer agreed on 2026-11-28; decision on #82).

### Batch completion (controller)

- [ ] Each task gets a task review from the counterpart family before the next task's review closes (per the decision on #84). Fixes go back to the implementer and are re-reviewed.
- [ ] On the final head: `make test`, `make vuecheck` and `make package` pass locally, and all five CI jobs (`test`, `luajit`, `vuecheck`, `privacy`, `package`) are green.
- [ ] A whole-branch review on the final head is clean, and it is posted on the PR. Then #84 moves to Review and the PR is marked ready; the merge waits for the maintainer's go.
