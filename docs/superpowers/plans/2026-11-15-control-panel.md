# Control Panel App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A clickable "Cops and Robbers Panel" UI app, not placed automatically, that runs rounds and changes settings, with settings saved automatically.

**Architecture:** A pure server module `cnr/panel.lua` builds the panel state, checks which commands the panel may send, and turns typed setting values into one validated config update. `main.lua` wires up a `cnr_panel` event, keeps a list of subscribers and pushes `cnr_panelState` when the state's signature changes. The GE extension forwards both directions. A Vue 3 app renders two tabs and calls the GE extension through `api.engineLua`.

**Tech Stack:** Lua 5.3+ server (tests run on the stock `lua`), LuaJIT client, Vue 3 SFC compiled by BeamNG 0.40's mod runtime, `make test`.

**Spec:** `docs/superpowers/specs/2026-11-15-control-panel-design.md`

## Global Constraints
- The panel is a separate app. Placement code never adds it. No permission checks on the server.
- Events and names:
  - client → server: `cnr_panel` with JSON `{action="open"|"close"|"command"|"settings", ...}`.
  - server → client: `cnr_panelState` and `cnr_panelReply`.
  - GE → UI: `CnRPanel` and `CnRPanelReply`.
- Settings save automatically, 0.5 s after the last change. Excluded cars save on Enter or when the field loses focus. Reset to default takes two clicks, and the confirm state lasts 3 s.
- A settings save is all or nothing, done in one `config.json` write. Settings saves reply in the panel only, never in chat. Mirrored command replies appear in both the panel and chat.
- During an active round, settings are refused and the tab shows "Stop the round first".
- `autoNextRound` appears on the Round tab only.
- Version 1.5.0.
- Code style: no comments, following the files' existing density.
- Client: no new top-level `local`s in `copsAndRobbers.lua` (164 of 200 are used), and nothing added to `onUpdate` (56 of 60 upvalues are used).

## Review Focus
1. **A change made by another player** in chat (`/cnr auto on`, `/cnr set ...`) shows in an open panel within one tick. Test: Task 2, "chat change is pushed to panel subscribers".
2. **A subscriber who disconnects** gets no further `cnr_panelState`. Test: Task 2, "disconnect drops the panel subscriber".
3. **Number formatting:** a value sent as `8.0` from the UI is saved as `8`, and `1.5` stays `1.5`. Test: Task 1, "applyValues formats numbers without trailing .0".
4. **An empty excluded cars list** saves as an empty list without errors. Test: Task 2, "empty excluded list saves".
5. **Malformed or hostile panel payloads** don't crash the plugin and save nothing. This covers non-JSON, `values` that isn't a table, list entries that aren't strings, unknown keys and an over-long command. Tests: Task 1, "applyValues rejects bad input" and "allow rejects over-long and unknown text"; Task 2, "malformed panel data is ignored".

---

### Task 1: Pure panel module

**Files:**
- Create: `server/CopsAndRobbers/cnr/panel.lua`
- Test: `tests/test_panel.lua`

**Interfaces:**
- Consumes: `config.setValue(raw, key, text) -> updated|nil, err` (existing).
- Produces:
  - `panel.BINDABLE`, the set moved verbatim from `main.lua`.
  - `panel.allow(text) -> string|nil` returns the trimmed, lowercased text if it is in `BINDABLE`, matches `^start %S`, or is `auto on`/`auto off`. Anything else, or more than 64 characters, gives nil.
  - `panel.can(state, test) -> {start, reroll, go, ["end"], stop, test, settings}` (booleans):
    - start: `state == "idle" or test`
    - reroll and go: `state == "prep"`
    - end: `state == "running"`. The spec says "head start and chase", but `Round:endCalled` refuses during head start, so the button would only produce an error there.
    - stop: `state ~= "idle"`
    - test and settings: `state == "idle"`
  - `panel.snapshot(info) -> table`, where info is `{version, map, phase, runner, test, elapsed, players, cfg, defaults}` and `players` maps pid to name. It returns:
    - `{version, map, phase, runner, test=bool, elapsed, players, settings, defaults, auto, can}`
    - `players` is a sorted list of names.
    - `elapsed` is `math.floor(info.elapsed)` or nil.
    - `settings` and `defaults` are copies, with lists copied.
    - `auto = cfg.autoNextRound == true`
    - `can = panel.can(phase, test)`
  - `panel.signature(t) -> string` is a deterministic serialisation. Keys are sorted at every level, and tables with the same content give equal strings.
  - `panel.applyValues(raw, values) -> updated, keys | nil, err`
    - `values` must be a non-empty table with string keys. Otherwise it returns `nil, "Nothing to save"`.
    - Keys are processed in sorted order and chained through `config.setValue`.
    - Values become text first: a number goes through `string.format("%.10g", v)`, a boolean through `tostring`, a string stays as it is, and a table becomes the `ipairs` entries passed through `tostring` and joined with `", "`.
    - The first error is returned unchanged.
    - `keys` is the sorted list of saved keys.

- [ ] **Step 1: Write the failing tests** in `tests/test_panel.lua` (style: `tests/test_hud.lua`, globals `test`/`assertEq`):
  - "allow accepts bindable, start <name> and auto on/off":
    - `allow("  GO ") == "go"`
    - `allow("start Reinder") == "start reinder"`
    - `allow("auto off") == "auto off"`
    - `allow("test cop") == "test cop"`
  - "allow rejects over-long and unknown text":
    - `allow("set headStartSeconds 1") == nil`
    - `allow("start") == nil`
    - `allow("auto maybe") == nil`
    - `allow("start " .. string.rep("a", 70)) == nil`
    - `allow(nil) == nil`
  - "can follows the round state":
    - for `"idle"`: start, test and settings are true; go, reroll, end and stop are false
    - for `"prep"`: go, reroll and stop are true; start is false
    - for `"headstart"`: end is false
    - for `"running"`: end is true
    - `can("running", true).start == true`
  - "snapshot sorts players, floors elapsed and copies lists":
    - players `{[2]="bob",[1]="Ann"}` gives `{"Ann","bob"}`
    - `elapsed=12.9` gives `12`
    - changing `snap.settings.excludedModels[1]` leaves `cfg.excludedModels[1]` unchanged
    - `snap.auto == true` when `cfg.autoNextRound = true`
  - "signature is order independent and sees value changes":
    - two tables built with keys in different orders give equal signatures
    - changing a nested list item changes the signature
  - "applyValues saves several values at once":
    - `applyValues({}, {headStartSeconds=9, explodeOnCatch=true, excludedModels={"citybus","us_semi"}})` gives `updated.headStartSeconds == 9`, `updated.explodeOnCatch == true`, `updated.excludedModels[2] == "us_semi"`
    - `keys` is `{"excludedModels","explodeOnCatch","headStartSeconds"}`
  - "applyValues formats numbers without trailing .0": `tostring(applyValues({}, {headStartSeconds=8.0}).headStartSeconds) == "8"`, and `stillMaxSpeedKmh=1.5` gives `1.5`.
  - "applyValues rejects bad input":
    - `{headStartSeconds=9, catchHoldSeconds=0}` returns nil and an err containing "catchHoldSeconds"
    - `{nope=1}` returns nil and an err containing "Unknown setting"
    - `"x"`, `{}` and `nil` each return `nil, "Nothing to save"`
    - `{excludedModels={"a", true}}` does not raise and gives `excludedModels` `{"a","true"}`

- [ ] **Step 2: Run** `make test`. Expected: `test_panel.lua` fails with "module 'cnr/panel' not found". All other tests pass.

- [ ] **Step 3: Implement** `server/CopsAndRobbers/cnr/panel.lua` with the interfaces above. `require("cnr/config")` and `require("cnr/tables")` if it has a list copy helper. Otherwise write a local copy helper.

- [ ] **Step 4: Run** `make test`. Expected: all pass.

- [ ] **Step 5: Commit**: `git add server/CopsAndRobbers/cnr/panel.lua tests/test_panel.lua && git commit -m "feat: pure panel module for state, allowed commands and settings saves"`

### Task 2: Server wiring

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, which includes `reply` (≈l.80), `BINDABLE`/`cnrOnCommand` (≈l.613-626), `cnrTick` (≈l.837), `cnrOnPlayerDisconnect` and event registration (≈l.861-877).
- Test: `tests/test_main.lua`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces:
  - Client event `cnr_panelState` with the `panel.snapshot` table.
  - Client event `cnr_panelReply` with one of two shapes:
    - `{text}` for a mirrored command reply
    - `{ok=bool, text, keys}` for a settings save: text `"Saved"` with `keys` on success, the error or `"Stop the round first"` on failure
  - Server event `cnr_panel` handled by global `cnrOnPanel(pid, data)`.

Wiring decisions:
- **Locals:** `panelSubs` (pid → true), `panelMirror` (pid or nil) and `lastPanelSig`. Declare them before `reply` so `reply` can mirror: when `pid == panelMirror`, it also sends `cnr_panelReply {text=msg}`.
- **`panelState()`** fills `panel.snapshot` from:
  - `VERSION`, `mapName` and `current.state`
  - the runner: `current.runnerId and current:runnerName()`, otherwise nil
  - `current.test == true`
  - elapsed: `now() - current.releasedAt` while `current.state == "running"`
  - `MP.GetPlayers() or {}`, `cfg` and `config.DEFAULTS`
- **`pushPanel()`:** when `next(panelSubs)` is nil, return. Otherwise compute the signature. If it differs from `lastPanelSig`, send to every subscriber and store it.
  - It is called at the top of `cnrTick`, before the early return.
  - It is also called after a panel command and after a settings save.
- **Actions:** `data` is decoded with `pcall(Util.JsonDecode, data)`. Anything other than a table with a string `action` is ignored.
  - `open`: subscribe, then send the state to that pid directly. This doesn't touch `lastPanelSig`.
  - `close`: unsubscribe.
  - `command`: `panel.allow(text)`. If allowed, run it through the shared `runCommand(pid, text)` used by `cnrOnCommand` (parse `"/cnr " .. text`, then call the handler), with `panelMirror = pid` around the call. Clear `panelMirror` even if the handler errors (use `pcall`, then re-raise).
  - `settings`:
    - If `current:isActive()`, reply `{ok=false, text="Stop the round first"}`.
    - Otherwise `panel.applyValues(rawConfig, values)`.
    - On failure, reply `{ok=false, text=err}`.
    - On success: write `config.json` as `handlers.set` does, call `loadConfig()`, set `current = round.new(cfg)`, reply `{ok=true, text="Saved", keys=keys}`, then `pushPanel()`.
- **Clean-up:** `cnrOnCommand` uses `panel.BINDABLE`, and the local `BINDABLE` is removed. `cnrOnPlayerDisconnect` sets `panelSubs[pid] = nil`. Register `MP.RegisterEvent("cnr_panel", "cnrOnPanel")`.

- [ ] **Step 1: Write the failing tests** in `tests/test_main.lua`, using `boot()`, `env.call` and `env.lastSent`. Add a local helper `countSent(env, ev, pid)`.
  - "panel open sends state to the opener": after `env.call("cnr_panel", 1, '{"action":"open"}')`, `lastSent("cnr_panelState").pid == 1` and its data contains `"phase":"idle"` and `"map":"west_coast_usa"`.
  - "panel state is pushed on change, not every tick":
    - open as 1, then call `cnr_tick` twice: no new `cnr_panelState`
    - `env.startRound()` then `cnr_tick`: one more state, whose data contains `"phase":"prep"`
    - `cnr_tick` again: no new state
  - "chat change is pushed to panel subscribers": open as 1, chat `/cnr auto on` as pid 2, then `cnr_tick`. The latest state to 1 contains `"autoNextRound":true`.
  - "panel command runs handlers and mirrors replies":
    - `{"action":"command","text":"go"}` as pid 2 with no round: `lastSent("cnr_panelReply").pid == 2`, its data contains `No round set up`, and `env.chatHas("No round set up")` is true
    - `{"action":"command","text":"start Reinder"}` as pid 2: `lastSent("cnr_pickVehicle").pid == 2`
  - "panel command outside the allowlist does nothing": `{"action":"command","text":"set headStartSeconds 1"}`, then `/cnr config` in chat still shows `headStartSeconds = 7`.
  - "panel settings save several values in one write":
    - values `{"headStartSeconds":9,"explodeOnCatch":true,"excludedModels":["citybus"]}`
    - `/cnr config` shows `headStartSeconds = 9`, `explodeOnCatch = true` and `excludedModels = citybus`
    - the reply data contains `"ok":true`
    - `env.chatHas("Saved")` is false
  - "empty excluded list saves": values `{"excludedModels":[]}` reply `"ok":true`, and `/cnr config` shows `excludedModels = ` (empty).
  - "panel settings with one invalid value save nothing": values `{"headStartSeconds":9,"catchHoldSeconds":0}` reply `"ok":false` with `catchHoldSeconds`, and `/cnr config` still shows `headStartSeconds = 7`.
  - "panel settings are refused during a round": `env.startRound()`, then a settings save replies with data containing `Stop the round first`, and nothing changes.
  - "disconnect drops the panel subscriber": open as 1, `onPlayerDisconnect` for 1, `env.startRound()` as 2 with a tick. No `cnr_panelState` to 1 after the disconnect.
  - "malformed panel data is ignored":
    - `env.call("cnr_panel", 1, "not json")` and `env.call("cnr_panel", 1, '{"nope":1}')` raise nothing
    - `{"action":"settings","values":"x"}` replies `Nothing to save`

  Note for the "disconnect" test: check how the existing `onPlayerDisconnect` tests set names before reusing pid 2 as the starter.

- [ ] **Step 2: Run** `make test`. Expected: the new main tests fail with an error about `cnr_panel` not being registered (`attempt to call a nil value`). Everything else passes.

- [ ] **Step 3: Implement** the wiring decisions above in `main.lua`.

- [ ] **Step 4: Run** `make test`. Expected: all pass. That includes the existing `cnr_command` tests (≈l.745-757 of `test_main.lua`), which prove the move of `BINDABLE`.

- [ ] **Step 5: Commit**: `git commit -am "feat: server panel event, state push and automatic settings saves"`

### Task 3: Client bridge

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`, around `M.command` (≈l.1161), `onExtensionLoaded` (≈l.1166), `onExtensionUnloaded`, `onClientEndMission` and `onBeamMPServerLeave` (≈l.1191-1203).

**Interfaces:**
- Consumes: `cnr_panelState` and `cnr_panelReply` (Task 2).
- Produces:
  - `copsAndRobbers.panel(msg: table)`: when `TriggerServerEvent` exists and `type(msg) == "table"`, it calls `TriggerServerEvent("cnr_panel", jsonEncode(msg))`.
  - UI events:
    - `CnRPanel` with the decoded state table, or `{}` when disconnected
    - `CnRPanelReply` with the decoded reply table

- [ ] **Step 1: Implement:**
  - Add `function M.panel(msg)` next to `M.command`.
  - In `onExtensionLoaded`, add `AddEventHandler("cnr_panelState", function(data) guihooks.trigger("CnRPanel", jsonDecode(data) or {}) end)`, plus the same for `cnr_panelReply` → `CnRPanelReply`. Both are inline functions, so there are no new top-level locals.
  - Add `guihooks.trigger("CnRPanel", {})` to `onExtensionUnloaded`, `onClientEndMission` and `onBeamMPServerLeave`.

- [ ] **Step 2: Verify the client still compiles under LuaJIT limits:**
  - Run `luajit -bl client/lua/ge/extensions/copsAndRobbers.lua > /dev/null && echo OK`. Expected: `OK`.
  - Run `make test`. Expected: all pass.

- [ ] **Step 3: Commit**: `git commit -am "feat: client forwards panel requests, state and replies"`

### Task 4: Vue panel app

**Files:**
- Create: `client/ui/modules/apps/CopsAndRobbersPanel/app.json`, `app.vue` and `app.png`.
- `app.png` is a copy of `CopsAndRobbersHud/app.png`. A new preview is left to a later polish pass.

**Interfaces:**
- Consumes:
  - `CnRPanel` and `CnRPanelReply` (Task 3)
  - the state shape from Task 1
  - `copsAndRobbers.panel(table)`

**`app.json`:**
- `"domElement": "<cops-and-robbers-panel></cops-and-robbers-panel>"`
- `"directive": "copsAndRobbersPanel"`
- `"name": "Cops and Robbers Panel"`
- `"types": ["ui.apps.categories.utility"]`
- `"vue": true`, `"interactive": "required"`, `"isAuxiliary": false`, `"category": "Gameplay"`
- `css` is `{left: "20px", top: "120px", width: "440px", height: "520px", "min-width": "360px", "min-height": "300px"}`
- `author`, `version` and `description` follow the style of the HUD's `app.json`.

**`app.vue` decisions:**
- **Imports:**
  - `useBridge` from `@/bridge` for `api`
  - `useEvents` from `@/services/events`
  - `BngButton`, `BngSwitch` and `BngDropdown` from `@/common/components/base`
- **Calling the GE extension:** `send(msg)` runs `api.engineLua(\`if copsAndRobbers then copsAndRobbers.panel(${api.serializeToLua(msg)}) end\`)`.
- **Lifecycle:**
  - On mount: `send({action:"open"})`, then retry every 2000 ms while `state.phase` is unset.
  - `CnRPanel` with no `phase` resets the state to "not connected", and the retries resume.
  - On unmount: `send({action:"close"})` and clear every timer.
- **Not connected view:** the text "Not on a Cops and Robbers server".
- **Tab header:** two buttons, ROUND and SETTINGS, with an active class (no `BngTabs`). It is followed by a version label `v{{state.version}}`.
- **Round tab:**
  - Status line: `{phaseLabel} · {state.map} · {players.length} players`. The phase labels are:
    - idle: `No round`
    - picking: `Picking cars`
    - prep: `Prep: waiting for GO`
    - countdown: `Countdown`
    - headstart: `Runner head start`
    - running: `Chase m:ss`, from `elapsed`
  - Runner line: `Runner: {runner}`, plus ` (practice)` when `test` is true. Only shown when `runner` is set.
  - Runner dropdown: items `[{value:"next",label:"Next (fewest runs)"},{value:"again",label:"Same as last"},{value:"random",label:"Random"}, ...players.map(n => ({value:n,label:n}))]`. The default is `"next"`, and it falls back to `"next"` when the chosen player leaves.
  - Buttons:

    | Label | Sends | Disabled when |
    |---|---|---|
    | Start round | `start ${choice}` | `!can.start` |
    | New car | `reroll` | `!can.reroll` |
    | GO | `go` | `!can.go` |
    | End chase | `end` | `!can.end` |
    | Cancel | `stop` | `!can.stop` |
    | Practice: as runner | `test runner` | `!can.test` |
    | Practice: as cop | `test cop` | `!can.test` |

    Each sends `{action:"command", text}` and clears the reply line first.
  - Automatic rounds: `BngSwitch` bound to `state.auto`. On change it sends `auto on` or `auto off`.
- **Settings tab:**
  - Groups, in order. Each row is key, label, unit, step and min. Booleans are switches and the list is a text field:
    - **Round:** `headStartSeconds` Head start s 1 0; `runnerCountdownSeconds` Runner countdown s 1 0; `roundTimeLimitSeconds` Time limit (0 = off) s 60 0; `autoNextDelaySeconds` Next round delay s 5 0
    - **Catching:** `catchHoldSeconds` Hold time s 1 1; `catchRadiusMeters` Radius m 1 1; `catchMaxSpeedKmh` Max speed km/h 1 1; `explodeOnCatch` Explode on catch (switch)
    - **Resets:** `resetWaitSeconds` Wait time s 1 0; `stillMaxSpeedKmh` Still speed km/h 0.5 0.5; `copResetMinDistanceMeters` Cop min distance m 100 0; `gasStationRadiusMeters` Gas station radius m 5 0
    - **Crashes:** `crashSpeedLossKmh` Speed loss km/h 5 5; `crashPenaltySeconds` Penalty s 1 0
    - **Cops:** `copSpawnMinMeters` Spawn min m 10 0; `copSpawnMaxMeters` Spawn max m 10 0; `lastSeenIntervalSeconds` Last seen every s 5 0
    - **Cars:** `includeModVehicles` Include mod cars (switch); `excludedModels` Excluded cars (text)
    - **Other:** any key in `state.settings` that is not listed above and not `autoNextRound`. Numbers get step 1 and min 0, booleans a switch, and lists a text field.
  - **Displayed value:** `pending[key] ?? state.settings[key]`. A list that isn't an array displays as empty.
  - **Stepper:** `[ − ] value unit [ + ]`. The new value is `Math.max(min, Math.round((v ± step) / step) * step)`, rounded to 4 decimals.
  - **Saving:** every change sets `pending[key]` and restarts one 500 ms timer. When it fires, it sends `{action:"settings", values: {...pending}}` and keeps those keys as `inFlight`.
  - **Excluded cars:** a plain `<input>`. On Enter or blur, the text is split on commas and whitespace into an array, then sent at once.
  - **Replies:** `CnRPanelReply` with `ok !== undefined` clears `pending` for the in-flight keys. On ok:
    - one key: `Saved: {label} {value} {unit}`
    - more than one: `Saved {n} settings`
    - reset: `Reset to defaults`

    On failure, the reply line shows `text`. A reply without `ok` shows `text` (mirrored command replies).
  - **Reset to default:** the first click changes the label to `Click again to reset` for 3000 ms. The second click sends `values` = every listed default except `autoNextRound`.
  - **During a round** (`!can.settings`): every control is disabled and the tab shows `Stop the round first`.
- **Layout and theme:** a dark translucent panel matching the HUD (`rgba(0,0,0,0.6)`, white text). The content scrolls inside the app box.

- [ ] **Step 1: Write** `app.json`, then `app.vue` from the decisions above.

- [ ] **Step 2: Verify:**
  - `python3 -m json.tool client/ui/modules/apps/CopsAndRobbersPanel/app.json > /dev/null && echo OK`. Expected: `OK`.
  - Extract the `<script setup>` block to `$SCRATCH/panel.mjs` (sed between the script tags) and run `node --check $SCRATCH/panel.mjs`. Expected: no output, exit 0.
  - `make package && unzip -l dist/Client/CopsAndRobbers.zip | grep CopsAndRobbersPanel`. Expected: `app.json`, `app.vue` and `app.png` are listed.

- [ ] **Step 3: Commit**: `git add client/ui/modules/apps/CopsAndRobbersPanel && git commit -m "feat: Cops and Robbers Panel app with round controls and automatic settings"`

### Task 5: Version 1.5.0 and docs

**Files:**
- Modify:
  - `server/CopsAndRobbers/main.lua` (`VERSION`)
  - `client/lua/ge/extensions/copsAndRobbers.lua` (`CLIENT_VERSION`)
  - `client/mod_info/CopsAndRobbers/info.json` (version)
  - `README.md`
  - `docs/FEATURES.md`
- Test: version tests in `tests/test_main.lua`, if any assert `1.4.0` (grep first).

- [ ] **Step 1:** Run `grep -rn '1\.4\.0' server client tests README.md docs/FEATURES.md`, then change the three version strings and any test expectation to `1.5.0`.
- [ ] **Step 2:** Add a "Control panel" section to `README.md` and `docs/FEATURES.md`. It covers:
  - adding it via Esc → UI Apps → "Cops and Robbers Panel"
  - the Round tab buttons
  - Settings saving automatically, and being locked during a round
- [ ] **Step 3: Run** `make test`. Expected: all pass, and the plugin load log says `Cops and Robbers 1.5.0 loaded`.
- [ ] **Step 4: Commit**: `git commit -am "chore: 1.5.0 - control panel app"`
