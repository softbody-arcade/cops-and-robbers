# TODO

## Next
- [ ] Leaderboard UI app (requested after the control panel)
- [ ] Traffic during rounds. Today the traffic toggles are locked during a round, and the server refuses any car other than the round car for players in a round, which would also remove traffic they spawn. Needs: decide who spawns the traffic, let those cars through the vehicle rule, and keep crash penalties and catching limited to players

## Rules
- [ ] Parts changes during the round are only logged, not undone. BeamMP reports the vehicle config in two shapes, and restoring on a false difference caused a reset loop. Since 1.6.0 the server log names the slots that differ ("changed parts during the round (not enforced), slots: ..."): collect a few of those lines from real rounds, then compare only real part changes and restore with a loop guard

## Server
