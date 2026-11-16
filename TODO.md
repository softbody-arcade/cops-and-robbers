# TODO

The shared ledger for every agent and worktree. Edit this file only on main (in the main checkout), so everyone reads the same state; from a worktree, read it with `git show main:TODO.md`. One exception: an issue found on a branch about that branch's own unmerged code goes under Issues in the branch's TODO.md and reaches main with the merge. Delete finished lines, never tick them.

## In progress
One entry per piece of work that has started: what it is, its branch (or "design" before there is one) and where it stands. Add it on main when the work starts (move it out of Ideas), move the Issues it folds in under it as sub-items (so no one else picks them up), keep it current, and delete it with its sub-items once the work is merged and checked.

- [ ] Sky polish: time and weather changes blend over up to 3 s (round start, New sky, round end), rain and storm drops tuned against the stock maps' rain (faster rain, heavier storm), and the game's rain sound during rain and storm. No thunder (the game has no lightning or thunder). Design: `docs/superpowers/specs/2026-11-16-sky-transitions-design.md`, being written; no branch yet

## Ideas
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars). Hard mode also raises the night and bad weather chances of night and weather rounds
- [ ] Police helicopter instead of the 30 s last-seen ping (`lastSeenIntervalSeconds`): a helicopter tracks the runner and gives the cops the runner's position, in place of the fixed ping every 30 s. Ties in with hard mode, which drops the 30 s pings
- [ ] Spike strips for cops: a few per round on a button (keybind), placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Dynamic roadblocks: parked cop cars that block part of the road ahead of the runner. Same goal as spike strips (stop the runner ahead), so plan them together
- [ ] Infection mode: game starts with 1 cop and caught runners become cops
- [ ] Leaderboard filter by conditions (All / Normal / Night / Bad weather), next to the car-mode filter, so storm records don't compete with clear-day runs unless wanted. Runs already record their conditions (night and weather rounds)
- [ ] Sit out rounds: a player's own switch to stay out of rounds (a break, AFK, watching) instead of being pulled into every round as a cop. Needs round decisions: where the sitting-out player's car goes, whether they can watch, how the runner pick and automatic next round skip them
- [ ] Runner preference: a player's own choice not to be picked as runner by Next (whoever has run least) and the automatic next round. The host can still pick them by name in the Round tab
- [ ] Thunder and lightning in storm rounds: the game has no lightning object in this version and no thunder sound, so it would be our own: a brief sky flash (the game's sky brightness) and a thunder sound a second or more later, timed from the round's weather seed so every player gets the same strikes. Needs a thunder recording with a free licence (CC0) shipped in the mod. Research notes in `docs/superpowers/specs/2026-11-16-sky-transitions-design.md`
- [ ] Cop sight that follows visibility: the sight range is worked out from what the game knows (fog thickness, how dark it is, street lights near the runner, whether the runner's lights are on, rain). Comes after night and weather rounds

## Issues
- [ ] Cop spots next to a narrow median: the runner can be matched to the other carriageway, so cops are placed for that side (`roads.lua` uses `findClosestRoad`, not the runner's heading)
- [ ] Cop spots on a road piece not connected to the rest: the straight-line fallback widens from 0 and ignores gates, so a cop can start right next to the runner or behind a gate (`roads.lua` `lineSpots`)
- [ ] Traffic late clean-up: traffic that finishes spawning more than 15 s after the round ends stays on the map, and AI traffic a player starts within those 15 s is deleted (`traffic.lua` `LATE_CLEANUP_SECONDS`). Check in game whether spawns ever finish that late
- [ ] Leaderboard Cops tab: cops with only assists get no row (`leaderboard.lua` `cops`). Showing them needs a sort and empty-state decision, since the tab ranks catches
- [ ] README says "Everything is clickable with the mouse cursor shown" without saying how a player shows the cursor. Check the game's control and say it
- [ ] Leaving the server removes every app the mod placed, also one the player removed and then added back themselves (`apps.lua` leave). Decide what counts as the mod's
- [ ] How to play forgets its size and position when reopened (`apps.lua` resets its placement). Decide whether to remember it
- [ ] Panel refusals ("Stop the round first", "Only the runner can apply the change", "Not available from the panel") show as plain info, not as warnings: the server's replies carry no tone for them (`main.lua` `reply`, Panel `app.vue`)
- [ ] Panel tabs forget their state when you switch tabs, because the game only renders the open tab: the Settings "more" fold, the Car tab's choice and the Map tab's stations. Decide which to keep in Panel `app.vue`
- [ ] Leaderboard: the gold badge gradient may be paler than the mockup (Leaderboard `app.vue`). Check in game
- [ ] App preview images (`tools/previews/*.svg`) are drawn approximations; replace them with in-game screenshots
- [ ] `useFit` (`fit.js`) only shrinks text and never grows it in a large app. Decide whether it should
- [ ] HUD styles repeated across components: `.title`, `.tone-*` and `.mono` (HudCenter, HudResult, HudChase) and the root container (Hud, Announcements and How to play `app.vue`). Move them into the shared kit; needs a visual check in game. (`.hud-btn` and `.swatch` are already shared: `.cnr-btn`, `.cnr-swatch` in `CnrRoot.vue`)
- [ ] Leaderboard `PLAYERS_TAB` / `ROUNDS_TAB` depend on the tab order (Leaderboard `app.vue`)
- [ ] The HUD's settings card clears the colour draft in its not-allowed watch (`app.vue`). That is safe only while no HUD push lands between the lobby and prep payloads; the spec asks for the draft to survive such a gap

## BeamNG.Earth
- [ ] Traffic (after traffic on normal maps has been played and tuned). BeamNG.Earth's navgraph manages any running traffic itself: it moves cars that stand still 45 s (our traffic is held still through prep), hides all traffic after a teleport until the new road graph arrives (round setup moves cops far), the road graph arrives after the round car is placed (a moved cop's traffic finds no roads), and a region change sets traffic up again with the player's own amount and police choice. Traffic positions would also have to travel as latitude/longitude for the crash fault rule
- [ ] Night and weather rounds: go through Earth's server hooks (`beamngEarth_sky.setServerClock`, `beamngEarth_weather.setPreset`), not `core_environment`, which flips players to Manual and saves it in their Earth settings. Earth ignores the date, has six weather presets that take about 60 s to fade in, and leaves players on Manual alone. Research notes in `docs/superpowers/specs/2026-11-16-night-weather-design.md`
