# TODO

## Next
- [ ] Leaderboard UI app (requested after the control panel)

## Rules
- [ ] Parts changes during the round are only logged, not undone. BeamMP reports the vehicle config in two shapes, and restoring on a false difference caused a reset loop. Since 1.6.0 the server log names the slots that differ ("changed parts during the round (not enforced), slots: ..."): collect a few of those lines from real rounds, then compare only real part changes and restore with a loop guard

## Server

## Check in game (1.6.0)
- [ ] HUD and panel follow the UI scale setting; HUD still lands bottom centre
- [ ] Panel: picking a player from the runner list starts them; a stepper change made just before closing the panel is saved
- [ ] Practice round: an AI crash shows once in the event line
- [ ] Result card disappears when leaving the server, and "Next round in" disappears on `/cnr auto off`
