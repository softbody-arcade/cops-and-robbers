# TODO

## Ideas
- [ ] Traffic on BeamNG.Earth (after traffic on normal maps has been played and tuned). BeamNG.Earth's navgraph manages any running traffic itself: it moves cars that stand still 45 s (our traffic is held still through prep), hides all traffic after a teleport until the new road graph arrives (round setup moves cops far), the road graph arrives after the round car is placed (a moved cop's traffic finds no roads), and a region change sets traffic up again with the player's own amount and police choice. Traffic positions would also have to travel as latitude/longitude for the crash fault rule
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars). Hard mode also raises the night and bad weather chances of night and weather rounds
- [ ] Spike strips for cops: a few per round on a button (keybind), placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Dynamic roadblocks: parked cop cars that block part of the road ahead of the runner. Same goal as spike strips (stop the runner ahead), so plan them together
- [ ] Infection mode: game starts with 1 cop and caught runners become cops
- [ ] Police helicopter instead of the 30 s last-seen ping (`lastSeenIntervalSeconds`): a helicopter tracks the runner and gives the cops the runner's position, in place of the fixed ping every 30 s. Ties in with hard mode, which drops the 30 s pings
- [ ] Leaderboard filter by conditions (All / Normal / Night / Bad weather), next to the car-mode filter, so storm records don't compete with clear-day runs unless wanted. Runs already record their conditions (night and weather rounds)
- [ ] Player settings card on the HUD: one place for a player's own options, such as their car colour (today's colour card) and a headlight toggle (lights on automatically at night)
- [ ] Cop sight that follows visibility: the sight range is worked out from what the game knows (fog thickness, how dark it is, street lights near the runner, whether the runner's lights are on, rain). Comes after night and weather rounds
- [ ] Night and weather rounds on beamng_earth: go through Earth's server hooks (`beamngEarth_sky.setServerClock`, `beamngEarth_weather.setPreset`), not `core_environment`, which flips players to Manual and saves it in their Earth settings. Earth ignores the date, has six weather presets that take about 60 s to fade in, and leaves players on Manual alone. Research notes in `docs/superpowers/specs/2026-11-16-night-weather-design.md`

## Issues
- [ ] Cop start spots are picked by straight-line distance from the runner (50-150 m), not by how far it is to drive there. A mountain road above the runner, the other side of a hairpin, or a road across a river or divided highway counts as close even when driving there takes much longer, and switchbacks make it worse. Pick spots by driving distance along the road network instead (the same goes for moving AI cops back near the runner)
