# UI/UX Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the HUD, host panel and leaderboard one native BeamNG look, make the full-screen HUD the front door (lobby card, colour, How to play), and move every chat line, pop-up and chat command into the apps.

**Architecture:** The server stops writing chat and sends structured events (`cnr_notice`, `cnr_rules`, `cnr_lobby`, `cnr_myColor`, richer panel and board state, a per-run timeline). The client Lua turns those into one HUD payload (`hud.lua`, pure and tested) and a new `apps.lua` keeps the full-screen HUD in the layout and opens/closes the panel and leaderboard. The three Vue apps are rewritten on the game's own components and tokens, sharing a small kit in `client/ui/modules/copsAndRobbers/`.

**Tech Stack:** BeamMP server Lua 5.3 (`server/CopsAndRobbers`), BeamNG GE Lua (`client/lua/ge/extensions`), Vue 3 SFC apps compiled by BeamNG 0.40.5's mod loader, Lua tests (`make test`), a new Node check for the Vue files (`make vuecheck`).

**Spec:** `docs/superpowers/specs/2026-11-15-ui-ux-rework-design.md` (read it before any task; the mockups it names are in `.superpowers/brainstorm/470328-1794764964/content/`).

## Global Constraints

- Work on branch `ui-ux-rework`. `make test` passes after every task; `make vuecheck` passes after every task that touches a `.vue`/`.js` under `client/ui`.
- No gameplay or rule changes: catching, resets, penalties, sight, placement, evolving rules and when GO is allowed stay exactly as today.
- After Task 3 nothing in `server/` calls `MP.SendChatMessage`; after Task 9 nothing in `client/lua` calls `ui_message` (check: `grep -rn "SendChatMessage" server/` and `grep -rn "ui_message" client/lua` print nothing).
- Colour meanings, only via these tokens: runner `--bng-add-red-500` (fills) / `--bng-add-red-400` (text); cop `--bng-add-blue-500` / `--bng-add-blue-400`; attention/rule broken `--bng-ter-yellow-200`; good/go/saved `--bng-add-green-400`; clickable accent `--bng-orange-b400`, main button `--bng-orange-500`, your own row `--bng-orange-300`; text `--bng-off-white`, muted `--bng-cool-gray-300`. Nothing else uses red or blue.
- Fonts: `"Overpass", var(--fnt-defs)` display, `var(--fnt-defs)` body, `var(--fnt-mono)` + `font-variant-numeric: tabular-nums` for numbers. Sizes and spacing in `rem` on a 0.25 rem grid, never `px`.
- Surfaces: cards `rgba(var(--bng-off-black-rgb), .6)` + `--bng-corners-2`; rows `rgba(var(--bng-off-black-rgb), .5)` + `--bng-corners-1`; HUD text shadow `0 0 .25rem rgba(var(--bng-off-black-rgb), .6)`.
- Components from `@/common/components/base` (`BngButton`+`ACCENTS`, `BngTabs`, `BngIcon`+`icons`, `BngSwitch`, `BngDropdown`, `BngColorPicker`, `BngCardHeading`), directives `vBngTextInput`, `vBngTooltip` from `@/common/directives`. Never the legacy ones: `styles/modules/legacy/*`, `--bng-black-8`-style names, `bngOldIcon`, `bngDrawerOld`, `utility/tab.vue`, accent `custom_old`, class `bng-app`.
- Every icon name must exist in `~/.local/share/Steam/steamapps/common/BeamNG.drive/ui/ui-vue/src/assets/fonts/bngIcons/bngIcons.js` (`make vuecheck` checks this once Task 1 is in). Names from the spec: `stopwatchArrows02`, `eyeSolidOpened`, `eyeSolidClosed`, `carChase01`, `strobeLights`, `restart`, `mapPoint`, `caution`, `danger`, `abandon`, `checkmarkBold`, `lockClosed`, `cup`, `group`, `info`, `cogSolid`, `play`, `flag`, `timer`.
- Player-facing copy is English, plain, gender-neutral ("they", "the runner").
- `client/lua/ge/extensions/copsAndRobbers.lua` is near LuaJIT's upvalue limit inside `onUpdate`: add no new upvalues there; put new logic in modules.
- Version stays `2.0.7` until Task 17 bumps server `VERSION` and client `CLIENT_VERSION` together to `2.1.0`.
- Commit messages follow the repo style (`feat:`, `fix:`, `docs:`, `chore:`) and end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_015vhaagYNpbvdjJr9efxGQG
  ```
- Between Task 7 (panel state) / Task 11 (HUD payload) and the Vue rewrites (Tasks 13–16) the old apps may render wrongly on this branch. That is expected; don't deploy the branch to the group's server before Task 16.
- In-game checks need the user (the executor can't run BeamNG). Tasks 2, 14, 15 and 16 end with a checklist: run `make package`, ask the user to install and check, and wait for their answer before committing.

## Review Focus

1. **A player who joins mid-round** gets rules, lobby and colour on join and sees the round HUD, not the lobby card (tests in Tasks 5 and 11).
2. **A practice round started by someone else**: everyone else stays in the lobby card with "Practice round: <name>" (tests in Tasks 5 and 11).
3. **Settings set to 0** (time limit, sight, last-seen pings): no "/ 0:00" on the chase line and How to play's rules read "no time limit" / "sight is off" (tests in Task 11).
4. **Old runs saved before the timeline existed, and runs with sight off**: the Rounds list shows them with `timeline = nil` and `sightPct = nil` instead of failing (test in Task 8).
5. **Leaving the server** removes the HUD and any panel/leaderboard the HUD opened from every layout (test in Task 10).

---

### Task 1: Vue compile check (`make vuecheck`)

**Files:**
- Create: `tools/vuecheck/package.json`, `tools/vuecheck/check.mjs`
- Modify: `Makefile`, `.gitignore`

**Interfaces:**
- Produces: `make vuecheck` → exit 0 when every `.vue` under `client/ui` parses and compiles and every icon name used exists; exit 1 with `file: message` lines otherwise.

- [ ] **Step 1:** `tools/vuecheck/package.json`: `{"private": true, "type": "module", "dependencies": {"@vue/compiler-sfc": "3.5.43", "sass": "1.105.0"}}` (the versions the game's own runtime uses, `ui/ui-vue/runtime/package.json`).
- [ ] **Step 2:** `check.mjs <dir>...`: for every `.vue` file: `parse` (errors fail), `compileScript(descriptor, {id})` when there is a script, `compileTemplate({source, filename, id, compilerOptions: {bindingMetadata}})` (errors fail), each `lang="scss"` style through `sass.compileString` with an importer that maps `@/` to `$BNG_UI_SRC` (default `~/.local/share/Steam/steamapps/common/BeamNG.drive/ui/ui-vue/src`) and relative paths to the file's folder. Icon check: collect names from `icons.<name>` and `type="<name>"`/`:type="'<name>'"` in templates and scripts, and fail on any name not matching `^  <name>: {` in `$BNG_UI_SRC/assets/fonts/bngIcons/bngIcons.js` (skip the icon check with a warning when that file is missing).
- [ ] **Step 3:** `Makefile` target `vuecheck: cd tools/vuecheck && npm install --silent --no-audit --no-fund && node check.mjs ../../client/ui`. `.gitignore`: `tools/vuecheck/node_modules/`. Commit `package-lock.json`.
- [ ] **Step 4:** Run `make vuecheck`. Expected: exit 0 on today's three apps.
- [ ] **Step 5:** Copy `client/ui/modules/apps/CopsAndRobbersHud/app.vue` to a temp dir, break a closing tag and add `<BngIcon type="nopeIcon"/>`, run `node tools/vuecheck/check.mjs <tmpdir>`. Expected: exit 1, two error lines. Delete the temp dir.
- [ ] **Step 6:** Commit `chore: make vuecheck compiles the Vue apps and checks icon names`.

### Task 2: Shared UI kit + in-game spike (user checkpoint)

**Files:**
- Create: `client/ui/modules/copsAndRobbers/CnrRoot.vue`, `CnrCard.vue`, `RoleChip.vue`, `format.js`
- Create (temporary, deleted in this task): `client/ui/modules/apps/CopsAndRobbersSpike/app.json`, `app.vue`, `app.png` (copy of the HUD's)
- Modify: `docs/DEPENDENCIES.md` (UI section)

**Interfaces:**
- Produces (imported by Tasks 13–16 as `../../copsAndRobbers/<file>` from an app folder, or the fallback path recorded in Step 6):
  - `CnrRoot.vue`: wraps its slot in `<div class="cnr-root">`; a non-scoped style defines on `.cnr-root` the CSS variables `--cnr-runner`, `--cnr-runner-text`, `--cnr-cop`, `--cnr-cop-text`, `--cnr-warn`, `--cnr-good`, `--cnr-accent`, `--cnr-main`, `--cnr-me`, `--cnr-text`, `--cnr-muted`, `--cnr-card`, `--cnr-row`, `--cnr-shadow`, `--cnr-display` mapped to the Global Constraints tokens, plus `color: var(--cnr-text)` and `font-family: var(--fnt-defs)`.
  - `CnrCard.vue`: props `title: String`, `sub: String`, `closable: Boolean`; emits `close`; slots `default`, `actions`. Header = `BngCardHeading` (`type="line"`) with the title, `sub` in muted small text, a ✕ `BngButton` (`accent="ghost"`, icon `xmark`) when closable.
  - `RoleChip.vue`: props `role: "runner"|"cop"`, `label: String`.
  - `format.js`: `formatTime(seconds) → "m:ss"`, `formatDistance(meters) → "230 m" | "2.4 km"` (≥1000 m one decimal km), `hexToHsl(hex) → {hue, saturation, luminosity}` (all 0..1, the `BngColorPicker` model), `hslToHex({hue, saturation, luminosity}) → "#rrggbb"`, `mapName({id, title, pretty}, translate) → string` (use `translate(title)` when it returns something other than the key and not starting with `levels.`, else `pretty`, else `id`).

- [ ] **Step 1:** Write the four shared files to the Interfaces above.
- [ ] **Step 2:** Spike app: `app.json` with `"directive": "copsAndRobbersSpike"`, `"vue": true`, `"interactive": "no"`, `css` `{left: "0", top: "0", width: "100%", height: "100%"}`. `app.vue` imports `CnrRoot`, `CnrCard` and `format.js` by relative path, fills the screen with a `pointer-events: none` container, and shows a `CnrCard` (with `pointer-events: auto`) containing: a counter button; a `BngColorPicker` (`v-model` an HSL object) with the hex from `hslToHex` next to it; buttons running `api.engineLua('ui_appLayouts.addApp(ui_appLayouts.getCurrentLayout().filename, "copsAndRobbersLeaderboard", {left="1em", top="6em", width="25em", height="32em"})')` and the matching `removeApp` (find the index in `getCurrentLayout().apps`).
- [ ] **Step 3:** `make vuecheck` then `make package`. Expected: both succeed.
- [ ] **Step 4:** Ask the user to install the package, add "Cops and Robbers Spike" via Esc > UI Apps, and report:
  1. the counter button clicks, while the game and other apps under the empty area still take clicks;
  2. in the layout editor, other apps can still be selected and moved (if not, note what happens);
  3. the card shows the shared look and `formatTime` output (shared import works);
  4. the colour picker works and its hex matches the colour;
  5. the leaderboard opens and closes from the buttons, between rounds and during a practice round.
- [ ] **Step 5:** If check 3 fails: move the shared files into each app as `client/ui/modules/apps/<App>/shared/` copies, import them with `./shared/...`, and record that this is the fallback. If check 1 or 2 fails: stop and bring the user's report back before any HUD work. If 4 fails: fall back to a hex text field only and tell the user.
- [ ] **Step 6:** Record the results in `docs/DEPENDENCIES.md` under "BeamNG.drive: UI": full-screen click-through (`interactive: "no"` + `pointer-events: auto` on buttons), the layout-editor finding, how shared files are imported, `BngColorPicker` HSL model, opening apps with `ui_appLayouts.addApp`. Delete `CopsAndRobbersSpike/`.
- [ ] **Step 7:** `make vuecheck && make test`, commit `feat: shared UI kit for the apps (verified in game)`.

### Task 3: Server goes quiet (notices instead of chat, no chat commands)

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/cnr/round.lua`
- Test: `tests/test_main.lua`, `tests/test_round.lua`, `tests/test_client.lua` (AI names only)

**Interfaces:**
- Produces: server→client `cnr_notice` `{msg: string, tone: "info"|"warn", about?: pid}`; round effects `{kind = "broadcast", msg, tone = "warn"|nil}`; AI names `"AI cop 1"`, `"AI cop 2"` (practice as runner) and `"AI runner"`, `"AI cop"` (practice as cop); AI colours runner `"#d83a2c"`, cops `"#1f6fe0"`, `"#6fb0ff"`.

- [ ] **Step 1: Tests (test_main).** Add to `boot`: `env.noticeHas(text, tone)` (searches `cnr_notice` in `env.sent`, optional tone match). Replace every `env.chatHas(...)` assertion that still applies with `env.noticeHas(...)`; drop the ones for messages this task removes. New tests:
  - `"the mod never writes to chat over a full round"`: the "full round over main wiring" flow, then `assertEq(#env.chats, 0)`.
  - `"chat commands are swallowed with a notice"`: `assertEq(env.call("onChatMessage", 1, "Reinder", "/cnr color #ff0000"), 1)`; last `cnr_notice` has `pid == 1` and contains `Chat commands are gone: use the Cops and Robbers card at the bottom of your screen.`
  - `"panel replies go to the panel only"`: `env.panel(2, "go")` with no round → last `cnr_panelReply` text `No round set up, start one in the panel`, and no `cnr_notice` sent to 2.
  - `"rule breaks are warn notices"`: illegal reset and teleport (existing setups) → `env.noticeHas("Reinder reset illegally", "warn")`; parts change → `noticeHas("⚠ Reinder changed parts during the round: engine", "warn")`; penalty notice carries `"tone":"warn"`.
- [ ] **Step 2: Tests (test_round).** `vehiclePicked`, `go`, the countdown→headstart→release ticks, `reroll`, and a caught practice round produce no `broadcast` effects; `vehicleReset` illegal and the teleport check produce `broadcast` with `tone == "warn"`; `cancel` keeps its message with no tone. Practice names/colours: as runner `r.players[-10] == "AI cop 1"`, `r.players[-11] == "AI cop 2"`; as cop `"AI runner"` / `"AI cop"`; the `setupAI` effect colours are `"#1f6fe0"`, `"#6fb0ff"` (as runner) and runner `"#d83a2c"`.
- [ ] **Step 3:** Run `make test`. Expected: the new/changed tests fail.
- [ ] **Step 4: Implement in `round.lua`:** delete the broadcasts in `vehiclePicked` (runner announcement, practice explanations), `go`, `tick` ("is off!", "Cops released!"), `finish` ("Test round: … caught"), `reroll` ("Picking a new car..."); add `tone = "warn"` to the illegal-reset and teleport broadcasts; new names and colours above.
- [ ] **Step 5: Implement in `main.lua`:** local `notify(pid, msg, tone)` sends `cnr_notice` `{msg, tone = tone or "info"}`; `reply(pid, msg)` sends only `cnr_panelReply` when `panelMirror == pid`, else `notify(pid, msg)`; `broadcast(msg, tone)` = `notify(-1, msg, tone)`; `applyEffects` passes `e.tone` (`e.to` → `notify(e.to, …)`). Remove: the "Next round in" broadcast, the result and top-5 broadcasts in `record` (keep `cnr_top`), the "Cars ready" message in `applied`, `HELP`, `handlers.help`, `handlers.version`, `CHAT_COMMANDS`. `cnr_notice` for penalties and missing parts gets `tone = "warn"`; parts changed uses `broadcast(msg, "warn")` (or `notify(current.issuerId, msg, "warn")` in practice). `cnrOnChatMessage`: `commands.parse(msg)` → notify the sender with the "Chat commands are gone…" line and return 1; else 0. `handlers.color` stays for Task 4 to rewire; nothing calls it from chat any more.
- [ ] **Step 6:** Update `tests/test_client.lua` lines using `"AI green"` to `"AI cop 1"`. Run `make test` and `grep -rn "SendChatMessage" server/`. Expected: all pass, grep prints nothing.
- [ ] **Step 7:** Commit `feat: the server talks through notices, not chat; chat commands are gone`.

### Task 4: Server: colour, gas stations and "start now" from the apps

**Files:**
- Modify: `server/CopsAndRobbers/main.lua`, `server/CopsAndRobbers/cnr/panel.lua`
- Test: `tests/test_main.lua`, `tests/test_panel.lua`

**Interfaces:**
- Consumes: `reply`/`notify` from Task 3.
- Produces:
  - client→server `cnr_color` `{hex?: string}` (absent/empty = no colour); server→client `cnr_myColor` `{hex?: string, error?: string}` (sent on join and after every `cnr_color`).
  - `cnr_panel` actions `{action = "station", op = "add"|"remove"}` (answers through `cnr_panelReply` with today's texts) and `{action = "stations"}` → `cnr_stationList` `{geo: bool, stations: [{x,y,z}] | [{lat,lon}]}`.
  - panel command `next` (in `panel.COMMANDS`) → `handlers.next(pid)`: starts the scheduled automatic round now, else replies `No round is scheduled`.

- [ ] **Step 1: Tests.** `"colour from the UI is saved and confirmed"` (`env.call("cnr_color", 1, '{"hex":"#ff0000"}')` → last `cnr_myColor` to 1 has `"hex":"#ff0000"`; `data/colors.json` contains it); `"a bad colour answers with the error and the old colour"` (`"#zz"` → `error` = `Use a hex color like #ff0000`); `"no colour clears it"` (`'{}'` → `cnr_myColor` without hex); `"colour in prep repaints"` (after `env.startRound()` → `cnr_paint` to 1); `"join sends your colour"`. Stations: `"Map tab adds and removes a station where you stand"` (position 0 → `cnr_panelReply` `Gas station added (1 on west_coast_usa)`, then remove → `Gas station removed (0 left on west_coast_usa)`; far away → `No gas station within 50 m`); `"stations list"` → `cnr_stationList` with one `{x,y,z}`; geo variant booted with `map = "/levels/beamng_earth/info.json"` and a `cnr_geo` report → `geo = true` and `lat`/`lon`. `"Start now starts the scheduled round"` (auto on, finish a round, `env.panel(1, "next")` → `cnr_pickVehicle` sent) and `"next without a schedule"` → reply text. test_panel: `panel.allow("next") == "next"`.
- [ ] **Step 2:** `make test`. Expected: new tests fail.
- [ ] **Step 3:** Implement `cnrOnColor(pid, data)` (register `cnr_color`) reusing `handlers.color`'s logic, but answering with `cnr_myColor`; send `cnr_myColor` in `cnrOnPlayerJoin`; panel actions `station`/`stations` (run `handlers.addstation`/`removestation` with `panelMirror = pid`, then `pushPanel()`); `handlers.next`; `panel.COMMANDS.next = true`.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit `feat: colour, gas stations and start-now through the apps`.

### Task 5: Server: rules and lobby for every client

**Files:**
- Create: `server/CopsAndRobbers/cnr/rules.lua`
- Modify: `server/CopsAndRobbers/main.lua`
- Test: create `tests/test_rules.lua`; modify `tests/test_main.lua`

**Interfaces:**
- Produces:
  - `rules.KEYS = {"runnerCountdownSeconds","headStartSeconds","catchHoldSeconds","catchRadiusMeters","catchMaxSpeedKmh","resetWaitSeconds","copResetMinDistanceMeters","crashSpeedLossKmh","crashPenaltySeconds","sightMaxMeters","lastSeenIntervalSeconds","roundTimeLimitSeconds","carMode"}`; `rules.payload(cfg) → table` with exactly those keys.
  - server→client `cnr_rules` (the payload): to a joiner, to everyone at plugin load, and to everyone after a panel settings save, `reload` and `auto on/off`.
  - server→client `cnr_lobby` `{online: number, practice?: string (issuer name), active: bool (a real round is on)}`: to a joiner, and to everyone whenever it changes (signature compared in `cnrTick`).

- [ ] **Step 1: Tests.** test_rules: payload has the 13 keys with the config's values and nothing else. test_main: `"a joiner gets rules, lobby and colour"`; `"a mid-round joiner also gets them"` (start a round, run to `running`, `env.call("onPlayerJoin", 2)` → `cnr_rules`, `cnr_lobby`, `cnr_myColor` and `cnr_roundSetup` with `phase = "running"` to 2) — Review Focus 1; `"saving a setting re-sends the rules"` (panel settings `headStartSeconds = 9` → last `cnr_rules` to -1 has `"headStartSeconds":9`); `"lobby shows a practice round by someone"` (`env.panel(1, "test runner")` + tick → `cnr_lobby` to -1 with `"practice":"Reinder"`) — Review Focus 2; `"lobby online count follows players"` (`env.names = {"Reinder"}` + tick → `"online":1`).
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement `rules.lua`; in `main.lua` `pushRules()` (send -1) and `lobbyState()`; send on join; compare `panel.signature(lobbyState())` each tick.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit `feat: clients get the live rules and the lobby state`.

### Task 6: Server: a timeline for every recorded round

**Files:**
- Modify: `server/CopsAndRobbers/cnr/round.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_round.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces: `Round:note(now, kind, name, seconds)`; `kind ∈ {"lost","penalty","illegalReset","teleport","partsChanged"}`; entries `{t = chase seconds (one decimal, 0 during the head start), kind, name, seconds?}`; at most 50 per round (`MAX_TIMELINE = 50`), only in `headstart`/`running`. Recorded runs gain `timeline` (array, possibly empty).

- [ ] **Step 1: Tests (test_round).** `"an illegal reset is noted"` (`kind = "illegalReset"`, `name = "Reinder"`, `t` = seconds since release); `"a crash penalty is noted with its seconds"`; `"losing the cops is noted"` (runner name); `"a teleport is noted"`; `"the timeline stops at 50"`; `"the timeline is saved with the run"` (the `record` effect's `run.timeline` equals the notes). test_main: `"a parts change is noted and saved"` (the parts-change flow, then end the chase → `data/leaderboard.json` contains `"partsChanged"`).
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement `note`, `self.timeline = {}` in `clear`, calls at the illegal reset, the teleport, the penalty and `lostCount` increment, `run.timeline` in `finish`; in `main.lua` `checkParts` calls `current:note(now(), "partsChanged", name)`.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit `feat: each recorded round keeps a timeline`.

### Task 7: Server: host panel state for "only what you can do now"

**Files:**
- Modify: `server/CopsAndRobbers/cnr/panel.lua`, `server/CopsAndRobbers/cnr/build.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_panel.lua`, `tests/test_build.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces (`cnr_panelState` / `CnRPanel` gains, everything else unchanged):
  - `players`: array (sorted by name, case-insensitive) of `{name, runs, next: bool, last: bool, role?: "runner"|"cop", state?: "loading"|"ready"|"changing"|"missing", change?: string, missing?: number}` — replaces today's array of names.
  - `nextRunner?: string`, `lastRunner?: string`, `goBlocked?: string`, `autoNext?: {seconds, runner}`, `lastResult?: {runner, seconds, reason}`, `stationCount: number`, `geo: bool`, `build?: {label, step, name, lastChange?: {step, by, text}}`.
  - `panel.playerRows(entries, nextName, lastName) → rows`; `panel.goBlocked(phase, evolving, runnerName, loading) → string|nil`: evolving `prep` → `Waiting for <runner> to apply the change`; `applying` → `Applying the change: <n> cars still loading` (n>0) or `Applying the change`; else nil.
  - `build.lastChange(b) → nil|{step, by, text}`: text = `"<label> <from> → <to>"` of the first change, plus `" and N more"` when there are more.
  - State rules (display only): role/state only while a real (non-practice) round is active; `loading` while the player's car is being placed (`partsBaseline[pid].placing`), `missing` after `cnr_missing` (count kept per pid until the round ends), `changing` for the evolving runner in prep with `change` = first queued change label, else `ready`.

- [ ] **Step 1: Tests.** test_build: `lastChange` text for one change and for three (`" and 2 more"`), nil without history. test_panel: `playerRows` sorting and flags; every `goBlocked` case. test_main: `"panel marks next and last runner"`; `"prep rows show loading until the car is placed"` (after `startRound`, row for Bob `state = "loading"`, after `cnr_myVehicle` from 2 → `ready`); `"evolving prep blocks GO with the runner's name"`; `"after a round with auto on the panel shows the next round"` (`autoNext.seconds == 15`, `runner` set) and `lastResult`; `"station count"`.
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement `panel.playerRows`, `panel.goBlocked`, `build.lastChange`; in `main.lua` build the entries (runs from `runCounts`, next via `commands.matchPlayer("next", …)`, last from `lastRunnerKey`), keep `missingCount[pid]` (cleared on round start/end), `lastResult` (set on a non-cancelled `roundEnd`, cleared on start), and pass everything to `panel.snapshot`.
- [ ] **Step 4:** `make test`. Expected: pass (update existing tests that read `players` as names; the old panel app's runner list breaks until Task 15, as noted in Global Constraints).
- [ ] **Step 5:** Commit `feat: panel state says who's next, who's ready and why GO waits`.

### Task 8: Server: leaderboard with "you", assists and a Rounds list

**Files:**
- Modify: `server/CopsAndRobbers/cnr/leaderboard.lua`, `server/CopsAndRobbers/main.lua`
- Test: `tests/test_leaderboard.lua`, `tests/test_main.lua`

**Interfaces:**
- Produces:
  - `leaderboard.rankOf(board, filter, key) → rank|nil, entry`.
  - `leaderboard.cops(board, filter, limit, assistPercent)` rows gain `assists` (same rule as `players`).
  - `leaderboard.rounds(board, filter, limit) → array` newest first (by `endedAt`) of `{id (index in board.runs), endedAt, map, player, survivedSeconds, endReason, catchers, model, mode, buildStep, timeline?, cops = [{name, sightPct?, catcher: bool}]}`; `sightPct` = rounded share of `chaseSeconds` (nil when the run has no `hiddenSeconds`, i.e. sight was off); `timeline` nil for runs without one.
  - `cnr_boardState` gains: `me: true` on the viewer's rows in `runners`, `cops`, `players`; `mine?: {rank, player, survivedSeconds, model, map}` when the viewer has a best time outside the top 20; `rounds` (sub.rounds, default 30); action `{action = "more"}` adds 30 (max 300).
  - `cnr_top` is sent per player: `{rows = [{rank, player, time, me}]}` (top 3 for the map).

- [ ] **Step 1: Tests.** test_leaderboard: `rankOf`; cops `assists`; `rounds` order, fields, `cops[i].sightPct`; `"an old run without a timeline or sight data"` → `timeline == nil`, `sightPct == nil` (Review Focus 4). test_main (use `env.ids = {[1] = {beammp = "11"}, [2] = {beammp = "22"}}`): viewer's runner row has `me`; `mine` pinned with 21 runs seeded through `opts.leaderboard`; `"more"` raises the rounds count; `cnr_top` to 1 has `me` on its own row only.
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement in `leaderboard.lua`; in `main.lua` `boardState(sub, viewerKey)` (call with `playerKey(pid)`), strip keys after marking `me`, and the per-player `cnr_top`.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit `feat: leaderboard knows who you are, counts assists and lists rounds`.

### Task 9: Client goes quiet (HUD events and standing warnings instead of pop-ups)

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers.lua`, `copsAndRobbers/hudfeed.lua`, `copsAndRobbers/game.lua`, `copsAndRobbers/inputs.lua`, `copsAndRobbers/ai.lua`
- Test: `tests/test_client.lua`, `tests/test_hud.lua`

**Interfaces:**
- Consumes: `cnr_notice` `{msg, tone}` (Task 3).
- Produces: `hudfeed.event(text, clock, tone)` (`tone` `"info"`|`"warn"`, entries `{text, tone, untilT}`); `hudfeed.warning(key, text|nil)` and `hudfeed.warnings() → array of texts` (keys `"binding"`, `"earth"`, `"version"`); `inputs.setNotify(fn)`, `ai.setNotify(fn)`. `game.toast` and `hudfeed.notify` no longer exist.
- Texts: binding `Bind a reset or recover button to reset during rounds`; earth `Cops and Robbers needs a newer BeamNG.Earth (API v1) on this map`; version `Your copy is <client>, the server runs <server>: rejoin to update`; lock `Parts and paint are locked during a round. Use the Colour button for your car colour`.

- [ ] **Step 1: Tests.** `"no pop-ups during a full round"` (setup → countdown → runnerGo → release → state with hints → penalty → roundEnd: `assertEq(#env.toasts, 0)`); `"notices become HUD events with their tone"`; `"a missing reset binding is a standing warning until bound"` (setup with no binding → `hudfeed.warnings()` contains the text; setup with a binding → gone); `"version mismatch is a standing warning"`; `"a locked menu becomes a HUD event"` (replace the test at line ~572); `"reset refused in prep is a HUD event"`. Update tests that read `env.toasts` (lines ~369, ~742) to read HUD events instead.
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement: replace every `toast(...)`/`hudfeed.notify(...)` call per the spec's message table (round-flow and status/countdown ones are deleted, including `updateCountdownToast` and `showEndToast`). `updateStatusToast` loses its toast but keeps its once-a-second `geo.gpsInfo()` refresh of `infoText` (BeamNG.Earth's distance on the status line): rename it `updateGpsInfo` in place so `onUpdate` keeps the same number of upvalues; `onNotice` → `hudfeed.event(d.msg, clock, d.tone == "warn" and "warn" or "info")`; inputs/ai notifiers set in `onExtensionLoaded`.
- [ ] **Step 4:** `make test` and `grep -rn "ui_message" client/lua`. Expected: pass, grep prints nothing.
- [ ] **Step 5:** Commit `feat: the client shows everything in the HUD, no pop-ups`.

### Task 10: Client: full-screen HUD that stays, and apps the HUD opens

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/apps.lua`
- Modify: `copsAndRobbers/placement.lua`, `copsAndRobbers/hudfeed.lua` (placement code moves out), `copsAndRobbers.lua`, `client/ui/modules/apps/CopsAndRobbersHud/app.json`
- Test: `tests/test_placement.lua`, `tests/test_client.lua`

**Interfaces:**
- Produces:
  - `placement.new(appName, placement, opts)`; `opts.sticky = true` re-adds an app the player removed instead of opting out.
  - `apps.APPS = {hud = {app = "copsAndRobbersHud", placement = {left = "0", top = "0", right = "", bottom = "", width = "100%", height = "100%"}, sticky = true}, panel = {app = "copsAndRobbersPanel", placement = {left = "", right = "1em", top = "6em", width = "27.5em", height = "34em"}}, board = {app = "copsAndRobbersLeaderboard", placement = {left = "1em", top = "6em", width = "25em", height = "32em"}}}`.
  - `apps.start(clock)`, `apps.update(clock)` (called from `hudfeed.update`, so `onUpdate` gains no upvalue), `apps.layoutChanged(clock)`, `apps.leave()`, `apps.placed() → bool` (HUD in the layout), `apps.toggle(name)` (`"panel"`|`"board"`), `apps.isOpen(name) → bool` (app present in the current layout, however it got there), `apps.refreshApps()` (the `onFilesChanged` hook for all three apps' files).
  - HUD `app.json`: `"interactive": "no"`, `css` `{left: "0", top: "0", width: "100%", height: "100%"}`, no min sizes.

- [ ] **Step 1: Tests.** test_placement: `"a sticky app comes back after the player removes it"`; the existing opt-out test stays for non-sticky apps. test_client (with `opts.layouts`): `"the HUD is placed full-screen"` (the `addApp` placement has `width = "100%"`); `"toggle opens and closes the leaderboard"` (`require("copsAndRobbers/apps").toggle("board")` + update → present; again → removed); `"isOpen sees an app the player added"`; `"leaving the server removes the HUD and the apps it opened"` (Review Focus 5).
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement `apps.lua` (move `placementEnv`, the placement timing constants and `refreshApps` from `hudfeed.lua`), sticky in `placement.tick`, wire `copsAndRobbers.lua` (`hudfeed.placed` callers → `apps.placed`, `hudfeed.start/leave/layoutChanged/refreshApps` → `apps.*`), update the HUD `app.json`.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit `feat: full-screen HUD that stays put and opens the other apps`.

### Task 11: Client: HUD payload v2, the UI router and How to play state

**Files:**
- Modify: `copsAndRobbers/hud.lua`, `copsAndRobbers/hudfeed.lua`, `copsAndRobbers.lua`
- Test: `tests/test_hud.lua`, `tests/test_client.lua`

**Interfaces:**
- Consumes: `cnr_rules`, `cnr_lobby`, `cnr_myColor` (Tasks 4–5), `cnr_top` rows (Task 8), `apps.isOpen` (Task 10).
- Produces the `CnRHud` payload (the contract Tasks 13–14 render), pushed at 10 Hz while connected to a Cops and Robbers server (`hudfeed.connect(true)` on `cnr_mode`, false on leave → one `{visible = false}`):
  ```
  { visible, mode = "lobby"|"round"|"result", driving = bool (countdown, head start or chase),
    lobby?  = { online, status, color?, warnings = {text...}, apps = {panel = bool, board = bool} },
    center? = { kind = "role", role, car, title, rule }            -- prep
            | { kind = "countdown", label, number, tone = "runner"|"cop"|"warn" }
            | { kind = "flash", text } | { kind = "applying", text = "APPLYING CHANGES" },
    prep?   = { waiting, color? },                                  -- bottom line in prep
    change? = (today's change block),                               -- evolving prep
    status? = { role, time, limit?, tag?, info?, reset, resetFlash, releaseIn? },
    catch   = (today's catch block),
    notices = { {text, tone} ... }  (newest 2, 4 s each),
    result? = { title, runner?, time?, catchers?, rows = {{rank, player, time, me}}, nextIn? },
    help    = { open = bool, rules? (cnr_rules payload, only when open) } }
  ```
  - `hud.ruleLine(role, runnerName, rules) → string`:
    - runner: `Survive as long as you can. Cops catch you by holding you under %g km/h within %g m for %g s.`
    - cop: `%s is the runner. You're released %g s after the runner. Catch them by holding them under %g km/h within %g m for %g s.`
  - `center.title`: `YOU'RE THE RUNNER` / `YOU'RE A COP`; `prep.waiting`: `Waiting for the host to press GO`, evolving runner `Make your change, then press Apply`, evolving others `Waiting for <runner>'s change`.
  - `lobby.status`: `Waiting for the host to start a round` | `Practice round: <name>` | `A round is running`.
  - `status.limit`: `hud.formatTime(roundTimeLimitSeconds)` when > 0, else nil.
  - The runner gets `status` already during the head start (`time = "0:00"`, `releaseIn` = whole seconds left until the cops are released); cops get `status` from their release, as today.
  - `copsAndRobbers.ui(msg)` router: `{action = "hello"}` (push now), `{action = "toggleApp", name}`, `{action = "color", hex?}` (→ `cnr_color`), `{action = "help", open}` (closing writes `settings/cnr_help_seen.json` `{seen = true}`), `{action = "apply"}`.
  - First time on a server (no seen file): `help.open = true` after `cnr_mode`.

- [ ] **Step 1: Tests (test_hud).** Lobby payload when idle (status, online, warnings, apps flags); `"practice by someone else keeps the lobby"` (Review Focus 2); prep `rule` exact strings with defaults (3 km/h, 10 m, 7 s, head start 7 s); `"time limit shows only when set"` (600 → `limit = "10:00"`, 0 → nil; Review Focus 3); `"help rules read sensibly at 0"` — `rules` passes through unchanged and the payload sets `help.rules.noLimit = true` when `roundTimeLimitSeconds == 0` and `help.rules.sightOff = true` when `sightMaxMeters == 0` (Review Focus 3); notices newest 2 with tone; `result.rows` passthrough with `me`; `driving` true from countdown to round end.
- [ ] **Step 2: Tests (test_client).** `cnr_rules` → `help.rules` when open; `"first join opens How to play and Got it remembers"` (seen file written; a second `bootClient` with `files = {["settings/cnr_help_seen.json"] = {seen = true}}` keeps it closed); `env.M.ui({action = "color", hex = "#00ff00"})` sends `cnr_color`; `"a mid-round joiner sees the round, not the lobby"` (`cnr_roundSetup` with `phase = "running"` → `mode = "round"`; Review Focus 1); `cnr_myColor` sets `lobby.color`.
- [ ] **Step 3:** `make test`. Expected: fail.
- [ ] **Step 4:** Implement in `hud.lua` (payload + helpers), `hudfeed.lua` (`connect`, `lobby`, `rules`, `color`, `help`, `prep(role, car, waiting, runner)`, always-on push), `copsAndRobbers.lua` (handlers `cnr_rules`, `cnr_lobby`, `cnr_myColor`; `M.ui`; the seen file; pass the runner's name into `hudfeed.prep`; `cnr_top` → rows).
- [ ] **Step 5:** `make test`. Expected: pass.
- [ ] **Step 6:** Commit `feat: one HUD payload for lobby, round and result, plus How to play state`.

### Task 12: Client: map names and nearest gas stations for the apps

**Files:**
- Create: `client/lua/ge/extensions/copsAndRobbers/nearby.lua`
- Modify: `copsAndRobbers/game.lua`, `copsAndRobbers.lua`
- Test: create `tests/test_nearby.lua`; modify `tests/test_client.lua`

**Interfaces:**
- Produces:
  - `game.mapTitle(id) → {id, title?, pretty}`: `title` from `core_levels.getLevelTitle(id)` when available; `pretty` = words split on `_`, capitalised, with `usa → USA`, `uk → UK`, and the whole id `beamng_earth → BeamNG.Earth`.
  - `CnRBoard` gains `mapNames = {[id] = {id, title?, pretty}}` (current map, filter maps); `CnRPanel` gains `mapName`.
  - `nearby.nearest(points, here, limit) → {{index, meters}}` sorted, `meters` rounded.
  - `cnr_stationList` → `guihooks.trigger("CnRStations", {count, nearest = {{meters}} (3), canRemove = nearest[1].meters <= 50})`; geo points through `geo.toGame(lat, lon, 0)`.

- [ ] **Step 1: Tests.** test_nearby: order, limit, rounding, empty list. test_client: `"board names maps"` (no `core_levels` → `pretty = "West Coast USA"`, `beamng_earth` → `BeamNG.Earth`); `"station list gives the nearest three and whether one can be removed"`.
- [ ] **Step 2:** `make test`. Expected: fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test`. Expected: pass.
- [ ] **Step 5:** Commit `feat: real map names and nearest gas stations for the apps`.

### Task 13: HUD app: round displays

**Files:**
- Rewrite: `client/ui/modules/apps/CopsAndRobbersHud/app.vue`
- Create: `CopsAndRobbersHud/HudCenter.vue`, `HudChase.vue`, `HudNotices.vue`, `HudResult.vue`, `HudChange.vue`

**Interfaces:**
- Consumes: the `CnRHud` payload (Task 11), shared kit (Task 2), `copsAndRobbers.ui(...)` (Task 11).
- `app.vue`: `CnrRoot` filling the screen, `pointer-events: none`; `useEvents().on("CnRHud", …)`; on mount `api.engineLua('if copsAndRobbers then copsAndRobbers.ui({action="hello"}) end')`; renders `HudCenter` (centre, top ≈ 22 %), and at the bottom centre (≈ 4.5 rem up, max width ≈ 40 rem) `HudNotices` above `HudChase`/`HudChange`; `HudResult` in the centre in `result` mode. Only `HudChange`'s Apply button has `pointer-events: auto`.
- Style (spec §2): police-chase treatment, no boxes except `HudChange` (a `CnrCard`); `HudCenter` label small caps-style Overpass 800 over a big mono number; role title italic Overpass 900 in the role's text colour; `HudChase` one row (role chip, `stopwatchArrows02` + time [+ muted `/ limit`], `eyeSolidOpened`/`eyeSolidClosed` + tag in its colour — SPOTTED `--cnr-warn`, HIDDEN muted, IN SIGHT `--cnr-good`, LIVE `--cnr-cop-text` —, `carChase01`/`mapPoint` + info), a small reset line with `restart` (no key shown), and the thin catch bar (runner red / cop blue on `--bng-black-o2`); `HudNotices` icon `caution` + text in `--cnr-warn` for warn, muted otherwise; `HudResult` title in the runner's colour for caught, `--cnr-good` for escaped, muted otherwise, top-3 rows with `me` outlined in `--cnr-me`, `NEXT ROUND IN n`.

- [ ] **Step 1:** Write the components to the Interfaces and the approved mockup `hud-round.html` (frames 5–8; no key on the reset line).
- [ ] **Step 2:** `make vuecheck`. Expected: pass.
- [ ] **Step 3:** Commit `feat: HUD round displays in the native police-chase style` (the in-game check happens after Task 14).

### Task 14: HUD app: lobby card, colour picker, prep line and How to play (user checkpoint)

**Files:**
- Create: `CopsAndRobbersHud/HudLobby.vue`, `HudPrep.vue`, `HudColor.vue`, `HowToPlay.vue`
- Modify: `CopsAndRobbersHud/app.vue`

**Interfaces:**
- `HudLobby` (`CnrCard` titled "Cops and Robbers", `sub` = "<n> online"): status line; standing warnings in `--cnr-warn` with `caution`; buttons Colour (swatch), How to play (`info`), Leaderboard (`cup`), Host panel (`cogSolid`) — the last two show open state from `lobby.apps` and send `{action = "toggleApp", name}`.
- `HudPrep` (bottom line in prep): `lockClosed` + `prep.waiting`, buttons Colour, How to play, Host panel.
- `HudColor` (`CnrCard` "Your car colour", closable): `BngColorPicker` (model via `hexToHsl`), hex field (`vBngTextInput`, validated `^#?[0-9a-fA-F]{6}$`), No colour, Done → `{action = "color", hex}`; opens from both Colour buttons.
- `HowToPlay` (centred `CnrCard` "How to play", closable, plus Got it): `BngTabs` Basics / Runner / Cop / Resets / Rules with the spec §5 content; every number from `help.rules` in `--cnr-me` mono; `help.rules.noLimit` → "no time limit", `help.rules.sightOff` → "sight is off" (and no last-seen sentence); the Rules tab's evolving part only when `rules.carMode == "evolving"`; close/Got it → `{action = "help", open = false}`.
- All buttons and cards `pointer-events: auto`; everything else click-through.

- [ ] **Step 1:** Write the components to the Interfaces and the approved mockups (`hud-round.html` frames 1–4, `how-to-play.html`).
- [ ] **Step 2:** `make vuecheck && make test && make package`. Expected: pass.
- [ ] **Step 3:** Ask the user to check in game and report: lobby card on join (and How to play opens the first time only); Colour picker sets and repaints in prep; Leaderboard and Host panel buttons open/close the apps; prep shows role, runner and rule line; countdown, GO, chase line, catch bar, notices and result look right on a bright road; the HUD can't be removed (it comes back); clicks pass through everywhere except the HUD's own buttons. Fix what they report.
- [ ] **Step 4:** Commit `feat: HUD lobby card, colour picker and How to play`.

### Task 15: Host panel rewrite (user checkpoint)

**Files:**
- Rewrite: `client/ui/modules/apps/CopsAndRobbersPanel/app.vue`
- Create: `CopsAndRobbersPanel/PanelRound.vue`, `PanelCar.vue`, `PanelMap.vue`, `PanelSettings.vue`, `settings.js`

**Interfaces:**
- Consumes: `CnRPanel` (Tasks 7, 12), `CnRPanelReply`, `CnRConfigs`, `CnRStations` (Task 12); sends through `copsAndRobbers.panel(...)`, `copsAndRobbers.newBuild(...)`, `copsAndRobbers.configs(...)` as today, plus `{action = "station", op}`, `{action = "stations"}` (on Map tab open and after add/remove) and the `next` command.
- `app.vue`: `CnrRoot` + `CnrCard` "Host panel", `sub` = `v<version>`, closable (→ `copsAndRobbers.ui({action="toggleApp", name="panel"})`); `BngTabs` Round / Car / Map / Settings; folds into the one-line bar (red dot, `Chase m:ss`, `<runner> running`, End chase, Cancel, ▾) on entering `countdown|headstart|running` and opens again on `idle`, as today.
- `PanelRound` per spec §3: player rows as the runner picker (`next` preselected, `last` marked, "Random runner" row) → main button `Start round with <name>` (`start =<name>` / `start next` / `start random`); Practice as runner / as cop; Automatic rounds switch with "next one <delay> s after a round"; prep: rows with role chips and state (`loading`, `ready`, `changing: <change>`, `missing <n> parts` in `--cnr-warn`), GO with `goBlocked` underneath, New car (random mode), Cancel round; after a round: `lastResult` line, `autoNext` line with Start now (`next`) and Stop automatic rounds (`auto off`); Cancel during the chase needs a second click within 3 s.
- Every tab shows the last `CnRPanelReply` as a small status line at the bottom of the card (green for saves, yellow for refusals, plain otherwise), as today's reply line.
- `PanelCar`: Random car / Evolving build switch (two `BngButton`s acting as a segmented control), build summary (`build.name`, step, `lastChange`), New build Choose a car… (searchable `BngDropdown`) + Random (second click when a build exists), Reset build (second click), Include mod cars, excluded cars (names, editable list field); locked during a round with the reason.
- `PanelMap`: "<map name> · <count> gas stations", Add station here (main), Remove nearest (disabled with `No station within 50 m to remove` unless `canRemove`), nearest three with distances.
- `PanelSettings` + `settings.js`: groups as today plus `common: true` on Head start, Time limit, Hold time, Catch distance (`catchRadiusMeters`), Reset wait, Crash penalty, shown first; the rest under a collapsed "More settings (<n>)"; one-line explanation per setting (builder writes them, plain and short); changed-from-default value in `--cnr-me` with a small per-setting reset; green "Saved: …" line, yellow refusals; Reset to default (two clicks) and Reload config.json stay; "Stop the round first" lock as today; unknown keys under "Other".

- [ ] **Step 1:** Write the components to the Interfaces and the approved mockup `host-panel.html`.
- [ ] **Step 2:** `make vuecheck && make test && make package`. Expected: pass.
- [ ] **Step 3:** Ask the user to run a round and a practice round from the panel and check every tab (start with a picked runner, prep states, GO reason in evolving mode, fold bar during the chase, Start now, settings save/reset, add/remove a station). Fix what they report.
- [ ] **Step 4:** Commit `feat: host panel shows only what you can do now`.

### Task 16: Leaderboard rewrite (user checkpoint)

**Files:**
- Rewrite: `client/ui/modules/apps/CopsAndRobbersLeaderboard/app.vue`
- Create: `CopsAndRobbersLeaderboard/BoardRunners.vue`, `BoardCops.vue`, `BoardPlayers.vue`, `BoardRounds.vue`

**Interfaces:**
- Consumes: `CnRBoard` (Tasks 8, 12), `CnRHud`'s `driving` flag (Task 11); sends `copsAndRobbers.board({action = "open"|"close"|"filter"|"more", ...})`.
- `app.vue`: `CnrRoot` + `CnrCard` "Leaderboard", closable (→ `toggleApp board`); `BngTabs` Runners / Cops / Players / Rounds; a filter row under the tabs (map with `mapName(...)`, car mode); renders nothing while `driving` is true.
- Rows per spec §4 in the multiplayer-scoreboard style: rank badges 1–3 gold/silver/bronze gradients, others muted; `me` rows outlined `--cnr-me`; `mine` pinned under a "· · ·" gap; Cops: catches, fastest, assists as sub-line; Players: table → detail tiles (runs, best, average, escapes, catches, assists, hidden %, lost the cops, "–" when nil) and the player's last 5 rounds from `rounds`; Rounds: grouped Today / Yesterday / date (from `endedAt`), icon per end (`carChase01` caught, `flag` escaped, `abandon` ended/left), first warn event as a yellow flag line, "Show more" → `more`; detail: title, date · map · car (and build step), timeline (Cops released at 0:00, events, the end) with dots coloured by kind (warn kinds yellow, `lost` green, end red), cops with `in sight n%` and catch marker; runs without a timeline show only the result.

- [ ] **Step 1:** Write the components to the Interfaces and the approved mockup `leaderboard.html`.
- [ ] **Step 2:** `make vuecheck && make test && make package`. Expected: pass.
- [ ] **Step 3:** Ask the user to open it from the HUD, check each tab and filter, a round's timeline after playing one, that it hides from GO to the end of the round, and closes with ✕. Fix what they report.
- [ ] **Step 4:** Commit `feat: leaderboard in the scoreboard style with a Rounds tab`.

### Task 17: Preview images, docs and version 2.1.0

**Files:**
- Modify: `tools/previews/hud.svg`, `panel.svg`, `board.svg`; `client/ui/modules/apps/*/app.png`; `README.md`, `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, `TODO.md`; `server/CopsAndRobbers/main.lua` (`VERSION`), `client/lua/ge/extensions/copsAndRobbers.lua` (`CLIENT_VERSION`), `tests/test_main.lua` (version assertions)

- [ ] **Step 1:** Redraw the three SVGs from the final apps (HUD: full-screen mid-chase over a road; panel: Round tab in prep; board: Runners tab) and export: `rsvg-convert -w 1000 -h 560 tools/previews/<name>.svg -o client/ui/modules/apps/<App>/app.png`. Expected: three 1000×560 PNGs (`file` confirms).
- [ ] **Step 2:** Docs: README (apps instead of commands, no chat), FEATURES.md (HUD, lobby, colour, How to play, panel tabs, leaderboard Rounds, quiet; remove the command table), DEPENDENCIES.md (components, tokens, fonts and icon names used; full-screen click-through; opening apps; `core_levels.getLevelTitle`; `make vuecheck`); TODO.md: remove the UI/UX item.
- [ ] **Step 3:** Bump to `2.1.0` in both version constants and the tests; `make test && make vuecheck`. Expected: pass.
- [ ] **Step 4:** Commit `feat: 2.1.0 - one native look, everything on screen`.
