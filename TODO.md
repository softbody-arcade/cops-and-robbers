# TODO

## Next
- [ ] Traffic during rounds. Today the traffic toggles are locked during a round, and the server refuses any car other than the round car for players in a round, which would also remove traffic they spawn. Needs: decide who spawns the traffic, let those cars through the vehicle rule, and keep crash penalties and catching limited to players

## Ideas
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars)
- [ ] Spike strips for cops: a few per round on a button, placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Escape route: the runner gets a random destination a few km away; reaching it ends the round as "Escaped" with a time bonus (GPS on BeamNG.Earth)
- [ ] Infection mode: a caught runner becomes a cop and the catcher becomes the next runner, so the round keeps going
- [ ] Night and weather rounds: the server sets the same time of day and weather for everyone per round (a panel switch)

## Server

## Issues
- [ ] Practice as runner: the AI cops keep the old build after Apply. Needs respawning the AI cars with the new config (and re-reporting their vehicle ids to the server)
- [ ] Queued change: part names come from the runner's game, so a player who lacks a part sees its name without a "⚠ missing" mark (missing parts are only reported at Apply)
- [ ] Apply: a "car placed" report from before the rebuild can count a player as ready too early. Needs a rebuild id in the ready report
- [ ] Apply can take up to ~40 s when the runner's game never answers (20 s for his setup, then 20 s for everyone to load)
- [ ] BeamNG.Earth: if the runner's position is out of date at the moment sight is lost, the one "last seen" ping is skipped
- [ ] BeamMP's own `beammp` layout keeps a user copy after the HUD was placed (only the stock BeamNG.Earth layout copy is reset on leave)
- [ ] Server-side parts enforcement: since 2.0.1 every menu is locked during a round on the client, but the server still only logs part edits ("changed parts during the round (not enforced), slots: ..."), so a modified client could still change parts
