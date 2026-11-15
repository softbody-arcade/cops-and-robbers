# TODO

## Ideas
- [ ] Traffic during rounds. Today the traffic toggles are locked during a round, and the server refuses any car other than the round car for players in a round, which would also remove traffic they spawn. Needs: decide who spawns the traffic, let those cars through the vehicle rule, and keep crash penalties and catching limited to players
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars)
- [ ] Spike strips for cops: a few per round on a button (keybind), placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Infection mode: game starts with 1 cop and caught runners become cops
- [ ] Night and weather rounds: the server sets the same time of day and weather for everyone per round (a panel switch)

## Issues
- [ ] Cop start spots are picked by straight-line distance from the runner (50-150 m), not by how far it is to drive there. A mountain road above the runner, the other side of a hairpin, or a road across a river or divided highway counts as close even when driving there takes much longer, and switchbacks make it worse. Pick spots by driving distance along the road network instead (the same goes for moving AI cops back near the runner)
