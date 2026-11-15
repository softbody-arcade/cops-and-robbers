# TODO

## Next
- [ ] Traffic during rounds. Today the traffic toggles are locked during a round, and the server refuses any car other than the round car for players in a round, which would also remove traffic they spawn. Needs: decide who spawns the traffic, let those cars through the vehicle rule, and keep crash penalties and catching limited to players

## Ideas
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars)
- [ ] Spike strips for cops: a few per round on a button, placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Escape route: the runner gets a random destination a few km away; reaching it ends the round as "Escaped" with a time bonus (GPS on BeamNG.Earth)
- [ ] Infection mode: a caught runner becomes a cop and the catcher becomes the next runner, so the round keeps going
- [ ] Night and weather rounds: the server sets the same time of day and weather for everyone per round (setting or `/cnr night`)
- [ ] Evolving car mode (friend's idea): the round car is a real player-built car instead of a stock config, so custom setups work. Start from a random or chosen car; after each round the runner may change one part (or tune), that change is synced to every cop's copy, and the evolved car carries over to the next runner. Needs: sending the full config (parts and vars) from the server instead of a .pc path, a one-change rule check for the runner's edit, and saving the car between rounds

## Rules
- [ ] Parts changes during the round are only logged, not undone. BeamMP reports the vehicle config in two shapes, and restoring on a false difference caused a reset loop. Since 1.6.0 the server log names the slots that differ ("changed parts during the round (not enforced), slots: ..."): collect a few of those lines from real rounds, then compare only real part changes and restore with a loop guard

## Server
