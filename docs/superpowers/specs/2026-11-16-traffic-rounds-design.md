# Traffic during rounds (design)

## Intent and why
Today the game's AI traffic is off during a round: the traffic toggles are locked, and the server refuses or removes every car of a round player except the round car. The user wants traffic on the roads during real rounds for **more fun, realism and difficulty**: the runner has to weave through it, cops have to get through it without ploughing into it, and the map stops feeling empty.

## Goals
- **Every player's game runs a few traffic cars around itself** during a round, so there is traffic wherever anyone drives (user: "everyone a few, default 5 per player, configurable").
- A setting `trafficPerPlayer`, default 5, 0 = off, editable in the panel like every other setting.
- Traffic cars pass the vehicle rule, but never count as a player's car: catching, resets, teleport checks, the parts check and sight keep using only the players' own round cars.
- **Crash penalties take traffic into account through the existing fault rule** (user picked this): a cop who drives into a traffic car gets the penalty, the same as hitting a wall or rear-ending the runner; a cop who gets hit by a traffic car does not.
- Built on **the game's own traffic system** (`gameplay_traffic`), driven by our client mod (user picked this approach).
- **Normal maps only in this version.** On BeamNG.Earth traffic stays off and the panel says so (user picked this; see Constraints for why).

## Non-goals
- **Traffic on BeamNG.Earth.** A follow-up, after the group has played and tuned traffic on normal maps. No traffic positions travel as latitude/longitude in this version.
- **Parked cars** (the game's parking system). Only moving traffic. Parked cars would share the same `MaxCars` cap and cost every player's game almost as much as traffic; the user decided against them.
- **Traffic blocking line of sight.** Sight still ignores vehicles (`castRayStatic`).
- **Choosing traffic models or density per map**, or traffic that uses the round car to help the runner hide.
- **Crash penalties for the runner.** Unchanged: only cops get them.
- **Players' own traffic during a round.** The traffic toggles stay locked for players; only the mod spawns traffic in a round. The lobby is unchanged (players may still switch traffic on between rounds).
- **Traffic stats per player** (for example crash penalties caused by traffic per cop). The user picked the leaderboard filter and the crash cause only.
- **Our own night headlight rule for traffic.** At night traffic keeps the game's behaviour: headlights on in the game's solar night window and in tunnels, and the game respawns traffic less often at night, so it thins out. The user wants to tune this after playing ("we can always tune when playing"). Bad weather is the one exception (see Weather and night).

## Anti-goals (a failure even if it technically works)
- A cop penalised for being hit by traffic.
- Catching, resets, the teleport check, sight or the crash detector following a **traffic car instead of the player's own car**.
- A false notice because of traffic: "changed parts during the round", "reset illegally" or "teleported".
- **Our server removing traffic mid-round** (cars vanishing in front of players), or removing or replacing anyone's round car because of traffic.
- A traffic car with emergency lights, or traffic police chasing players. Every car with lights must be a cop.
- **A round that can't start or stalls because traffic failed to spawn.** Traffic is best effort.
- Traffic left over after the round, or lobby traffic surviving into a round.
- A traffic car some players can't see (a local-only mod model).

## Constraints (found in the code and in BeamMP)
- **The BeamMP server can't spawn cars.** Every traffic car is spawned by a player's game and BeamMP syncs it like any car: everyone sees it, it counts against that player's `MaxCars`, and it goes through `onVehicleSpawn` / `onVehicleEdited`. Returning 1 from an edit **deletes** the car. (Checked in BeamMP's `MPVehicleGE.lua`: `onVehicleSpawned` sends every locally spawned vehicle to the server; nothing marks traffic.)
- **The game keeps traffic only around its owner.** `gameplay_traffic` respawns cars that fall behind at spots ahead of the focus vehicle (the owner's car), out of the owner's sight. Other players may see such a car disappear.
- **The game slips special vehicles into traffic.** `gameplay_police` registers a provider that adds police cars when the traffic options ask for police (`options.police`), and `gameplay_taxi` adds taxis. The default traffic group already filters `Config Type` Police out.
- **BeamMP draws the owner's name over every car the owner has**, traffic included. It skips a car whose `MPVehicleGE.getVehicles()[key].hideNametag` is set.
- **What breaks today if traffic simply came through:**
  - `vehicleAllowed` (`server/CopsAndRobbers/main.lua`) refuses any spawn by a round player when one car already exists, and any model other than the round car.
  - `cnrOnVehicleSpawn` and `cnrOnVehicleEdited` set `activeVid[pid]` to whatever car spawned or changed, so a traffic car would become "the player's car" for every server check.
  - `cnrOnVehicleEdited` runs `checkParts` on any car of a round player, so a traffic car changing would announce "changed parts".
  - `cnrOnMyVehicle` removes **every other car** of the player each time `cnr_myVehicle` arrives. That happens at round setup, but also after a colour repaint in prep and after every evolving-mode Apply rebuild, so it would delete traffic mid-round.
  - `crash.atFault` only sees the players' cars, so today a cop who hits traffic or is hit by it is treated like a solo crash (at fault).
  - The client's `runnerObject()` falls back to *any* car of the runner when the runner's active vehicle isn't found, which could pick one of the runner's traffic cars for sight.
- **Trust:** the server can't tell a traffic car from a second car a player spawned by hand. Like the panel (the server doesn't check who uses it), it trusts the player's game, but caps how many extra cars a player may have.
- **BeamNG.Earth manages any running traffic itself** (`mods/unpacked/beamng_earth/lua/ge/extensions/beamngEarth/navgraph.lua`), whoever started it:
  - `guard()` moves any traffic car that has stood still for 45 s and is 40 m or more from the player, so traffic held still through a long prep would be shuffled around.
  - `onTeleport()` hides all traffic (`setActiveAmount(0)`) until the new road graph arrives, and round setup often moves cops kilometres away.
  - The new road graph arrives after the round car is placed, so a moved cop's traffic would often find no roads.
  - `checkRegion()` sets traffic up again with the player's own level-start amount and police choice after a region change, which could bring police cars back.

  Working around that means depending on BeamNG.Earth internals beyond its mod API v1, which the project has avoided. Hence off on BeamNG.Earth for now. (Also: every player has their own coordinate origin there, so traffic positions would have to travel as latitude/longitude.)
- **Night and weather rounds (2.2.0, merged before this was built)** act on every car in each player's game, traffic included:
  - The sky is locked through `core_environment` during a round, and the round's time can run (`clockSpeed`), so sunrise or sunset can happen mid-round. The game's traffic reads the time from `core_environment.getTimeOfDay()`, so its night headlights follow the round's clock.
  - Weather grip swaps the game's ground models (`copsAndRobbers/surfaces.lua`). The game's vehicle AI reads grip from the ground model (`obj:getStaticFrictionCoef()` in `lua/vehicle/ai.lua`), so traffic slows down on wet roads and snow by itself.
  - Gusty ground wind is sent to every car through `be:queueAllObjectLua("obj:setWind(...)")` (`copsAndRobbers/sky.lua`, `wind.lua`), traffic included. Every game computes the same seeded gusts, so a traffic car is pushed the same way in its owner's game and everyone else's. While the sky is locked the game doesn't give newly spawned cars wind itself; our 0.25 s updates do.
  - The game never switches traffic headlights on in daytime fog, and fog is now a round type (fog density 25), so unlit traffic would be nearly invisible and cops would collect "(traffic)" penalties for cars they couldn't see.
  - Practice AI cars get headlights from our mod at night (`ai.lightsOn(sky.isNight())`).
  - Recorded runs carry a `sky` field that the Rounds list row and detail show; the panel has a Sky settings group that shows "Not available on BeamNG.Earth yet" instead of its settings on BeamNG.Earth.
- Code style and platform as before: client Lua stays LuaJIT / Lua 5.1 compatible, the server runs Lua 5.3, `cnr/*.lua` modules stay pure (no `MP` API), no chat messages or pop-ups (everything through the apps), no code comments.

## Approaches
1. **The game's own traffic system, run by our mod (picked).** After a player's round car is placed, the server tells that game how many traffic cars to spawn; our client mod starts `gameplay_traffic` with that amount and a vehicle group without police or emergency vehicles, holds it still until GO and deletes it at round end. The game reports which cars are its traffic; the server lets them through, keeps them out of every player check, and reads their positions for the fault rule. The game does the hard part for free (keeping traffic around each player, lanes, traffic lights). Cost: we depend on game internals that an update can change (goes into `docs/DEPENDENCIES.md` with a check), and others may see a traffic car disappear when the owner's game moves it.
2. **Our own AI cars, like the practice cars.** Spawn N cars in AI traffic mode and move them ourselves when they fall behind their player. Full control and no dependence on `gameplay_traffic`, but we'd rebuild the respawning the game already does well: much more code and tests, and probably worse traffic.
3. **Just unlock the toggles and let extra cars through.** Dropped: no server-wide amount, no control over police, and traffic would drive into frozen cars during prep.

Who runs the traffic was decided separately: **every player runs a few** (picked) rather than the runner running all of it. Traffic is everywhere and the load is spread; the cost is that traffic near the chase grows with the player count, and every game simulates every traffic car.

## Design

### The setting
- `trafficPerPlayer`: whole number, default 5, minimum 0, 0 = off. Saved in `config.json` like the rest, validated in `cnr/config.lua`, locked during a round.
- **Cap from `MaxCars`:** the server reads `MP.Get(MP.Settings.MaxCars)` and spawns at most `MaxCars − 1` traffic cars per player in a real round, `MaxCars − 3` for the practice issuer (the two AI cars count), never below 0. The setting itself is not changed; the cap applies per round.
- **BeamNG.Earth (geo mode):** the effective traffic is 0, whatever the setting says. The setting stays editable (it applies when the server runs a normal map).
- With an effective traffic of 0 (setting 0, `MaxCars` too low, or BeamNG.Earth) everything behaves exactly as today.

### Lifecycle in each player's game
1. **Round setup (prep):** the player's round car is placed as today and `cnr_myVehicle` reaches the server. Only after the server has done its clean-up for that car does it tell the game to spawn its traffic, with the capped count. (Otherwise the clean-up could delete traffic that spawned first.) Before spawning, the game stops any traffic the player had running from the lobby.
2. **Spawn:** the game starts `gameplay_traffic` with that many cars around its own round car: official vehicles only (so every player can see every traffic car), no police and nothing with emergency lights, no pursuits or other traffic events aimed at players. All spawned cars are active (no hidden pooled cars).
3. **Held still until GO:** traffic stands still through prep, Apply and the countdown, and starts driving when the runner is released ("GO! RUN!"). Prep has no time limit, and moving traffic would drive into the frozen round cars. During the head start traffic drives while cops are still frozen; that's accepted (no crash penalties are checked before the chase). **Held traffic still follows the headlight rules below** (night, tunnels, bad weather), so a night or fog round doesn't start with unlit cars standing on the road; if the way traffic is held stops the game's own night check, the mod sets the lights itself with the same `sky.isNight()` the practice AI cars use.
4. **Report:** the game tells the server which server vehicle ids are its traffic, and again whenever that changes (a traffic car replaced or removed).
5. **Round end, Cancel, leaving the server, the issuer's practice ending:** the game deletes its traffic. A player who disconnects loses their cars through BeamMP anyway.
6. **Late joiners and reconnects** become cops as today; their game spawns its traffic after their round car is placed, and it starts driving at once if the runner is already released.
7. **Traffic failing to spawn** (no road graph, `MaxCars` refusals, a game error) never blocks the round. The player gets one personal notice ("Traffic could not spawn", or how many did), and the round goes on.

### Weather and night (agreed after night and weather rounds were merged)
- **Bad weather: headlights on.** When the round's weather is rain, storm, fog or snow, the mod switches every traffic car's headlights on (`electrics.setLightsState(1)`) and keeps them on: it re-sends the command every second, because the game turns a car's lights off when it moves it to a new spot. Held traffic too. Clear and cloudy rounds, and rounds with the map's own weather, leave the lights to the game.
- **Night:** the game's own rule, as above. It follows the round's clock, including a sunrise or sunset mid-round.
- **Grip and wind:** nothing to do. Traffic slows on wet roads and snow by itself, and the gusts push it in every game alike.

### Which cars are traffic, on the server
- The player's own round car is the one named by `cnr_myVehicle` (`activeVid`). During a round with traffic on, **a spawn or edit never moves `activeVid` to another car** once `cnr_myVehicle` has named one.
- Traffic is what the game reports as traffic, within the cap. The server keeps that set per player for the round and forgets it at round end.
- **Vehicle rule (`vehicleAllowed`) in a round with traffic on:** the round car rule is unchanged for the player's own car. Extra cars are allowed, any model, up to the cap. One beyond the cap is refused as today. With traffic off, today's rule applies unchanged.
- **Edits of traffic cars** are always allowed (never return 1, which would delete them) and **skip `checkParts`**.
- **Clean-up on `cnr_myVehicle`:** still removes every other car of the player, **except the player's traffic**. At round setup the traffic doesn't exist yet (see Lifecycle), so lobby leftovers still go; after a repaint or an Apply rebuild the traffic survives. (Settled in the plan: once the go-ahead is out, the clean-up no longer runs for that player, because lobby leftovers were removed before it and the vehicle rule caps extra cars at the traffic count, so every extra car is traffic, reported or not.)
- **A missing round car never hands over to traffic:** if the player's own car is gone mid-round, the server tracks no car for them rather than falling back to another car of theirs.
- Resets of traffic cars are ignored as today (`cnrOnVehicleReset` only looks at the player's own car).

### Crash penalties
- The fault rule (`crash.atFault`) gets **every traffic car's position and velocity** next to the other players' cars, from the previous tick like today. Nothing else changes: the nearest car within 15 m decides, and whoever drove toward the other harder is at fault.
  - Cop drives into a traffic car: at fault, penalty.
  - Traffic drives into the cop: not at fault, no penalty.
  - Cop crashes with no car within 15 m: at fault, as today.
- Applies to AI practice cops too.
- **Positions:** the server reads traffic cars with `MP.GetPositionRaw(owner, vid)` (normal maps only; there is no traffic on BeamNG.Earth).
- Traffic cars are passed to the round **only for the fault check**. They are never in the `cars` table that catching, resets, sight, the teleport check and the crash detector read.
- **Crash cause (user picked this):** the fault check knows whether the nearest car within 15 m was a traffic car, a player's car or none. When it was a traffic car, the live notice reads "Bob: crash penalty 10s (traffic)" and the timeline entry carries `cause = "traffic"`, so the Rounds tab shows the same line. Crashes with a player or with no car nearby read as today (my call: only traffic gets a cause, the others are what people already know). The `cause` field must survive the leaderboard save and reach the app; old timelines have none.

### Catching, resets, sight, teleports
Unchanged, and must stay player-only: catching needs a cop within the catch radius (traffic around the runner doesn't hold them), resets and the teleport check follow the player's own car, and sight casts against terrain and buildings only.

### Name tags and the runner's car on every game
- Every game hides BeamMP's name tag on **all traffic cars, its own and everyone else's**, so a name tag always means a player.
- Every game must also know exactly which car is the runner's round car, so `runnerObject()` never picks a traffic car for sight. The fallback to "any car of the runner" goes.
- For both, the server shares with all games which cars are round cars (or which are traffic) during a round. How is left to the builder. This includes a practice round: players in the lobby also see the practising player's traffic without name tags.

### Practice rounds
Practice uses the same setting: the issuer's game spawns traffic (capped at `MaxCars − 3`), held still until GO, deleted when the practice ends. Starting a real round ends the practice as today, and its traffic goes with it.

### Panel, How to play, HUD, leaderboard
- **Panel Settings tab:** a **Traffic** settings group of its own, next to the Sky group, with one common setting "Traffic", "N per player", off at 0. Its note line names the cost for the current player count, for example "5 each · 30 cars with 6 players", and when `MaxCars` caps it: "MaxCars is 4 on this server: 3 per player". On BeamNG.Earth the group shows the same "Not available on BeamNG.Earth yet" note the Sky group shows, instead of the setting (agreed: the panel's Sky-only group flag becomes a general not-on-Earth flag). The panel state needs the note from the server.
- **How to play (my call):** the **effective** traffic per player (after the `MaxCars` cap, 0 on BeamNG.Earth) joins the rules payload (`cnr/rules.lua`). When traffic is on, the Cop tab (crash line) says driving into traffic counts as a crash and being hit by it doesn't, and Basics mentions the traffic. When off, nothing about traffic shows.
- **HUD:** nothing new besides the personal notice when traffic can't spawn and the "(traffic)" on a crash penalty notice.
- **Leaderboard:**
  - Each run records the traffic per player it was played with (`traffic`, the effective number after the cap; absent or 0 means none). The Rounds list row shows "Traffic" next to the sky label, and the round's detail shows "Traffic: 5 per player" after the sky, for example "Gavril D-Series · Night · Rain · Traffic: 5 per player" (agreed). Old runs show nothing.
  - **Traffic filter (user picked this):** the filter row gets a third dropdown, All traffic / With traffic / No traffic, next to the map and car mode filters. It filters every tab (Runners, Cops, Players, Rounds) through the same filter the car mode uses (`cnr/leaderboard.lua`, the server's `boardState` and the app's filter message). Old runs count as "No traffic", because they were played without it. Default: All. The TODO's later conditions filter (night, bad weather) would add a fourth dropdown; folding the two into one "Conditions" filter is for when that is built.

### Docs
- **README:** the setting row (normal maps only, not on BeamNG.Earth yet); the install note that `MaxCars` needs room for 1 + the traffic cars (3 + traffic for practice); a tip that BeamMP's "Simplify remote vehicles" option lightens other players' traffic.
- **FEATURES:** traffic in round flow, the vehicle rule, the crash penalty fault rule and the "(traffic)" cause, the leaderboard's traffic filter and the traffic on each round, How to play, the settings table, and in the BeamNG.Earth section that traffic is off there for now; "AI traffic" stays in the locked list for players.
- **DEPENDENCIES:** the `gameplay_traffic` calls and options we use (spawn with amount and group, police off, delete, the traffic list, holding cars still), the group filter we rely on, the game's own traffic headlight rule (`gameplay/traffic/vehicle.lua`, night window and tunnels, lights off on a respawn), `MPVehicleGE.getVehicles()[key].hideNametag`, `MP.Get(MP.Settings.MaxCars)`, the fact that BeamMP syncs traffic as normal cars, and an update check: a practice round with traffic (cars spawn, stand still until GO, have no name tags, no police, a cop driving into one gets a penalty, all gone after the round), then one with Night and Fog (traffic lit while held and driving) and one with Rain (traffic slows on wet roads, gusts push it).

## Left to the builder
- The event names and payloads (the spawn go-ahead, the traffic report, sharing round cars or traffic with all games).
- How the game holds traffic still until GO (deactivating the traffic AI, freezing the cars, or both) and how it builds the police-free group, as long as the anti-goals hold.
- How traffic positions reach the round (a separate argument next to `cars` is the obvious shape).
- How the server treats a traffic spawn that arrives before the game has reported it (it is within the cap, so it is allowed; it just isn't in the traffic set yet).
- The version bump (2.3.0: night and weather rounds took 2.2.0).

## Testing
- **Server wiring (`tests/test_main.lua`):** with traffic on, extra spawns pass up to the cap and the next is refused; a traffic spawn or edit doesn't move `activeVid`; a traffic edit doesn't announce parts and isn't deleted; the clean-up after a repaint or rebuild spares traffic and still removes other extras; the cap follows `MaxCars` (real and practice); the effective traffic is 0 in geo mode; traffic off behaves exactly as today; traffic positions reach the fault check.
- **Rules (`tests/test_crash.lua`, `tests/test_round.lua`):** a cop driving into a traffic car is at fault, a cop hit by one is not; a traffic crash gives the "(traffic)" notice and `cause = "traffic"` on the timeline entry, other crashes don't; traffic never counts for catching, resets, sight or teleports.
- **Leaderboard (`tests/test_leaderboard.lua`):** runs record `traffic`; the traffic filter (all, with, without) works on every list; old runs without the field count as no traffic; the timeline `cause` survives a save and load.
- **Client (`tests/test_client.lua`):** traffic spawns only on the server's go-ahead, with the given count; it stays still until the runner's GO; it is deleted at round end, Cancel and on leaving; traffic ids are reported; name tags are hidden on traffic; `runnerObject()` returns the runner's round car, never a traffic car; in a rain, storm, fog or snow round traffic gets headlights (held too) and keeps them, in a clear round it gets none from us.
- **Config and panel:** `trafficPerPlayer` validates (whole number, at least 0) and shows in the panel's common settings.
- **In game** (added to the DEPENDENCIES quick check): a practice round with traffic, then a real round with two players.
