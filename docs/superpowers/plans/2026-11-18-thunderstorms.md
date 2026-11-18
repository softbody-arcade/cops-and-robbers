# Thunderstorms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a warm-weather thunderstorm with shared lightning, distance-delayed thunder and a local switch for flashes, without putting lightning in the existing gale.

**Architecture:** The server chooses the weather, dates and changes; only the existing sky payload carries the strike seed. A pure GE module reconstructs candidates on the GO clock. A separate scene module anchors each accepted strike once, then renders and plays it according to the local camera, cover and preference.

**Tech Stack:** BeamMP Lua 5.3 server, BeamNG.drive GE LuaJIT, Vue 3, Bash, FFmpeg/libvorbis and ffprobe (asset preparation only).

**Spec:** [Thunder and lightning design](../specs/2026-11-18-thunder-and-lightning-design.md)

## Global Constraints

- Work on `thunder`. Follow the repository rules for the shared ledger. Each task below defines one reviewable change.
- No new events or strike messages. No mod weather on BeamNG.Earth. No strikes before host GO, without `lightningSeed`, or outside a thunderstorm or its blend. Ordinary storm remains a spring/autumn gale.
- Atmosphere only: no sightings, catch, damage, AI, helicopter tracking or scoring inputs from a strike. Ground the helicopter by **weather**. Do not touch the player's graphics, exposure, master volume or other game settings.
- Thunder continues with flashes off or under cover. Weather affects driving gates grip and vehicle wind, not lightning. No scene light between flashes, no bolt draw between pulses.

## Review Focus

1. Same seed, different frame sizes, late join or same-sky reapply: the future strike stream is identical, without replaying old strikes (Tasks 6 and 8).
2. A stay followed by a real change: no phantom transition, notice or early forecast, but the next real forecast still opens (Task 3).
3. Rain fades out under a bridge: cover still suppresses flashes and bolts, without a second sampler or silencing thunder (Task 7).
4. A spectator is far from the runner, or the runner is not loaded: use the right origin and listener distance; moving afterwards cannot retime the sound (Task 7).
5. End, leave or unload during a flash with thunder both pending and playing: nothing survives or plays in the next round (Tasks 7 and 8).

## File Map

Paths below are worktree-relative. `S/` = `server/CopsAndRobbers/cnr/`, `C/` = `client/lua/ge/extensions/copsAndRobbers/`, `UI/` = `client/ui/modules/apps/`; **extension** = `client/lua/ge/extensions/copsAndRobbers.lua`.

| Responsibility | Files |
|---|---|
| Rebuildable sound bank | New `tools/thunder/cut.sh`, ten `client/art/sound/cnr/thunder_*.ogg`, new `C/thunderClips.lua` |
| Eligibility, climate, weighted changes, payload | `S/config.lua`, `S/climate.lua`, `S/helicopter.lua`, `S/weather.lua`, `S/sky.lua` |
| Weather presentation, forecast, wind and grip | `C/sky.lua`, `C/skyChanges.lua`, `C/wind.lua`, `C/surfaces.lua`, `UI/CopsAndRobbersPanel/settings.js` |
| Strike math, scene and cover | New `C/strikes.lua`, `C/lightning.lua`; adapt `C/rain.lua` using existing `C/shelter.lua` |
| Lifecycle, local preferences, HUD | Extension, `C/playerSettings.lua`, `C/hud.lua`, `UI/CopsAndRobbersHud/HudSettings.vue` |
| User and maintenance docs | `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, `README.md`, `UI/CopsAndRobbersHowToPlay/HowToPlay.vue` |

Tests below use `tests/run.lua` (`test`, `assertEq`, `assertNear`); new `tests/test_*.lua` are auto-discovered. In each Lua task run the listed files with `lua tests/run.lua <files>` first red, then green (`N passed, 0 failed`); run `make test` before the task gate. No game or Downloads dependency in the normal suite.

### Task 1: Cut the ten final clips

**Files:** Sound bank in File Map; new `tests/test_thunder_clips.lua`.

**Interface:** `require("copsAndRobbers/thunderClips") -> {close,medium,far}`, each an ordered array of `{file="/art/sound/cnr/<name>.ogg", seconds=number}`. Durations are encoded file durations, not guessed emitter lifetimes.

- [ ] Write `thunder bank lists the shipped Oggs`: assert group sizes 2/1/7, ordered filenames, positive seconds within 0.02 s of the following targets and `io.open("client"..clip.file,"rb"):read(4) == "OggS"` (close handles). Run this file: missing bank/assets must fail.
- [ ] Base `cut.sh` on the existing preview script at `~/.claude/jobs/a1c056a9/tmp/thunder/cut.sh`. Read its exact bajko WAV, mikala_oidua WAV and TRP MP3 basenames in `~/Downloads`; resolve the output against the script's repo, not the caller's directory. Keep the stereo-to-mono mix, fades, 48 kHz resample, two-pass peak normalization to -1 dBFS before Vorbis q5. Omit the csengeri recording. Keep intermediates out of the sound bank.

| Final basename (all start with `thunder_`) | Source and interval, seconds | Fade in/out | Target seconds |
|---|---|---|---|
| close_1 | bajko 0-15 | 0.01/3 | 15 |
| close_2 | same faded PCM, play at 0.92 speed (`asetrate=44160,aresample=48000` on 48 kHz audio), normalize separately | inherited | 16.304 |
| medium_1 | mikala_oidua 0-18.4 | 0.05/2 | 18.4 |
| far_1 through far_7, in order | TRP 2-8, 44.5-57, 59.7-65, 69.5-74, 76.7-90, 125.7-135.5, 146.7-161 | 0.3/1.5 each | 6, 12.5, 5.3, 4.5, 13.3, 9.8, 14.3 |

- [ ] Run `bash -n tools/thunder/cut.sh`, then `bash tools/thunder/cut.sh`. For each output run `ffprobe -v error -show_entries stream=codec_name,channels,sample_rate,duration -of default=nw=1 FILE`: expect vorbis, 1, 48000 and the target duration within 0.02 s. Enter the measured seconds beside each path in the bank.
- [ ] Rerun the clip test and suite. Gate: script, ten final recordings and duration table only, plus their test; no originals, previews or changes to the rotor.

### Task 2: Register the weather on the server

**Files:** `S/{config,sky,weather,climate,helicopter}.lua`; `tests/test_{config,sky,climate,weather,helicopter,main}.lua`.

**Interface:** Existing `sky.pick/date/record`, `climate.offset/range`, `weather.build/groundedAt`, `helicopter.new/update`; new key `"thunderstorm"`. Preserve old keys and tie order.

- [ ] Extend the choice, climate, random date and grounding tests: `assertEq((config.merge({weather="thunderstorm"})).weather,"thunderstorm")`; May 1 through Sep 30 are exactly 153 unique dates; random bad index 5 selects it, manual selection ignores percentage. July range is 22/25. Rank 4 beats snow, ties storm with first worst retained. Grounded at entry and until exit plus 60 s, including a fixed start. Update the month map in `test_main.lua`'s New sky test.
- [ ] In `test_weather.lua` extend `WEATHERS`, `conditions`, `allowed`, month fixtures and seed indexing (use `#WEATHERS`, not 6 for weather). Test hot eligibility on both sides of 20, based on the **higher surrounding point**, not instantaneous T. With `noSlots` use a winter thunderstorm cooling from a fitted state through 1 C: first cross to rain, then snow after 60 s if still cold. Extend the independent no-missed-crossing fit oracle. Run the six files; new choices/schedule expectations fail.
- [ ] Append to `sky.BAD`'s ordered list, set `WINDOWS.thunderstorm={5,6,7,8,9}`, `RANK.thunderstorm=4`, climate `OFFSET={2,-6}` for this key, allow in config and both helicopter grounding maps. In `NEXT` add hot edges from cloudy and rain and exits to rain/cloudy only; compute `hot=high>=20` alongside `warm=high>=15` in `slotAt/options`. Mark the cloudy edge's third tuple field 0.5 for Task 3. In `CROSS` map to rain; add to `CAN_STOP` and the rain/storm cases of `fits/stops`. Keep the original gale window and offset.
- [ ] Rerun the six files and suite. Gate: manual and random starting conditions and eligible neighbors work before changing the slot picker.

### Task 3: Weight planned changes and allow silence

**Files:** `S/weather.lua`, `S/sky.lua`, `C/skyChanges.lua` (forecast reader belongs with its wire change); `tests/test_weather.lua`, `tests/test_sky_changes.lua`.

**Interface:** `weather.build(s,cfg,random?)` still emits **only real changes**. A real change immediately following one or more stays may carry optional `afterStay=true`. Same array passes through `sky.payload`; old rows without the flag retain today's early and prep forecasts.

| From | Eligible options in draw order; stay = current |
|---|---|
| clear | stay, cloudy, fog if foggy |
| cloudy | stay, clear, rain if wet, snow if cold, fog if foggy, thunderstorm **0.5** if hot |
| rain | stay, cloudy, storm if warm, snow if cold, thunderstorm if hot |
| storm | stay, rain |
| snow | stay, cloudy, rain if wet |
| fog | stay, cloudy, clear |
| thunderstorm | stay, rain, cloudy |

- [ ] Test `planned picks roll group then weight` with scripted draws in `test_weather.lua`: hot non-foggy cloudy with wet T, bad roll 0.24999 at 25%, within-group draw just below 2/3 gives rain, at 2/3 gives thunderstorm (compare cumulative weights without division-boundary rounding); group draw 0.25 gives calm. Hot rain's bad choices stay/storm/thunderstorm are equal. At 0/100% choose only the available requested group; hot clear at 100% and storm at 0% still pick from the sole available group. No direct gale/thunderstorm edge. Forced fog lift/temperature crosses ignore stay and percentage.
- [ ] Test `stay consumes a slot, not a change`: July noon cloudy, dayLength off, 3/3-minute slots, 400 s limit, chance 25. Use existing `script({0.5,0,0.9,0,0,0.9,0.75,0.5,0},0)` for shift, interval, calm/stay, interval, calm/clear, forecast, interval. Assert `#r.changes==1`, row to clear at release+360, afterStay=true, forecastFrom=release+300. Repeated calm/stay yields zero rows. In client `payload` fixture assert `prepForecast(p)==nil`, `forecast(p,forecastFrom-0.01,true)==nil`, then normal “any minute” at the boundary; unflagged rows still show existing early forecasts. The omitted slot cannot advance `skyChanges.at`'s change index.
- [ ] Replace the current **maximum gap between emitted changes**, mandatory nonempty/last-near-horizon and 179-emitted assumptions: test fixed-slot alignment, minimum gaps for non-crosses, and a scripted no-stay run reaching slot 179 (one-minute slots, frozen day), none at/after release+10800. Keep independent allowed-neighbor, temperature, forecast-window, horizon and seeded fingerprint properties. Run both files; unconditional changes/early forecasts fail.
- [ ] Implement local `options(from,T,foggy,warm,hot)` returning ordered eligible tuples including stay; `pick(random,list,badPercent)` partitions by membership in the bad list (move ordered BAD to `weather.BAD`, use in `sky.pickWeather`; no circular require). Weights default 1. If both groups exist, use `random()*100 < badPercent` (default config 25); otherwise skip group draw. Select using cumulative weights in stable array order, with last-item fallback for a test RNG returning 1. Keep a separate uniform draw for forced fog `LIFT`.
- [ ] In the local `slotAt(x)` inside `schedule`, on stay only remember its timestamp and set `slot=x+interval()`; do not call `add`, draw a forecast, change `cur/running/fitted`, or postpone a forced cross. On next real `add` set the flag and consume the timestamp. On short slots test and enforce `forecastFrom=max(lastStayAt,x-120*draw)` for this row only. In `skyChanges.forecast` hide a flagged row until its window opens; in `prepForecast` return nil for a flagged first row. Leave ordinary predictions unchanged.
- [ ] Rerun both files and suite. Gate: real-change-only payload plus its matching reader; no separate network message, no target percentage asserted for unconditional long-run occupancy.

### Task 4: Carry one independent strike seed

**Files:** `S/sky.lua`, `tests/test_sky.lua`, `tests/test_main.lua`.

**Interface:** Optional integer `p.lightningSeed` in `sky.payload(s,cfg,clockSeconds)`, same value for all recipients of this sky.

- [ ] Test `strike seed belongs to the picked sky`: use distinguishable scripted integer draws for wind/weather/lightning, assert a fresh `random(1,2147483646)` on non-Earth pick; payload at nil and 123.5 seconds carries the same seed; `sky.record(...).lightningSeed==nil`. Earth takes zero draws and sends no payload. Extend the setup/New sky wire test to check the new field on both. Run both files: missing seed fails.
- [ ] Draw once in `sky.pick` **after** existing weatherSeed draw, even on a clear start (could change later); copy next to windSeed in `payload`. No seed generation on join, in payload or in a leaderboard record.
- [ ] Rerun both files and suite. Gate: no change to earlier RNG draws or the weatherSeed-derived plan.

### Task 5: Present the new weather everywhere

**Files:** `C/{sky,skyChanges,wind,surfaces}.lua`, `UI/CopsAndRobbersPanel/settings.js`, `UI/CopsAndRobbersHowToPlay/HowToPlay.vue`; `tests/test_{sky_client,sky_changes,wind,surfaces}.lua`.

**Interface:** Existing sky/traffic/board labels, wind vectors, four canonical grip weights, forecast and notice strings. “Thunderstorm” is the label; “a thunderstorm” is the noun.

- [ ] Test `thunderstorm has gale rain but distinct gusts`: compare sky presets and precipitation, `sky.isBadWeather`, `sky.label({weather="thunderstorm"})=="Thunderstorm"`; check configured wind ranges below and seeded peak/angle bounds. In surface tests use existing fake ground models: `apply("thunderstorm")` gives DIRT depth 0.15 then restores. Rain to thunderstorm at midpoint yields grip rain=0.5/storm=0.5; drying still uses the existing 180 s. Test ground/return forecast hints and entry/exit notices. Run the four files: missing key or incorrect fallback text fails.
- [ ] Alias `sky.WEATHER.thunderstorm` to storm (cloudCover 3.0, fogDensity 8, windSpeed 1.5, rain_medium 7000 drops, size 1.3, speeds 0.6/0.8, volume 2.0); include in `BAD_WEATHER`. Set `wind.WEATHER.thunderstorm={steady=10,peak=24,every={4,12},length={1,4},turn=45}`. In `skyChanges` mark WET and map to storm in `kindOf`; canonicalize likewise in `surfaces.apply` before RULES lookup. No fifth grip weight or duplicate ground model writes.
- [ ] Add GROUNDED, CLEARING_FROM and WORDS entries; `notice` into thunderstorm is “Weather: a thunderstorm is coming”; to rain “Weather: the thunderstorm is easing”; to cloudy retains “Weather: clearing up”. Forecast uses “a thunderstorm” and “clearing up”. Board rows consume `row.skyLabel=sky.label(row.sky)`, as does HUD sky text: no Vue weather map to fork.
- [ ] Add panel option and update help for starting weather, driving, grounding, changes and interval rows (slots can pass without a change). Show Bad weather chance for `v("weather")==="random" || v("weatherChanges")===true`; describe starting random weather and planned rolls when both groups are possible. Update **both** grounding paragraphs in How to Play. Leave its flash/comfort sentence for Task 9.
- [ ] Rerun the four files, suite and `make vuecheck` (expect Vue and JS files ok). Verify panel row visible for random/off and fixed/on, hidden for fixed/off; `rg -ni storm client server` should leave only intentional gale-specific or canonical grip branches. Gate: weather presentation works without the scene effect.

### Task 6: Reconstruct strikes without the game

**Files:** New `C/strikes.lua`, `tests/test_strikes.lua`; consumes `C/skyChanges.lua` and Task 1's bank.

**Interface:** `strikes.new(seed) -> cursor`; `strikes.between(cursor,p,lo,hi) -> Strike[]` over **(lo,hi]** in round seconds; `strikes.weight(p,t) -> 0..1`. Strike = `{at,range,bearing,pulses,soundRoll,shapeSeed}`, pulses = ordered `{start,length,level}` offsets. `strikes.bolt(shapeSeed) -> {main,branches}` (local xyz polylines, foot at origin); `strikes.sound(soundRoll,d) -> clip,delay,volume`; `strikes.strength(d) -> number`. No vec3, engine, wall clock, global RNG or listener inputs to the candidate stream.

- [ ] Test `same future after a late join`: serialize all scalar fields/pulses and sampled bolt coordinates, not table identities. Compare one continuous run vs short frames, an independent cursor first queried at t=613.4 and same-seed reconstructed cursor on the identical suffix through 1200; require nonempty matches across window edges, different seed differs. Exact split on a strike emits it once. Include transitions with rejected candidates; changing camera/asking for sound or bolt cannot consume schedule draws. Missing seed, pre-GO time, gale/rain/fog/snow/clear produce no strikes.
- [ ] Test `thin at the candidate time`: with change at 100, weight at 100/115/130/160 is 0/0.15625/0.5/1; reverse on exit, full thunderstorm is 1 even with identical from/to. Compare partial-weight events against the full-storm stream for the same seed and exact times, with both kept and rejected candidates across several seeds. For full storm seed 1 assert first time near `-25*math.log(1-16807/2147483647)` (1e-10). Across 250,000 s at fixed seed 4242 count events incrementally; check mean gap within 2 s of 25 and band shares within 2 percentage points of 10/35/55; distances and bearings always within range.
- [ ] Test `pulse and branch geometry`: 2-4 nonoverlapping positive pulses, first starts 0 at full level, last ends by 0.5; 65 main points from z=900 to 0, 1-3 attached descending/outward branches of 17 points, endpoints 150-350 m from branch roots. Test audio thresholds at 999.9/1000/3000/3000.1, first/last pick of every group, delays at 343 and 3430 m (1/10 s), volume at 0/500/3250/6000/7000 (1/1/0.675/0.35/0.35); strength at 0/300/3000/6000 (1e10/1e10/1e8/2.5e7). Run new test file: module missing.
- [ ] Use Park-Miller `x=x*16807%2147483647`, normalized by 2147483647, seed 1..2147483646. From time zero draw exponential increments `-25*log(1-u)`, then a keep roll and independent per-candidate detail seed, **even for skipped candidates**. Cache candidate records for one 60 s window plus the next boundary candidate/RNG state; discard elapsed windows. A new cursor fast-forwards the same stream without retaining history; on backward queries replay from seed. Cross arbitrarily many windows in order; don't restart exponential waits at boundaries. Keep if roll < weight at candidate time using `skyChanges.at/smooth` and interpolated thunderstorm indicators.
- [ ] From detail RNG draw band (<0.10, <0.45, else), uniform range within 300-1000/1000-3000/3000-6000 m, uniform bearing [0,360), then sound roll, shape seed and pulse pattern. Use 2-4 equally likely pulses, first length 0.05-0.07 s, later dark gaps 0.04-0.07 s and lengths 0.04-0.07 s, later levels 0.5-1. Subdivide main 6 times (lateral midpoint displacement, roughness 0.35); branch from seeded interior vertices, 1-3 seeded downward/outward directions, 4 levels at 0.4. Project positions only in Task 7. Band for audio is chosen by **listener** d (<1000 close, <=3000 medium, otherwise far); index via soundRoll, delay d/343, linear clamped gain 1 to 0.35 over 500-6000 m. Strength = `1e10*(300/max(300,d))^2`.
- [ ] Rerun new test file and suite. Gate: pure shared schedule and shapes, independently seekable, with bounded retained history.

### Task 7: Render pulses and play arriving thunder

**Files:** New `C/lightning.lua`, `tests/test_lightning.lua`; modify `C/rain.lua`, `C/sky.lua`, extension, `tests/env_stubs.lua`, `tests/test_{rain,sky_client,client}.lua`. Patterns: `heli.createLight` (local), `heliVan.tick` and lazy debugDraw, `heliSound` emitter registration.

**Interface:** `lightning.new() -> state`; `tick(state,p,lo,hi,runnerObj,flashes,covered)` consumes Task 6's interval, samples GE camera; `hide(state)` cancels visuals only; `clear(state)` also deletes audio, pending arrivals and cursor. `rain.covered() -> boolean`; one roof sampler driven by `rain.update(dt,needRoof)`, not by each consumer.

- [ ] In scene tests use `fakeEnvironment()`, record fields, positions, `postApply`, playback and deletions; spy on the eight-argument `utils/debugDraw.LineInstance_MinArg` like `test_heli_van.lua`. Inject known strikes by temporarily replacing `strikes.between` and restoring it. Test `capture landing once`: north bearing 0 from runner, camera elsewhere, one downward ray per strike; hit distance 2400 gives z=100; nil/full-range miss uses runner height. Nil runner uses camera; move camera after strike, assert unchanged deadline, band and volume. At 4000 m draw, at 4000.01 don't; distant strike still flashes. Missing camera skips local effects without corrupting future events.
- [ ] Test `only pulses draw`: inspect PointLight fields below, two pulses and a dark gap, delete after last pulse; count segment calls on each visible pulse, zero in gap, no rebuilding shape between frames. Cover or `hide` mid-flash deletes light and stops drawing immediately; queued thunder still plays. Test `four due thunders`: play three, drop fourth at its due time (no eviction/deferred replay); reap at actual play time + clip.seconds before admitting another. Assert non-looping/non-3D and volume; clear twice mid-flash with playing and pending thunder, then tick a new seed: no stale object, draw or sound.
- [ ] Test `one roof sampler with no rain object` in rain/sky tests: while seeded thunderstorm weight is positive and rain inactive at a fade edge, two covered samples 0.25 s apart suppress light/bolt; with rain active, no duplicate rays and rain volume still halves. Confirm normal opening debounce, new-round reset, and no polling in dry inactive weather. In `test_client.lua` use `bootClient` and a spy on the loaded `lightning.clear` for round result, leave, end mission and extension unload. Run these test files red.
- [ ] Leave cover in rain; move sampling guard from `cur and updateCover(dt)` to `cur or needRoof`, expose covered state and do not reset it on every inactive `target`. Retain `resetRoof` at new round and reset on clear/idle-to-new-use so stale cover never leaks. `sky.update` drives this **once** per frame for rain.active() or started seeded thunderstorm/blend (use Task 6 weight at the advanced frame clock); keep the 0.25 s cadence and `shelter.step` debounce. On first activation under a roof, prime the shared reading before allowing a flash; do not expose a default open state as a confirmed sky view.
- [ ] In `tick` consume strikes once, even when covered or flashes off. Reference = runnerObj:getPosition() or camera. Offset x/y by range*sin/cos(bearing radians), ground ray `castRayStatic(vec3(x,y,2500),vec3(0,0,-1),5000)`; z = 2500-hit for valid hit in [0,5000), else reference z. Freeze landing and 3D camera distance for sound, strength and bolt cutoff. Queue arrival at strike.at+delay. Drain due arrivals in deadline order (strike order on ties), reuse three named slots `cnr_thunder_1..3`; Sim.upcast, fileName, is3D="0", isLooping="0", unsaved, register, verify, add to MissionGroup, set volume then play. Delete by clip duration; let tails finish after the sky clears.
- [ ] Test the idle path with a fixed gale and no active effects: zero candidate queries, camera reads, ground rays, draw calls and scene lookups by lightning. Cache thunderstorm intervals when the payload changes (entry through end of exit blend); only query candidates if the **frame interval** intersects one, not just if the ending weather is thunderstorm. Outside those intervals still service pending deadlines/active effects. Read the camera on a strike or visible pulse, not to poll for strikes.
- [ ] For visible pulses create unsaved `PointLight` named `cnr_lightning_flash`, verified registration + MissionGroup; follow camera+300 m Z, radius 1500, color "0.75 0.82 1 1", castShadows="0". Write **both** brightness and intensity = strength*level, isEnabled for on/off and call postApply(); disable in gaps, delete after last pulse. Overlapping strikes share the light (strongest active pulse), keep distinct bolts/audio. Build bolt once per visible strike <=4000 m; lazy-require LineInstance_MinArg(x1,y1,z1,x2,y2,z2,width,packedColor), color(235,240,255,alpha), main 4 px, branches 2 px at reduced alpha on later pulses. No draw or per-frame geometry generation outside pulses. Clean partially registered objects on API failures; a visual failure must not stop audio or the chase.
- [ ] Give extension one lightning state next to heliSound state and clear it in `endRound(leaving)` beside heliSound.clear. This covers normal end, `leaveServer`, `onBeamMPServerLeave`, `onClientEndMission` (sky.drop then leave) and `onExtensionUnloaded`. Same-seed reapply must not clear; seed replacement clears before accepting new effects. Wire regular ticking only in Task 8.
- [ ] Rerun new scene test, rain/sky/client files and suite. Gate: scene behavior and cleanup independently tested; stub calls do not prove actual brightness or audible playback.

### Task 8: Wire the GO clock and comfort setting

**Files:** Extension, `C/{sky,playerSettings,hud}.lua`, `UI/CopsAndRobbersHud/HudSettings.vue`; `tests/test_{player_settings,hud,sky_client,client}.lua`.

**Interface:** `sky.lightningFrame() -> p,lo,hi,covered` for the most recent started `sky.update(dt)`, otherwise nil. Local boolean `lightning`, default true, carried via `hudfeed.settings(prefs)` into `hud.lua`'s settings payload.

- [ ] Test `lightning preference round trips`: missing/invalid/old settings -> true, false loads and persists, non-booleans and unchanged writes rejected. `env.M.ui({action="setting",key="lightning",value=false})` removes a live flash before another update, `env.written["settings/cnr_settings.json"].lightning==false`, `env.hud().settings.lightning==false`; audio arrives with rotor sound also disabled. Re-enabling affects future strikes, not an already cancelled flash.
- [ ] Test `GO frame matches joined clock` with `changing/started` in sky tests and `bootClient/chaseWith/spectate` in integration tests: no frame before countdown; GO from 0 with dt=0.1 yields (0,0.1]; join at 613.4 starts there, not 0. Reapply identical sky at running clock: compare future (at,shapeSeed) pairs to a continuous run, with pending sound played only once. Test new seed resets and no old-payload/Earth strikes. Check runner uses own vehicle, cop/spectator use the resolved runner (including AI); driving off does not disable the effect. Drive each Task 7 exit while effects exist; assert no light, emitter or delayed play afterwards. Run four files; missing setting/tick fails.
- [ ] Capture `lo=roundTime` before advancement in `sky.update`; expose interval after update only for started, seeded round; invalidate on forget/drop/restore/prep. Preserve `startClock(clockSeconds)` for joins and existing active-round time on `apply`. Start at **host GO** (cnr_countdown starts sky clock), not runner release, cop release, advancing time of day, or extension uptime.
- [ ] In extension `onUpdate` after sky.update and runnerObj resolution, pass frame to `lightning.tick` for active/spectating clients; explicitly select ownVehicle() for runner and existing runnerObj for cop/spectator, leaving nil for camera fallback. Don't put this inside the helicopter-enabled path. Handle absent/replaced frame by clearing old state once, not scanning the scene every idle frame.
- [ ] Add key/default in `playerSettings.lua`, `lightning=prefs.lightning~=false` in `hud.lua`'s settings, and adjacent BngSwitch row **after Helicopter model**, label “Lightning flashes”, description “Show flashes and bolts during thunderstorms. Thunder still plays.” Emit `setting` with key `lightning`. In extension `M.ui` accepted change to false calls `lightning.hide` immediately; retain generic persist, HUD push and preference loading.
- [ ] Rerun the four files, suite and `make vuecheck`. Gate: usable local preference and live round integration for all roles; no host option or persistent engine setting.

### Task 9: Document behavior and engine dependencies

**Files:** `docs/FEATURES.md`, `docs/DEPENDENCIES.md`, `README.md`, `UI/CopsAndRobbersHowToPlay/HowToPlay.vue`.

**Interface:** Describe the player-visible behavior and the maintainer's local test procedure, not additional code or version history.

- [ ] Audit existing weather, grounding, forecast, HUD settings and rotor-credit passages using `rg -ni 'storm|forecast|rotor|helicopter model' docs/{FEATURES,DEPENDENCIES}.md README.md client/ui/modules/apps/CopsAndRobbersHowToPlay/HowToPlay.vue`. Identify stale lists, slot timing guarantees and missing thunder credits.
- [ ] Update FEATURES for gale vs thunderstorm, start season/hot transitions, weighted group chance/stay and silent forecasts, GO, camera-relative delay, cover, visual toggle and no gameplay effects. In How to Play add one player-facing sentence explaining the flash switch leaves thunder audible; keep the grounding updates from Task 5.
- [ ] In DEPENDENCIES' GE section record the PointLight fields/intensity scale, debugDraw signature, one-shot SFXEmitter lifecycle and 3D fallback, why deprecated sky brightness and exposure-bias spikes weren't usable, and what to recheck after a game update. In both it and README credit the CC0 originals by title and author: [sfx_thunder blast.wav, bajko](https://freesound.org/people/bajko/sounds/399656/), [Distant Thunder Clap_Gentle.wav, mikala_oidua](https://freesound.org/people/mikala_oidua/sounds/347562/), [230405 Thunder DRY rolling distant low rumbles, roof, EM272s, Toronto 7am, TRP](https://freesound.org/people/TRP/sounds/717845/). Point maintainers to the regeneration script.
- [ ] Repeat the audit, `make test` and `make vuecheck`; expect consistent lists, all three links in both credits, zero failures. Gate: docs match shipped behavior; leave engine-dependent findings for the local check.

## In-game checks

Run on the owner's local server. Start with forced Thunderstorm at night; check light and sound first. Unit tests cannot certify either GE behavior.

1. Verify flash at camera+300 m: near strikes cap at 1e10, around 3 km is 1e8, far weaker. Test brightness and intensity separately locally to identify the effective field; ship both with isEnabled/postApply unless verified otherwise. Inspect all pulse gaps, 4/2 px branches, bolt cutoff at 4 km and ground alignment. No frame-rate drop between flashes.
2. Verify a non-3D one-shot plays once at the requested volume; compare close crack, medium clap and far rumble, about 3 s delay per km. **If non-3D is silent or ignores volume**, use the same one-shot emitter with is3D="1", 30 m from the camera toward the strike; verify perceived gain and cleanup again. Tune volume/widths by ear and eye, not by changing game settings.
3. Confirm fixed and random summer starts, hot cloudy/rain entries, easing/clearing, panel chance visibility, labels, forecast, notices, board and both help perspectives. Watch a stay with no notice/forecast, then the next real forecast. Ordinary gale has heavy rain and no strikes.
4. Compare two players including a late spectator: same future strikes, direction relative to runner, shape and timing; different camera distances can give different thunder. Rate about one per 25 s when full, thinning at the edges. No strikes in prep or on Earth.
5. Drive under a bridge/in a tunnel through a wet/dry edge. Neither flash nor bolt under cover; audio continues. Toggle Lightning flashes off mid-pulse, verify immediate suppression and persisted choice on rejoin.
6. End round, leave server, and unload mission with lightning active and thunder queued/playing. Inspect scene tree for no flash/emitters, no delayed sound afterwards, and normal weather/sound next round.
