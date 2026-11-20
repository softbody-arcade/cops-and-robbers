# Air One on the pursuit radio

Design for player review · 20 November 2026

A cop a junction behind the runner should hear enough to choose the same exit while keeping their eyes on the road. Air One is a spotter. “Took the first exit toward downtown” tells the driver which choice the runner made. “Turn right” could send two cops approaching from different directions down different streets. Every left and right is from the runner’s direction of travel.

## What a chase sounds like

| What the crew sees | What pursuing cops might hear |
| --- | --- |
| First clear sight of a known runner travelling north | “Air One has Reinder, northbound.” |
| An unfamiliar player commits to the first city-bound ramp on a surveyed approach | “Suspect took the first exit toward downtown.” |
| Two nearby junctions, both turns visible before the radio speaks | “Took a left, then a right.” |
| The left has already aired when the crew sees the right | “Now taking a right.” |
| The last clear view is of the runner entering the identified tunnel mouth, followed by sustained loss of sight | “Lost visual at the financial district tunnel.” |
| A ground cop sees the runner inside, while the helicopter watches a possible exit | Radio stays quiet. On seeing the runner emerge, the crew can say “Back in sight, heading east.” |

The group asked for short directions, runner names or “suspect,” natural variations, and sentences that can chain successive moves. West Coast USA gets extra attention because it is the map the group plays most. The highway exit and financial district tunnel are the two routes to identify first. The **audience, timing, voice production and name coverage below are proposed defaults**.

## When two moves belong in one sentence

Give the first confirmed ordinary turn up to **one second** before starting its call. If a second distinct junction turn is confirmed in that window for the same runner, during uninterrupted aircraft sight, say them in order in one transmission. The writer prepares all four pairs, including “Two lefts in succession.” A left at a junction followed by a rightward bend on the same road earns only the left. A swerve or steering correction earns neither.

Once the first call has started, treat it as heard. A second confirmed turn within **four seconds of the first** gets a short continuation at the next available break. Never repeat the first clause. Cap each transmission at two maneuvers. After a spoken pair a third turn can stand alone if it is still fresh. Keep at most one unsent call while audio is playing. On overload keep the latest useful action, and use standalone wording if an intervening maneuver was dropped. A confirmed named exit bypasses the one-second hold and takes the next available break. It replaces any unsent ordinary turn, even a left at the preceding junction. For a left followed 0.75 seconds later by the surveyed ramp, cops hear “Took the first exit toward downtown.” The ramp gets only one call.

The first blocked sight sample clears pending route calls and breaks the chain. A brief obstruction that clears during tracking grace earns silence. Queue a loss report only when the helicopter enters search after having seen the runner. If sight returns before that report starts, cancel it and resume ordinary calls. Once a loss report starts, the next confirmed sighting earns “Back in sight.” The server tracks which calls it has started for the pursuit. A listener who missed the loss through mute or a connection delay can still understand the reacquisition on its own.

Start with a **three-second start deadline** from the last maneuver in a line and keep recordings short enough to finish in roughly two seconds where the wording permits. The server accounts for the selected clip’s measured duration before issuing a continuation. Clients drop expired calls. Timing, phrase variety and the delivery of “then” are listening-test decisions. A pause long enough to miss the exit or a backlog narrating three junctions ago would spoil the feature.

## What the helicopter can know

The existing helicopter checks the line from the aircraft to the runner on the game client roughly every quarter second. The cover report sends initial or changed, filtered cover state. The server keeps tracking for two seconds under cover and can receive guidance from a ground cop while the aircraft searches. All three signals serve gameplay today. Voice needs the actual clear sample associated with each maneuver. [Aircraft sight](../../../client/lua/ge/extensions/copsAndRobbers/heli.lua) · [Flight phases](../../../server/CopsAndRobbers/cnr/helicopter.lua)

- The client already responsible for cover, the human runner or the Practice host for an AI runner, observes the driven road and aircraft ray together. While visible, match approach and departure to connected, drivable road segments, using movement over several samples. A turn requires commitment to a distinct branch at a junction. Level, direction, travel distance and connectivity must distinguish parallel ramps, stacked roads and ordinary curves. When the match is ambiguous, omit the turn. A clear travel heading can still accompany contact or reacquisition. Parked or reversing cars do not establish a new outbound heading.
- The observer sends bounded event and place identifiers with their observation sequence and current pursuit identity. The server accepts only its designated reporter for this runner and round, fresh observations from the current flight and a valid phase. Raw sight loss breaks turn continuity immediately, even within tracking grace. A sustained loss call needs prior confirmed sight and the aircraft entering search. If the last visible approach cannot establish tunnel entry, say “Lost visual.” Keep only the last positively observed place for that call. Acquisition and reacquisition need a fresh clear observation. Server positions, ground-cop guidance and predicted search exits alone cannot authorize speech. [Cover reporter](../../../server/CopsAndRobbers/cnr/round.lua) · [Client road graph and aircraft update](../../../client/lua/ge/extensions/copsAndRobbers.lua)
- The server chooses a single phrase variant and sends it only to active human cops once the cops are released. Solo Practice as cop hears the same reports about the AI runner. A human runner, a spectator and a cop still waiting for release hear silence. At release, first contact requires current sight. Disable, refuel, grounding, round end, reporter or runner replacement and role changes invalidate pending calls. Rejoining, unmuting or regaining eligibility never replays a backlog. A local mute stops current playback.

## Place names that help a driver

Start with the map’s own readable place names. The installed West Coast USA level has 135 entries in `city.sites.json`, including Downtown Belasco and repeated entries for the BMRA tunnel. A named area can locate a sighting. Naming a particular exit or tunnel mouth requires a route match. For the first playable build, choose a plausible city-bound ramp and downtown tunnel mouth from the installed map. Record the approach, outgoing branch, elevation and direction for each candidate. Ship the candidate mappings and their spoken lines so the group can drive them and tell us which location, wording or timing to tweak. The group chose to identify its preferred routes in game. Use “first exit” only on an approach where the exit order can be established from the map. “Financial district tunnel” is a provisional local label. When road or sight evidence is ambiguous during a chase, use a generic call.

The bundled voice can pronounce the places in its catalogue. Match the level and its map-provided name to a recorded label, with small hand-authored overrides for those West Coast routes. Other maps get the same junction and heading calls, plus any recorded name that matches their map data. An unknown name, missing graph or uncertain exit should still give a truthful call such as “Back in sight, eastbound,” when the evidence supports it. Avoid repeated heading reports on every bend. First contact, reacquisition and confirmed route decisions are the occasions to speak.

## Where the AI voice runs

| Approach | What players and hosts would experience |
| --- | --- |
| **Prepare AI-voiced recordings when making the mod; select on the server and play on the client. Recommended.** | A consistent crew voice, reviewed place pronunciations and immediate offline playback during a chase. Vocabulary grows when new recordings ship. |
| Generate prepared text on the live server and cache the result | Can pronounce new names after synthesis. Requires a working voice service or model and a way to deliver new audio to already-connected players before the call expires. |
| Synthesize prepared text on each player’s machine | Can speak arbitrary map and player names. Depends on a usable voice engine on each installation, with differing voices, pronunciation and startup times. |

Ship complete English lines as Ogg files, including the four turn pairs and standalone continuations. Use the same pilot, pace and radio treatment for all of them. Start with the generic line and an empty name list. Add a named first-contact clip when the player supplies the exact display name, confirms the pronunciation and opts in to distributing the recording. “Reinder” illustrates that path. Use a synthetic fixture name to test it before any player opts in. Use “the suspect” immediately for any unlisted or renamed player and for AI runners. Optional details such as a destination or name are included only when a complete clip exists for those facts. Choose a different valid variant from the last one when available. Never build a spoken name from unreviewed player text. Choosing the synthesis tool, voice with suitable distribution rights, trimming and file layout belongs to the builder.

The BeamMP server sends a clip ID, sequence, pursuit identity and expiry. It never needs an audio generator during play. A client plays the packaged file once as a non-positional radio transmission, independent of camera distance. An unknown or missing clip is skipped. Add a local **Helicopter radio** toggle, initially on, beside the existing helicopter preferences. Rotor sound keeps its own control. Thunder already uses packaged Ogg files and non-positional emitters. Speech clarity over sirens and the gap between two clips still need an in-car listen. [Current helicopter preferences](../../../client/lua/ge/extensions/copsAndRobbers/playerSettings.lua) · [Thunder playback](../../../client/lua/ge/extensions/copsAndRobbers/lightning.lua)

## What proves the design

| Check | Expected observation |
| --- | --- |
| Replay a surveyed highway trace taking the exit, passing it and passing above it | Only the first trace earns the named exit. Reverse travel uses only labels verified for that approach. |
| Replay two distinct junctions at 0.75 s and 1.5 s apart, a single S-bend, and a three-turn burst | The close pair produces one ordered recording. The separated pair gives a single plus a continuation if fresh. The bend stays quiet. The third turn never creates a three-clause sentence or replays an older turn. |
| Follow a left immediately with a named ramp, then try a brief obstruction and a sustained loss that clears before its queued report airs | The named ramp replaces the pending left. Neither obstruction produces a stray “Back in sight.” A sustained loss that actually starts playing gets one subsequent reacquisition. |
| Break the aircraft ray between two turns, continue under cover while a ground cop sees the runner, then emerge | No chain crosses the gap. Loss identifies only the last confirmed entry. The exit or heading becomes speakable after the fresh sighting. |
| Feed duplicate, expired, wrong-role and previous-round events, toggle mute mid-call, then reconnect | Only eligible cops receive a current call. Each eligible listener plays it at most once. Muting stops the clip and reconnecting starts with an empty queue. |
| Audit the shipped voice catalogue against all four pairs, follow-ups, checked West Coast labels and name fallbacks | Every required phrase has a playable asset and a measured duration. A new player and a map without known names still get complete grammatical lines. |

During the build, verify candidate geometry with local map data, then replay approach, bypass and wrong-height samples. During the first staged playtest, drive the group’s familiar routes and compare the spoken label and trigger point with what the driver sees. Use that feedback to adjust the mapping. For the listening check, one player in Practice as cop can hear the actual recordings over their engine and siren. Use a reproducible pair of observed turns or replay its captured event timing locally. The listener should be able to repeat both directions in order, hear one natural transmission for the close pair, and still have time to act on the second turn. Keep open geography and listening checks with the other in-game checks once there is a staged build.

Changes to helicopter search, pursuit AI, map markers, cop routing and general dispatch chatter are outside this feature. A pilot that guesses the next exit, exposes a hidden runner or talks so continuously that the cops tune out would fail the chase even with perfect audio playback.
