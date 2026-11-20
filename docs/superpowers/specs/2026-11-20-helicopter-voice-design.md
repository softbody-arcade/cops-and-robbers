# Air One on the pursuit radio

Design for player review · 20 November 2026

## Why

A cop comes up on a West Coast highway exit a few seconds behind the runner. The helicopter has eyes on the car. Its rotor tells the cop that air support is nearby, and the position marker helps them find the runner on the map. What the driver needs to know before passing the ramp is *which road the runner took*. “Suspect took the exit toward downtown” answers that with the driver's eyes still on the road.

The runner has a stake in what happens next. If they make it into a tunnel, Air One can tell the cops which entrance it saw. The choice of where to emerge belongs to the runner. Hearing “Lost visual at the financial district tunnel” should leave a real decision for the cops on the ground.

## Goals

- Give a pursuing cop enough information to take a confirmed branch from the same approach, or recognize its destination when approaching from another direction.
- Make two quick moves understandable in order. The cop who hears “Took a left, then a right” should be able to repeat both directions without having to remember two separate radio calls.
- Give the crew a recognizable voice. Use a runner's recorded name or “the suspect” at first contact, then keep the channel clear for turns, exits and changes of sight.
- Make West Coast USA sound familiar to the group. On a map with no recorded place names, an observed junction turn or a travel heading should still be useful. A player driving a cop in solo Practice should hear the same kind of report as a cop in multiplayer.

## Non-goals

Helicopter flight, search paths, searchlight behavior, ground-cop AI, spotting rules and map markers are separate features. This release also leaves general police dispatch, voice commands from players, turn-by-turn routing for each cop, and recording every street or player name outside its scope.

## Anti-goals

- A pilot says “taking the east exit” because the helicopter is watching that mouth. A correct guess would still teach the cops that they can hear a hidden runner.
- A cop approaching from the far side hears “turn right” and drives away from the pursuit. Left and right must describe the runner's maneuver from the runner's direction of travel.
- A car following an S-bend triggers “left, then right,” or a driver on an overpass hears a tunnel-entry call about the car on top. Those false positives would make a genuine call hard to trust.
- Speech overlaps, recites old turns while the cop passes the next junction, or talks often enough that players mute it to hear the chase.

## User decisions

| Decision | Consequence for the first build |
| --- | --- |
| Give the helicopter an AI voice that reports what the runner actually did. A runner name or “suspect” works. Prepared variations fit the desired style. | Write short, complete lines for observed events. An exact exit becomes speakable once the crew sees the runner take it. |
| Support chained moves such as left then right. | Include all four ordered pairs of left and right. Give a turn that happens after the first call has aired its own natural continuation. |
| Prioritize West Coast USA, especially the highway exit into the city and the financial district tunnel. | Start with map-provided names and add specific approach and entrance matches for these two examples. |
| Test the implementation in game and tweak the locations from that drive. | Ship provisional mappings **and their audio** in the first playtest build. The group can drive its usual routes without first supplying a pin or screenshot. |

The audience, radio switch, handling of unrecorded names and speech-generation location below are design proposals. The timing values are starting points for the drive.

## What the current game establishes

| Evidence | What it gives the radio |
| --- | --- |
| The runner's client checks aircraft-to-car sight about every 0.25 seconds. In Practice with an AI runner, the issuer reports cover. Today's cover message carries the initial or changed, filtered result. [Client sight check](../../../client/lua/ge/extensions/copsAndRobbers/heli.lua) · [Server cover ownership](../../../server/CopsAndRobbers/cnr/round.lua) | Pair a fresh, clear aircraft sample with the car's actual road movement. A ground cop can keep the team's marker live after the aircraft loses sight. |
| The server gives a tracking helicopter two seconds of sustained cover before it starts searching. Ground units can guide the search, and the helicopter can watch possible exits. [Flight phases](../../../server/CopsAndRobbers/cnr/helicopter.lua) · [Exit search](../../../client/lua/ge/extensions/copsAndRobbers/heliSearch.lua) | A bridge can briefly block the aircraft without requiring a loss announcement. A search destination supplies no evidence that the runner emerged there. |
| The installed West Coast level has 135 zone entries in `city.sites.json`. They include Downtown Belasco, both directions of US Route 110 and repeated entries for the BMRA tunnel. BeamNG supplies connected road links and their elevations. [Road data used by the mod](../../../client/lua/ge/extensions/copsAndRobbers/roads.lua) | A zone can name the area. A particular ramp or tunnel entrance still needs a directional road match. The group's financial district label is provisional. |
| Rotor audio is positional. Thunder already plays packaged Ogg clips through a non-positional emitter. [Rotor sound](../../../client/lua/ge/extensions/copsAndRobbers/heliSound.lua) · [Thunder playback](../../../client/lua/ge/extensions/copsAndRobbers/lightning.lua) | The mod has a playback path for an in-car transmission. Whether a short sentence is intelligible over the engine and siren still needs a listen. |

## Approaches

| Where speech is generated | Benefit | Cost during a chase |
| --- | --- | --- |
| **Prepare whole AI-voiced lines when building the mod. Recommended.** The server selects a line and each cop plays the bundled recording. | We can listen to the pronunciation and cadence of “left, then right” before it ships. Every cop gets the same pilot and wording. | The voice can use only recorded names and phrases. A new local nickname needs a new recording. |
| Synthesize prepared text on the live server and cache the result. | The host can add unfamiliar player and place names during a session. | A cache miss needs synthesis and audio delivery to connected clients before the turn goes stale. Hosts need a model or service. |
| Synthesize prepared text on each client. | A player's machine can speak arbitrary names without receiving new audio. | Each supported installation needs a usable voice engine. Players may hear different pronunciation and delays for the same call. |

The proposed first release spends the synthesis time before the chase. Use one English-speaking pilot, complete sentences and a few variations. An improvised account of the chase would add wording latency precisely when the cop is deciding whether to take the exit.

## Design

### Who hears Air One

Only released, participating human cops receive the radio. This includes a player driving a cop in solo Practice. A human runner, a spectator watching an AI round and a cop waiting through the head start hear silence. If the helicopter is already tracking at cop release, a fresh clear observation can start the first contact call.

Add **Helicopter radio** beside **Helicopter sound** in player settings. Radio defaults on, including for existing settings files. It plays in the listener's car regardless of camera distance from the aircraft. Muting radio stops the current sentence immediately. A player can keep radio on with rotors off or hear rotors with radio off. [Existing player preferences](../../../client/lua/ge/extensions/copsAndRobbers/playerSettings.lua)

### What a pursuit sounds like

| What happens in the chase | What a cop hears |
| --- | --- |
| Air One first sees a runner with a recorded name and a clear northbound heading. | “Air One has Reinder, northbound.” For an unfamiliar player or an AI runner, “Air One has the suspect, northbound.” |
| The runner drives past the city ramp, then another time takes it from the mapped approach. | Passing the ramp earns silence. Taking it earns “Took the exit toward downtown.” Use “first exit” only where the map establishes the count from that approach. |
| The runner takes a left and then a right at two visible junctions. | Close together, “Took a left, then a right.” If the left has already been called, “Now taking a right.” |
| The last clear view shows the car entering the mapped tunnel mouth. Sustained cover puts the aircraft into search. | “Lost visual at the financial district tunnel.” If the crew saw only the runner disappear behind a building nearby, “Lost visual.” |
| A ground cop follows the runner inside. The aircraft later sees the runner emerge heading east. | Quiet while the aircraft searches. When it regains sight after an announced loss, “Back in sight, heading east.” |

Start with an empty list of recorded player names. Add a name when that player supplies the spelling and pronunciation and agrees to the packaged recording. “Reinder” illustrates the named version. An unlisted or renamed player immediately gets the generic line. Choose a different fitting variation from the previous one where possible. Omit an optional name, heading or location when the catalogue has no complete line for that combination.

### What counts as a move

The observing client uses the runner's visible travel across a junction. It must match the incoming road and the outgoing branch using connected drivable roads, direction, distance travelled and elevation. A steering correction, reversing through the junction or following a curve with a single way forward earns no turn. With ambiguous road geometry, omit the turn. A clear direction of travel can still support a heading on first contact or reacquisition. A stationary or reversing car supplies no new outbound heading. First contact can simply say “Air One has the suspect.”

Prefer the map's readable place name where the voice catalogue has a match. For West Coast USA, pick a plausible city-bound ramp and downtown tunnel mouth from installed map data. Record a starting landmark, approach, outgoing road, height and direction for each. A car crossing above the mouth or on a parallel road gets no named call. Use the group's first drive to adjust the candidate or its spoken label. On other maps use known place names when available and ordinary observed turns elsewhere.

### When to combine, interrupt or drop a call

Hold the first ordinary turn briefly. Two distinct junction turns in that window, with uninterrupted aircraft sight, become one recording in the order seen. That includes “Two lefts in succession.” Once the first call starts, it counts as heard. A second turn within the continuation window can follow at the next break. After a pair, a fresh third turn can stand alone. A bend or a blocked sight sample cannot supply the second half.

A named exit bypasses the hold and replaces an unsent ordinary turn. If the runner goes left and takes the downtown ramp 0.75 seconds later, the useful line is “Took the exit toward downtown.” While a clip plays, allow at most one waiting call. Keep the latest useful maneuver. Use standalone wording if an intervening turn was dropped. Never talk over a clip to squeeze in another one.

The first blocked aircraft sample clears waiting route calls. During a brief obstruction, the radio stays quiet. Announce a loss only after prior visual contact and a transition into search. Remember the last visibly entered mouth through continuous blocked samples. A gap in observations clears that evidence. If the crew sees the runner again before the loss call starts, cancel it. If the loss has already aired, one fresh sighting earns reacquisition.

### How all cops get the same report

The client responsible for the runner's cover sends ordered observations for its assigned car and flight. The server checks sender, pursuit identity, sequence, sample age and flight phase, then picks one recording for the eligible cops. A client's fresh observation supplies what happened. The server's pursuit state determines whether the crew may say it. A team position update or a predicted search exit cannot substitute for aircraft sight.

The server schedules around the measured length of each recording. Each client checks that a call still belongs to its pursuit and can start before its deadline. Skip an unknown or missing recording. Round end, replacement of the runner or reporter, refuelling, grounding and helicopter disable clear pending speech. A listener who rejoins, unmutes or regains the cop role starts with new transmissions.

## Proposed tuning for the first playtest

| Setting | Starting value | What to judge |
| --- | --- | --- |
| Hold for a second ordinary turn | Up to 1 second after the first | Does “left, then right” sound like one thought, and does a single left still arrive in time to take it? |
| Continuation after an announced turn | Within 4 seconds of the first maneuver | Does “now taking a right” still refer clearly to the left the driver heard? |
| Latest start of a maneuver call | Before 3 seconds have elapsed since the last maneuver in it | If a busy channel holds a turn past the deadline, drop it. A driver should hear the current decision. |
| Line length and delivery | Aim for about 2 seconds wherever the wording permits | Can a cop hear the destination or second direction over a siren? Use measured clip length to schedule the next line. |
| Observation gap | Start by treating two missed 0.25-second samples as stale | A reporting pause must end a chain. Check ordinary travel still supplies consecutive observations at junctions. |

## Automated acceptance

| Replay or fixture | Observable pass condition |
| --- | --- |
| Drive the candidate ramp, its bypass, the road above it and its reverse. Repeat at the tunnel mouth and on an unknown map. | Only the matched approach earns the local label. The unknown map still produces a confirmed generic turn. Moving forward with missing road data still allows a supported contact heading. Stopping or reversing earns no new heading. |
| Replay all four turn pairs at 0.75 seconds apart, then a pair at 1.5 seconds with the first already aired. Try a third turn, an S-bend and a named ramp following an unsent left. | The close pairs play once in order. The later turn uses a continuation. The third never extends the sentence to three clauses. The bend stays quiet and the named exit replaces the pending left. |
| Break sight between turns, pass briefly under a bridge, then replay sustained tunnel cover while a ground cop has sight. Reacquire both before and after the loss call starts. | No chain crosses the break. Only sustained confirmed loss earns a loss line. No hidden exit leaks. Only an announced loss earns “Back in sight.” |
| Feed a delayed or duplicate packet, wrong reporter, stale car or flight, role change, mute/unmute and reconnect through the normal round handlers. | Released human cops get the same current phrase once. Ineligible players hear silence. Obsolete calls never resume. Radio and rotors can be toggled independently. |
| Check the packaged assets and measured durations for paired turns, follow-ups, named routes, first contact and loss. Try an unfamiliar display name and a missing clip. | Every required line decodes and has a duration. Unknown names get “suspect.” A missing asset skips cleanly and a later valid call can play. |

## Engine questions and in-game checks

The installed level supplies candidate geometry. The first radio build is where the group decides whether the mapped entrances and spoken names match its own routes. These are the checks that need a driver or listener. The deterministic cases above belong in tests.

| Shortest setup and action | Observable pass condition | What the check settles |
| --- | --- | --- |
| One player, West Coast USA. Use the staged solo route check to drive the usual city-bound exit and the financial district tunnel, then pass the ramp once. The check simulates the aircraft entering search. | The turnoff is called as the car commits, passing it is quiet, and the loss line names the entrance the driver recognizes. | Which ramp and mouth the group means, their local names and where each trigger should sit. |
| Inspect the real aircraft sight trace from a staged chase through the candidate mouth. A solo Practice runner can drive it while the reporter records the approach. | The trace shows whether the final clear sample places the runner on the incoming branch at the mouth, followed by continuous cover and search. That sequence qualifies for the named loss. Earlier occlusion qualifies only for generic loss. | Whether the actual aircraft can see the car commit to this entrance from its flight path. The trace answers this even when the driver is the runner and hears no radio. |
| One player, Practice as cop with the helicopter airborne. Hear a pair of turns with the engine and siren on. If the AI takes another route, replay the captured pair timing locally. | Both directions are intelligible in order. The cop can still act on the second one. | Radio level, natural delivery of “then,” and whether the one-second hold helps or costs a turn. |

## Left to the builder

Choose the synthesis tool and a voice that permits distribution, trim and level the recordings, and author variations that fit the same observed facts. Select road-matching thresholds against the candidate, bypass and wrong-height fixtures. Choose the small route data format so a playtest correction can move an entrance or change its label without rewriting pursuit logic. The implementation plan covers modules, clocks, fixtures and staging. [Implementation plan](../plans/2026-11-20-helicopter-voice.md)
