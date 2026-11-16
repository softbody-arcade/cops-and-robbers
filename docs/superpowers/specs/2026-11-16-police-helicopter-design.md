# Police helicopter

Status: design for review, 2026-11-16. Replaces the periodic last-seen ping (`lastSeenIntervalSeconds`) with a police helicopter that tracks the runner in the open. Also hides the runner from the cops' minimap and name tags unless they are spotted.

## Why
- **The fixed ping is mechanical.** Every 30 s every cop gets the runner's position, wherever the runner is. A helicopter that tracks the runner in the open, loses them under cover and has to refuel gives the chase phases and gives the runner something to do: get under cover.
- **Sight matters little today.** Cops see the runner's car on the game's minimap and through BeamMP's name tag from anywhere.

## Goals
- **The periodic last-seen ping is gone.** The `lastSeenIntervalSeconds` setting goes too. One "last seen" ping still goes out when the runner stops being spotted: no cop sees them and the helicopter isn't tracking.
- **A police helicopter, on by default.** It's a tracking rule, not a flying model: the game ships no helicopter.
  - **Host settings:** arrival time, time up, refuel time.
  - **While up and the runner is in the open:** cops get the runner's live position, like cop sight.
  - **Under cover** (tunnels, bridges, garages, canopies): it loses the runner and searches. If no cop sees the runner either, cops get one last-seen ping where the runner went under.
  - **Weather:** it stays grounded in storm, fog and snow.
- **Everyone sees the helicopter's state on the HUD.**
  - At night, a searchlight shines on the runner while it tracks.
- **The runner is hidden from cops unless spotted.**
  - **From the runner's release (the head start) on,** the runner's name tag and minimap marker show on the cops' games only while the runner is spotted, meaning a cop has sight or the helicopter is tracking.
  - **In prep and the countdown,** the runner shows as today.
  - **With the sight range set to Off,** the runner is never hidden.

## Non-goals
- **A visible helicopter model or rotor sound.** None ships with the game. We'd have to ship our own.
- **A host switch for the hiding.** It always applies.
- **Pings while the helicopter is grounded or away.** There are none; cops have their own sight only.
- **Hiding the runner's car itself.** Cops still see the car in the world when it's in view. Only the marker and the name tag are hidden.
- **A minimap ring or icon for the helicopter.** Dropped on 2026-11-16: the helicopter does not show on the minimap.
- **Minimap hiding on BeamNG.Earth.** Earth uses its own map. The helicopter still tracks there, through Earth's GPS like sight does.

## Anti-goals
- **A cop who sees the runner losing their live position** because of the helicopter's state. Cop sight keeps working as today.
- **A name tag or minimap marker left hidden** after the round, a cancel or leaving the server.
- **A searchlight left in the scene** after the round, a cancel, leaving or a map change.
- **Countdowns that differ between players.** The server owns the phases. Clients only count down what the server sent.

## Decisions (from the conversation, 2026-11-16)
| Decision | Value |
|---|---|
| Helicopter on by default | yes (`helicopter = true`) |
| Limited availability | arrives, flies, refuels, flies again, until the chase ends |
| Pings | none at all, also while the helicopter is grounded, arriving or refuelling |
| Hiding the runner | always, also with the helicopter off |
| Hiding starts | at the runner's release (the head start); prep and the countdown show the runner as today |
| Sight range Off | the runner is never hidden |
| Visuals | searchlight at night only; no model, no minimap ring (dropped 2026-11-16) |

## Weather and night
| Round weather | Helicopter |
|---|---|
| Clear, Cloudy, the map's own (no weather set), BeamNG.Earth | flies normally |
| Rain | flies; finds the runner again after **10 s** in the open instead of 5 |
| Storm, Fog, Snow | **grounded** for the whole round. The HUD says "HELICOPTER GROUNDED (FOG)" |
| Night (any time of day setting) | flies as normal, with the searchlight on |

The weather is the round's sky weather (`current.sky.weather` on the server). New sky in prep can change it. A grounded helicopter never arrives that round.

## Design

### Server: the helicopter (new pure module `cnr/helicopter.lua`)
- **Config** (`cnr/config.lua` `DEFAULTS`):

  | Key | Default |
  |---|---|
  | `helicopter` | true |
  | `helicopterArrivalSeconds` | 60 |
  | `helicopterUpSeconds` | 120 |
  | `helicopterRefuelSeconds` | 90 |

  - **Arrival** is at least 0. Arrival 0 means it's up at release.
  - **Time up** must be more than 0 (`strictlyPositive`).
  - **Refuel** is at least 0. Refuel 0 means it never leaves: once up, it stays up for the rest of the chase, and the HUD shows no countdown.
- **Retired:** `lastSeenIntervalSeconds` joins `RETIRED_KEYS`, so a panel save drops it.
- **Panel:** a new "Helicopter" group in the Settings tab:
  - a switch "Police helicopter"
  - three steppers in seconds, shown as durations like the time limit, each with a short help line
  - it replaces the "Last seen every" row
- **State machine:**
  - **Phases:** `grounded`, `arriving`, `up` (with `tracking` or `searching`), `refuelling`.
  - **Start and clock:** it starts at cop release (the round's `running` state). Time is measured in round seconds from `now`, like penalties.
  - **Timers:**
    - `arriving` lasts the arrival time, then `up`.
    - `up` lasts the time up, counting both tracking and searching, then `refuelling`.
    - `refuelling` lasts the refuel time, then `up` again.
  - **Grounded:** a weather of storm, fog or snow means `grounded` for the whole round.
  - **Tracking and searching:**
    - On entering `up`, it is `tracking` if the runner is in the open, otherwise `searching`.
    - When the runner goes under cover while tracking, it switches to `searching`. The round sends a `lastSeen` only under the rule in "Pings" below.
    - While searching, after the runner has been in the open for the re-find time (5 s, or 10 s in rain), it switches to `tracking`.
- **Effects:**
  - **Live position while tracking:** a `live` update every `sightLiveIntervalSeconds` (the same throttle as sight, at least 3 s on Earth), sent to every cop like sight's live update.
  - **No-route rule:** `noRoute` stays per cop, worked out exactly as now, for cops who themselves see the runner.
  - **One live stream:** when both sight and the helicopter would send a live update in the same tick, only one goes out.
  - **Phase changes** send `heli` to everyone in the round: `{ phase, seconds = time left in the phase or nil, reason = weather key when grounded }`. It is also sent in each player's round setup, so a rejoiner sees it.
- **Pings:**
  - **The periodic ping goes:** the interval branch in `Round:tick` (`round.lua:368-377`) is removed. This includes the sight-Off fallback that `tests/test_round.lua:753-758` asserts today.
  - **One last-seen ping per loss:** the round tracks `tracked`, which is cop sight (`self.inSight`) or the helicopter `tracking`. When `tracked` goes from true to false, it sends one `lastSeen` at the runner's position.
    - This replaces both the lost-sight ping in `sightTick` and the helicopter's cover ping.
    - So a cop who still sees the runner never gets a route to a tunnel mouth, and losing sight while the helicopter tracks sends no stale ping.
  - **Live updates:** both live sources share the `liveAt` throttle.
  - **The runner's nearest-cop readout:** the runner still gets `cnr_nearestCop` every 30 s while running (a fixed interval, not a setting), plus with each live update as today. Cops get nothing from this.
- **Spotted for hiding:** the server tracks `shown`:
  - **True** in prep and the countdown, and for the whole round when `sightMaxMeters` is 0 (sight Off).
  - **From the head start on** (sight on), it equals `tracked`. In the head start nobody can have sight yet and the helicopter isn't up, so the runner is hidden there.
  - **On a change** it sends `runnerShown { shown }` to every cop (not the runner), and it is included in round setup.
- **Run record:** a run notes `helicopter = true` when the helicopter flew that round (on and not grounded), like `traffic`. There is no leaderboard filter for it yet.
  - The runner's own SPOTTED / HIDDEN tag stays tied to cop sight only. The helicopter has its own HUD item.
- **Cover from the runner's game:** the server keeps `runnerCovered` from `cnr_cover { covered }`, and only accepts it from the game that owns the runner's car:
  - the runner, in a normal round
  - in practice as a cop, the practising player, whose game owns the AI runner
- **Practice rounds:** the helicopter works there too.

### Client: cover check on the runner's car
- **Who runs it:** the game that owns the runner's car, which is the runner's own car, or the AI runner (`ai.runnerObject()`) in practice.
- **How:** it runs `shelter.roofed` from 1.5 m above the car's position every 0.25 s, with `shelter.step` (two checks to switch, both directions). It sends `cnr_cover { covered }` to the server when the state changes, and once at release.
- **Separate state:** this is a second shelter state, apart from the camera one the rain uses.

### Client: HUD
- **The chase line gets a helicopter item for both roles,** built in `hud.lua` from the last `heli` message plus a local countdown:

  | Phase | Text |
  |---|---|
  | arriving | `HELICOPTER IN 0:45` |
  | up, tracking | `HELICOPTER 1:30` (time up left) |
  | up, searching | `HELICOPTER SEARCHING` |
  | refuelling | `HELICOPTER REFUELLING 0:50` |
  | grounded | `HELICOPTER GROUNDED (FOG)` |

- **Icon:** one from the game's set. The countdown is in the mono font.
- **Off:** with the helicopter switched off there's no item.
- **How to play:**
  - The cop and runner tabs drop the "last position every 30 s" lines.
  - They explain the helicopter: arrival, time up and refuel from the rules, grounded weathers, hiding under cover.
  - They explain the hiding: cops see you on the minimap and by name tag only while spotted.
  - With sight Off, the "last position every …" line becomes: cops see the runner on the minimap all round.

### Client: hiding the runner (on cops' games only)
- **Name tag:** while `shown` is false, set `MPVehicleGE.getVehicles()[key].hideNametag = true` on the runner's car key. Use the key from `cnr_roundCars` that `traffic.roundCar(runnerId)` already gives. Clear it when shown, at round end and on leave. Re-assert it about once a second, because BeamMP can rebuild its vehicle table.
- **Minimap:**
  - **The wrap is lazy.** `ui_apps_minimap_vehicles` only exists after the Navigation app loads it, and it can be reloaded.
    - So about once a second, while our extension is loaded, wrap its `drawOtherVehicles` if the minimap extension exists and the function isn't our wrapper yet.
    - On unload, put the original back only if our wrapper is still in place.
  - While the runner is hidden, the wrapper swaps the global `activeVehiclesIterator` for a filtered one that skips the runner's game vehicle id. It calls the original inside `pcall`, then puts the global back.
  - When not hiding, it calls the original unchanged.
- **The runner's own game** never hides anything. Cops' cars and traffic are unaffected.
- **Practice as a cop:** the AI runner has no name tag (BeamMP draws none for local cars). It is hidden from the minimap by its game id (`ai.runnerObject():getID()`) under the same rule.

### Client: searchlight
- **When:** while the helicopter is `tracking` and it is night (`sky.isNight()`), each game shows a searchlight.
- **What:** a `SpotLight` object `cnr_heli_light`, not saved with the level (`runnerObject()` on cops' games, the own car on the runner's). It hovers 40 m above the car with a slight drift. The beam keeps on the car with smooth operator-style corrections: it lags a sudden move then settles (near-critically damped), nudges every 1.5-3 s within 1 m, and has a slight tremor.
- **Flying in:** when tracking starts after `arriving` or `refuelling`, the light starts 300 m away at 60 m up in a random heading and eases out to the hover point over 8 s. Its aim starts 15 m off the car and sweeps onto it.
- **Flying away:** on `tracking` to `refuelling` the light stays 8 s, flies 300 m away climbing to 60 m (ease-in), its aim drifts off the car, and it fades to nothing over the last 3 s.
- **Under cover:** on `tracking` to `searching` the light is deleted at once. On `searching` to `tracking` it comes back at the hover point, fades in over 1 s, and its aim starts 8 m off the car and swings back on. When night ends it fades out over 1.5 s.
- **Removed when:** the round ends, on cancel, on leaving or on a map change (at once), or when an animation above finishes.
- **Values:** cone 8 and 16 degrees, brightness 80, range about 120 m, colour warm white.

## Tests
- **`cnr/helicopter.lua`:**
  - phases and their timers (arrival, up, refuel, up again)
  - time up counts while searching
  - grounded for storm, fog and snow, and never arriving
  - the re-find time is 5 s, and 10 s in rain
  - an arrival of 0 means up at release
  - a refuel of 0 means it stays up with no countdown
- **Round:**
  - no periodic `lastSeen` any more, also with the helicopter off and with sight Off
  - one `lastSeen` when `tracked` goes false
  - no `lastSeen` when the helicopter loses the runner while a cop sees them, or when sight is lost while the helicopter tracks
  - while tracking, `live` comes every `sightLiveIntervalSeconds`, and only once per tick when a cop also sees the runner
  - `heli` goes to everyone on each phase change and in setup
  - `runnerShown`:
    - is true in prep and the countdown, and false at the head start
    - is always true with sight Off
    - goes to cops on changes from sight and from the helicopter, and not to the runner
  - `cnr_cover` from anyone but the runner's owner is ignored
  - the runner gets `cnr_nearestCop` every 30 s while running
  - the run record has `helicopter = true` only when it flew
- **Config:**
  - the helicopter keys' defaults and validation, with a time up of 0 rejected
  - `lastSeenIntervalSeconds` is retired
- **Client:**
  - **Cover:** sent only by the runner's owner, and on change only.
  - **HUD:** the helicopter text for each phase, with the countdown going down between messages.
  - **Name tag:** the runner's `hideNametag` is set while not shown, cleared when shown and at round end.
  - **Minimap:**
    - The wrapper skips the runner's id while hidden and passes everything through otherwise.
    - The global iterator is restored even when the original throws.
    - The wrap is applied once the minimap extension appears, and again after it reloads.
    - In practice as a cop, the AI runner's id is the one skipped.
  - **Searchlight:** created at night while tracking, never by day, removed on each exit path.

## In-game check
1. **Arrival:** in a clear round, the HUD counts down "HELICOPTER IN", then "HELICOPTER 2:00". Cops get live routes while the runner drives in the open.
2. **Cover:** drive into a tunnel. You get "HELICOPTER SEARCHING", and cops get one last-seen route to the tunnel mouth. Come out, and it's tracking again after 5 s.
3. **Refuel:** after the time up, "HELICOPTER REFUELLING" counts down, and cops get nothing but their own sight.
4. **Weather:** a fog round shows "HELICOPTER GROUNDED (FOG)" all round, and no pings arrive.
5. **Hiding:** as a cop, the runner shows in prep and disappears from your minimap at the head start. After that they have no name tag and aren't on your minimap until you see them or the helicopter tracks them. With the sight range Off, they show all round.
6. **Searchlight at night:** it follows the runner's car while tracking and is gone afterwards. Every player sees it.
7. **Wrapper safety:** the minimap still works normally outside rounds.

## Calls made (not discussed, easy to change)
- **Defaults:** arrival 60 s, time up 2 min, refuel 90 s.
- **Re-find times:** 5 s in the open, 10 s in rain.
- **The runner's SPOTTED / HIDDEN tag** stays about cop sight. The helicopter has its own HUD item.
- **Cover is reported** by the game that owns the runner's car, using the roof check from 1.5 m above it.
- **Searchlight:** hovers 40 m above the car with a slight drift; the beam keeps on the car with smooth operator-style corrections (nudges every 1.5-3 s); flies in over 8 s from 300 m, flies away over 8 s with a fade, is cut at once under cover and fades in over 1 s when re-found.
- **Earth:** the helicopter flies, the name tag is hidden, and there's no minimap hiding.
- **Pings:** one last-seen ping per loss of the runner by both sight and the helicopter. It replaces the two separate pings, so neither cuts into the other's live stream.
- **Settings:** time up must be more than 0, and a refuel of 0 means the helicopter stays up.
- **Nearest cop:** the runner's readout keeps updating every 30 s, since the periodic ping that refreshed it is gone.
- **Run record:** runs note whether the helicopter flew. There's no leaderboard filter for it yet.
- **Practice as a cop:** the AI runner is hidden from the minimap too.

## Left to the builder
- `SpotLight` field names and values, checked in game.
- The panel group's step sizes.
- The HUD icon.
- Where the helicopter state lives in `round.lua`: a field holding a `helicopter` instance, ticked from `Round:tick`.
