# TODO

The shared ledger for every agent and worktree. Edit this file only on main (in the main checkout), so everyone reads the same state; from a worktree, read it with `git show main:TODO.md`. One exception: an issue found on a branch about that branch's own unmerged code goes under Issues in the branch's TODO.md and reaches main with the merge. Delete finished lines, never tick them.

Priorities run from `!!!!` (highest) through `!!!` (high), `!!` (normal), and `!` (low). Put the marker after the checkbox and sort each section highest first. Batch notes inherit their parent’s priority.

## In progress
One entry per piece of work that has started: what it is, its branch (or "design" before there is one) and where it stands. Add it on main when the work starts (move it out of Ideas), move the Issues it folds in under it as sub-items (so no one else picks them up), keep it current, and delete it with its sub-items once the work is merged and checked.

- [ ] ! Directional cop sight and weather visibility (`feat/cop-visibility`). Implementing the [reviewed plan](docs/superpowers/plans/2026-11-18-cop-visibility.md), starting with the range calculation. [Design](docs/superpowers/specs/2026-11-18-cop-visibility-design.md) · [Diagram](docs/superpowers/specs/cop-visibility.svg)
  - Use the driving camera for human cops and car heading for Practice AI. At the default, the rear mirror gives 200 m straight behind the car in clear daylight. Looking directly back gives 400 m.
  - Scale spotting range with daylight, fog, precipitation, the runner’s headlights and nearby streetlights. In Practice, losing sight changes the shared spotting report while AI cops keep chasing.

## In-game checks
Use the [playtest criteria in AGENTS.md](AGENTS.md#verification-and-release) to decide what needs a player. Record deferred checks here with the action, expected observation and open question. Remove a check once verified and record failures under Issues.

Run these together on the locally staged 2.14.8 (`364b545`) or later.

- [ ] !!! Park a hitched truck and trailer at an angle beside a landmark. Sit out, watch an AI Practice round, then end it. Both should return at their original angles and the trailer should follow when you pull away.
- [ ] !!! With Play selected, bring the hitched rig and a spare car into driving Practice with traffic enabled. After placement, the rig and spare should be gone, AI and round traffic should remain, and you should keep the round car at the end.
- [ ] !!! Two players, night thunderstorm. From nearby viewpoints, compare a bolt’s landmark and flash timing. Have the cop disconnect and rejoin during the chase. They should see SPECTATING, and the runner should see no new car queued for them. Compare another bolt after the reconnect.
- [ ] !! Solo Practice as cop, West Coast USA. Select Clear weather, Sunset, Fast day length, helicopter arrival at release and refuel off. Hold the throttle during prep and the runner’s head start. The cop car should stay in its slot until release, then drive away without a second teleport.
- [ ] ! Continue the solo round through downtown and toward a hillside. The helicopter should clear roofs and slopes smoothly, then settle back to its usual height. Keep it airborne through dusk and watch the searchlight, glare and enabled beam brighten together over about one second.

- [ ] ! In the BeamNG layout editor, enlarge the HUD and move and resize How to play. Save, close and reopen How to play. It should return to the saved rectangle. During the solo round, check that the HUD and announcements stay readable, with no clipped text or invisible area swallowing clicks.

## Ideas
- [ ] !! Include the helicopter in the spectator camera cycle while it is airborne, so spectators can use Tab or Ctrl+Tab to switch between the helicopter and the round cars.
- [ ] !! Fog you can see at night (the user, 2026-11-18): fog works at night (it fades the distance into the dark, checked in game with screenshots) but shows no grey murk, because the game's fog shader (`shaders/common/postFx/fogP.hlsl`, `sceneLitFog.h.hlsl`) lights fog only by the sun and the sky's ambient light, both near zero at night, and not by headlights or street lamps. Tried in game, no visible effect: ScatterSky `nightFogColor` (the shader no longer uses a fog colour) and `nightColor` 0.05. Untried and costly: our own fog near the player (for example particles) that headlights light up, or a brighter moon (lights the whole night)
- [ ] !! Dependency check by fingerprint (the user, 2026-11-17): a manifest in the repo lists, per dependency in `docs/DEPENDENCIES.md`, the exact pieces the mod relies on, not whole files: a function in a game or BeamMP Lua file (for example `getCurveTemperatureC` in `core/environment.lua`, the spawn queue in `MPVehicleGE.lua`), a key in a JSON or jbeam file, the node ids and material we use in the Pigeon model, an SCSS variable. Each piece gets a fingerprint taken after stripping comments and spacing, so edits elsewhere in the file and cosmetic edits don't count. `make depcheck` reads the installed game (including inside its zips) and prints only the pieces that changed or disappeared, each with its `DEPENDENCIES.md` section and, from a local git-ignored copy of the last checked pieces (game files can't be committed), what changed in them; `make depcheck-accept` records the new state once checked. A second pass lists every game function our code calls (`core_environment.*`, `scenetree.*`, `be:*` and so on) and flags any that no longer exist. Limits: changes inside the game engine (C++), such as how `TSStatic` moves, still need the in-game checks
- [ ] !! Runner preference: a player's own choice not to be picked as runner by Next (whoever has run least) and the automatic next round. The host can still pick them by name in the Round tab
- [ ] ! Hard mode vs normal mode (a round setting): the police helicopter already removes the 30 s pings and hides the runner unless spotted; hard mode adds whatever else fits when planning it (for example no "Nearest cop" for the runner, no name plates or minimap markers for other cars, a shorter helicopter time up). Hard mode also raises the night and bad weather chances of night and weather rounds
- [ ] ! Spike strips for cops: a few per round on a button (keybind), placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] ! Dynamic roadblocks: parked cop cars that block part of the road ahead of the runner. Same goal as spike strips (stop the runner ahead), so plan them together
- [ ] ! Infection mode: game starts with 1 cop and caught runners become cops
- [ ] ! Leaderboard filter by conditions (All / Normal / Night / Bad weather), next to the car-mode filter, so storm records don't compete with clear-day runs unless wanted. Runs already record their conditions (night and weather rounds)
- [ ] ! Dry roads in tunnels: in rain, storm and snow rounds the road grip is the same inside a tunnel as outside, because the mod changes the map-wide surface types (`surfaces.lua`). The roof check that hides the rain (`shelter.lua`) could switch the surfaces back to dry while the player's own car is under a roof, with a short delay at tunnel mouths so grip doesn't flicker. Grip is simulated per player, so only your own car's grip changes noticeably; on your machine every road is briefly dry while you're under the roof
- [ ] ! Let the runner get out of their car and flee on foot during a chase. Work out how cops spot and catch the runner once they leave the car.
- [ ] ! Give the police helicopter an AI-generated voice. Decide in the spec whether the server or each player's client generates the speech.

- [ ] ! Workflow request. Make it easy to see which subagents are currently working when the session list also contains completed agents.

## Issues
