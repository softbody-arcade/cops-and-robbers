# TODO

## Next
- [ ] Leaderboard UI app (requested after the control panel)

## Check in game
- [ ] Cop emergency lights with the new part-tree planner: I-Series and Burnside beacons, Miramar and pickup light bars, midtruck's four beacons
- [ ] Control panel: typing in Excluded cars doesn't trigger car bindings, collapses on GO and opens at round end, dropdown renders inside the app box
- [ ] Control panel shows up in Esc > UI Apps after joining
- [ ] HUD is placed in BeamNG.Earth's MP layout after it switches
- [ ] HUD is removed from layouts after leaving the server; 230 px placement after leave + rejoin

## Rules
- [ ] Parts changes during prep are only logged, not enforced: find out the two config shapes BeamMP reports, then restore safely without a reset loop

## Control panel (from the 1.5.0 review)
- [ ] Reject list entries that aren't strings or numbers (hostile payloads save junk names)
- [ ] Send a request id with settings saves and echo it back, instead of matching replies by order
- [ ] Reset the panel in `onMode` so open panels resubscribe after a plugin hot-reload
- [ ] Flush the pending change on unmount instead of dropping it
- [ ] Stepper: floor/ceil to the next grid value when the current value is off the step grid
- [ ] Wrap `pushPanel()` in `cnrTick` in a pcall
- [ ] Keep the original case of names in replies; handle players named next/again/random; reply on over-long names

## HUD and client
- [ ] Extract the HUD push from `onUpdate` before adding anything there (56 of 60 upvalues used)
- [ ] AI crash shows twice in the event line
- [ ] "Next round in N" keeps counting after `/cnr auto off`
- [ ] Clear `hudResult` on leaving the server
- [ ] Font sizes in px don't follow UI scaling
- [ ] `margin: auto` placement is marked deprecated by the layout system
- [ ] Placement polling cost; layout copy in the user folder; `refreshUiApps` side effects

## Docs
- [ ] `docs/FEATURES.md`: prep row says a parts change puts the car back (not enforced since the hotfix)
- [ ] `docs/FEATURES.md`: light bar line still describes copying from a police config (now the part-tree planner)

## Server
