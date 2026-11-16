# TODO

## Ideas
- [ ] Traffic during rounds (designed, branch traffic-rounds, `docs/superpowers/specs/2026-11-16-traffic-rounds-design.md`): every player's game runs a few traffic cars around itself (`trafficPerPlayer`, default 5, capped by MaxCars), through the game's own traffic system. Normal maps only; off on BeamNG.Earth for now
- [ ] Traffic on BeamNG.Earth (after traffic on normal maps has been played and tuned). BeamNG.Earth's navgraph manages any running traffic itself: it moves cars that stand still 45 s (our traffic is held still through prep), hides all traffic after a teleport until the new road graph arrives (round setup moves cops far), the road graph arrives after the round car is placed (a moved cop's traffic finds no roads), and a region change sets traffic up again with the player's own amount and police choice. Traffic positions would also have to travel as latitude/longitude for the crash fault rule
- [ ] Traffic headlights: traffic keeps the game's behaviour for now (lights on at night and in tunnels, unlit in daytime fog, thinner traffic at night). Tune after playing, for example lights on in thick fog
- [ ] Hard mode vs normal mode (a round setting): hard mode gives cops a route/position only while someone has sight (no 30 s last-seen pings), hides the name plates above cars, and whatever else fits when planning it (for example no "Nearest cop" for the runner, no minimap markers for other cars)
- [ ] Spike strips for cops: a few per round on a button (keybind), placed behind or ahead of the cop and visible to everyone (the game has spike strip props)
- [ ] Dynamic roadblocks: parked cop cars that block part of the road ahead of the runner. Same goal as spike strips (stop the runner ahead), so plan them together
- [ ] Infection mode: game starts with 1 cop and caught runners become cops
- [ ] Night and weather rounds: the server sets the same time of day and weather for everyone per round (a panel switch)

## Issues
- [ ] Cop start spots are picked by straight-line distance from the runner (50-150 m), not by how far it is to drive there. A mountain road above the runner, the other side of a hairpin, or a road across a river or divided highway counts as close even when driving there takes much longer, and switchbacks make it worse. Pick spots by driving distance along the road network instead (the same goes for moving AI cops back near the runner)
