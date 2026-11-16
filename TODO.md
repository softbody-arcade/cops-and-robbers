# TODO

## Ideas
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars). Hard mode also raises the night and bad weather chances of night and weather rounds
- [ ] Police helicopter instead of the 30 s last-seen ping (`lastSeenIntervalSeconds`): a helicopter tracks the runner and gives the cops the runner's position, in place of the fixed ping every 30 s. Ties in with hard mode, which drops the 30 s pings
- [ ] Spike strips for cops: a few per round on a button (keybind), placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Dynamic roadblocks: parked cop cars that block part of the road ahead of the runner. Same goal as spike strips (stop the runner ahead), so plan them together
- [ ] Infection mode: game starts with 1 cop and caught runners become cops
- [ ] Leaderboard filter by conditions (All / Normal / Night / Bad weather), next to the car-mode filter, so storm records don't compete with clear-day runs unless wanted. Runs already record their conditions (night and weather rounds)
- [ ] Player settings card on the HUD: one place for a player's own options, such as their car colour (today's colour card) and a headlight toggle (lights on automatically at night)
- [ ] Cop sight that follows visibility: the sight range is worked out from what the game knows (fog thickness, how dark it is, street lights near the runner, whether the runner's lights are on, rain). Comes after night and weather rounds

## Issues
- [ ] The version number conflicts between branches built side by side: it sits in 4 places (`server/CopsAndRobbers/main.lua`, `client/lua/ge/extensions/copsAndRobbers.lua`, `client/mod_info/CopsAndRobbers/info.json`, the `docs/FEATURES.md` heading) and 12 test lines (`tests/test_client.lua`, `tests/test_main.lua`), so two branches that each bump it conflict on all 16 lines (2.3.1 against 2.4.0). Fix: bump only on main, as its own commit when a branch merges, never on a feature branch; tests read the version from the code instead of hardcoding it (and check client and server agree); optionally a `make version V=x.y.z` target that rewrites the 4 places

## BeamNG.Earth
- [ ] Traffic (after traffic on normal maps has been played and tuned). BeamNG.Earth's navgraph manages any running traffic itself: it moves cars that stand still 45 s (our traffic is held still through prep), hides all traffic after a teleport until the new road graph arrives (round setup moves cops far), the road graph arrives after the round car is placed (a moved cop's traffic finds no roads), and a region change sets traffic up again with the player's own amount and police choice. Traffic positions would also have to travel as latitude/longitude for the crash fault rule
- [ ] Night and weather rounds: go through Earth's server hooks (`beamngEarth_sky.setServerClock`, `beamngEarth_weather.setPreset`), not `core_environment`, which flips players to Manual and saves it in their Earth settings. Earth ignores the date, has six weather presets that take about 60 s to fade in, and leaves players on Manual alone. Research notes in `docs/superpowers/specs/2026-11-16-night-weather-design.md`
