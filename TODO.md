# TODO

## Next
- [ ] Leaderboard UI app (requested after the control panel)
- [ ] Traffic during rounds. Today the traffic toggles are locked during a round, and the server refuses any car other than the round car for players in a round, which would also remove traffic they spawn. Needs: decide who spawns the traffic, let those cars through the vehicle rule, and keep crash penalties and catching limited to players

## Ideas
- [ ] Spike strips for cops: a few per round on a button, placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Escape route: the runner gets a random destination a few km away; reaching it ends the round as "Escaped" with a time bonus (GPS on BeamNG.Earth)
- [ ] Infection mode: a caught runner becomes a cop and the catcher becomes the next runner, so the round keeps going
- [ ] Night and weather rounds: the server sets the same time of day and weather for everyone per round (setting or `/cnr night`)
- [ ] Player stats: runs, best and average survival time, catches and assists per player; fits the leaderboard app. Once the cop line-of-sight check exists, also score the runner's time out of sight and how often they lost the cops

## Rules
- [ ] Parts changes during the round are only logged, not undone. BeamMP reports the vehicle config in two shapes, and restoring on a false difference caused a reset loop. Since 1.6.0 the server log names the slots that differ ("changed parts during the round (not enforced), slots: ..."): collect a few of those lines from real rounds, then compare only real part changes and restore with a loop guard

## Server
