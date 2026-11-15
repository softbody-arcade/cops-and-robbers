# BeamMP Cops and Robbers — Design

## Intent

A friend group plays cops and robbers on a BeamMP server that one of them hosts.
Today the rules are enforced by agreement, which leads to arguments ("was he
caught?", "you reset illegally"). This mod makes the server enforce the group's
house rules, with every number configurable, so the game itself is the referee.

## Goals

- Enforce the group's rules (below) automatically during a round.
- Every timing/distance value lives in one config file on the server.
- Zero setup for players: anything that runs in their game is auto-downloaded by BeamMP on join.
- Persistent leaderboard of runner survival times.

## Non-goals

- Win conditions for the runner (no escape zones, no time limit). The score is survival time.
- Multiple runners per round. Exactly one runner; everyone else is a cop.
- Custom HTML UI apps. On-screen feedback uses the game's built-in message toasts.
- Admin/permission system. Any player can run any command (trusted friend group).
- Anti-cheat against a determined player editing the client mod. The server is authoritative
  on what matters (catch, timing, reset legality) but the group is trusted.

## Anti-goals

- Two players' games disagreeing about whether the runner is caught.
- Players needing to install anything manually.
- A round that gets stuck with no way out (there must always be `/cnr stop`).

## The rules (as decided by the group)

1. **Vehicle:** each round a random vehicle + config is picked; everyone (runner and cops) drives that exact vehicle and config. Any vehicle can be picked (see "Vehicle pool").
2. **Start flow (revised 2026-11-14):** `/cnr start <name>` gives everyone the round car, frozen in place (prep,
   no timer). During prep only paint may change (parts/tuning changes are reverted). `/cnr go` starts a
   `runnerCountdownSeconds` (default 3) countdown, then the runner is released and cops stay frozen for
   `headStartSeconds`. `/cnr color <#hex|off>` stores a per-player primary color applied to every round car.
3. **Resets** are only allowed when one of these holds:
   - **Gas station:** the vehicle is within a gas station area and fully stopped.
   - **Wait:** anywhere, after staying stopped for `resetWaitSeconds` continuously. Moving restarts the countdown.
   - **Far cop:** a cop that is at least `copResetMinDistanceMeters` from the runner may reset anywhere, immediately.
   This applies to cops and runner alike (except the far-cop rule, cops only).

   **What an allowed reset does:**
   - **Runner:** repair in place only. No move, no rewind. If the runner drives into water or gets
     stuck, that's their problem: the cops catch them, or someone uses `/cnr stop`.
   - **Cop:** repair and move to the nearest road node (nearest to where the car is now, not near
     the runner), facing along the road. The far-cop rule only changes *when* a cop may reset, not where they end up.
   - Rewind/recover is never available during a round.
4. **Caught:** the runner is caught when held in place for `catchHoldSeconds`: runner speed below
   `catchMaxSpeedKmh` while at least one cop is within `catchRadiusMeters` (vehicle center to center),
   continuously. If either condition breaks, the hold timer resets to zero.
5. **Survival clock:** starts when the head start ends and cops are released, and stops at the catch.
   No catch can happen during the head start. The head start does not count toward the score.
5b. **Crash penalty (added 2026-11-14):** a cop losing `crashSpeedLossKmh` (default 50) within 0.5 s is frozen
   for `crashPenaltySeconds` (default 10). Resets are blocked during the penalty and the wait rule starts after it.
   A penalized cop does not count toward a catch. Runner crashes are not penalized. When another car was within
   15 m before the crash, only the car driving into the other is at fault (comparing closing speeds the tick before).
   `/cnr test runner` (you blue runner, AI cops green/red chase you) and `/cnr test cop` (you green cop, AI blue
   runner flees, AI red partner cop) are practice rounds against BeamNG AI, never recorded. AI vehicles belong to the
   issuer and need MaxCars >= 3.
6. **Round end:** a catch ends the round. Everyone gets a message with the runner's name and survival
   time. Optionally the runner's vehicle explodes (`explodeOnCatch`, default off).
7. **Choosing the runner:** players pick manually via command, or ask for a random pick.

## Edge cases (proposed by Claude, accepted without objection)

- Runner disconnects: round ends, time counts up to the disconnect, recorded as a run with end reason `disconnect`.
- Someone joins mid-round: becomes a cop, gets the round vehicle, spawned near the runner like the others (no head-start freeze).
- A cop leaves: round continues.
- Runner gets stuck or falls off the map: only repair-in-place resets, by the group's decision. `/cnr stop` is the way out.
- No distance limit on how far ahead the runner may get.

## Approaches considered

- **A. Server plugin + auto-distributed client mod (chosen).** Server owns round state, timers, catch
  detection (from the vehicle positions BeamMP already relays), reset authorization and the leaderboard.
  The client mod does what only the game can: spawn the round vehicle, place and freeze cops, block the
  reset/vehicle-selector keys unless the server authorizes, show countdowns. Cost: two codebases to keep
  in sync over a small event protocol.
- **B. Server plugin only.** Server announces the vehicle in chat, rejects wrong spawns, punishes illegal
  resets after the fact (e.g. delete vehicle). No prevention, no countdowns, cops place themselves.
  Rejected: blocking resets and automatic setup are most of what makes rules feel enforced.
- **C. Client-side logic.** Each game decides catches/resets itself. Rejected: games can disagree (anti-goal).

## Architecture

```
Resources/
  Server/CopsAndRobbers/      server plugin (Lua, BeamMP server 3.x API)
    main.lua                  events, commands, round state machine
    rules.lua                 pure rule logic (no MP.* calls) — unit tested
    config.json               all tunables
    data/leaderboard.json     persistent runs
    data/stations/<map>.json  gas station positions per map (auto-detected + manual)
  Client/CopsAndRobbers.zip   client mod, auto-downloaded by BeamMP
    scripts/CopsAndRobbers/modScript.lua
    lua/ge/extensions/copsAndRobbers.lua
```

Server and client talk via `MP.TriggerClientEvent[Json]` / `TriggerServerEvent` + `AddEventHandler`, JSON payloads.

### Server responsibilities

- **Round state machine:** `idle → headstart → running → idle`.
- **Position polling:** every ~250 ms during a round, read each relevant vehicle with `MP.GetPositionRaw`
  (position + velocity). Used for catch detection, stillness, distances, gas-station checks.
- **Catch detection:** per rule 4; broadcasts hold progress (0–1) so clients can show "CAUGHT IN 3.2s".
- **Reset authorization:** client asks "may I reset?"; server evaluates rule 3 with its own position data
  and the station list; replies allow/deny + reason ("stay still 4s more", "get to a gas station").
  Wait-timer state lives on the server. Defense in depth: `onVehicleReset` for a reset that was not
  authorized is logged and announced in chat (no automatic punishment in v1).
- **Vehicle enforcement:** during a round, `onVehicleSpawn`/`onVehicleEdited` are cancelled unless they match
  the round vehicle (model + config) and the player has no other vehicle; extra vehicles are removed.
- **Leaderboard:** append each finished run to `leaderboard.json`; `/cnr top` shows best time per player.
  Shown in chat after every round.
- **Stations:** per map, stored in `data/stations/<map>.json`. Seeded from the first client that reports
  auto-detected stations for that map; extended with `/cnr addstation` (current position of the issuing
  player's vehicle) and `/cnr removestation` (nearest within radius).

### Client responsibilities

- **Vehicle pick:** the client of the player who issues `/cnr start` picks a random model + config from
  its local vehicle list and sends it to the server, which broadcasts it. Pool = official game vehicles
  by default; `includeModVehicles` widens it to installed mods (risk: others may not have them).
- **Round setup:** replace own vehicle with the round vehicle. Runner: in place. Cops: placed on a road
  node between `copSpawnMinMeters` and `copSpawnMaxMeters` from the runner, facing along the road, spread
  so they don't overlap. Cops frozen during head start with an on-screen countdown; runner sees "GO!".
- **Input lock:** during a round, disable reset/recover/reload actions and the vehicle/parts selectors.
  The reset key instead sends a reset request; on allow, the client performs the reset (runner: repair
  in place; cop: repair + move to nearest road node). The server knows a cop reset can jump position
  and must not count that as a broken catch hold or a wait-timer violation.
- **Gas-station detection:** on map load, read the level's facility data for gas/charging stations and
  report positions to the server.
- **Feedback:** toasts for countdowns, reset status, catch progress, round result. Explode on catch if enabled.

### Commands (chat, intercepted by `onChatMessage`, any player)

| Command | Effect |
|---|---|
| `/cnr start <name\|random>` | start a round with that runner |
| `/cnr stop` | cancel current round (not recorded) |
| `/cnr top` | leaderboard (best per player) |
| `/cnr addstation` / `/cnr removestation` | edit this map's gas stations |
| `/cnr config` | show current config values |
| `/cnr reload` | reload config.json |
| `/cnr help` | list commands |

### Config (`config.json`, defaults)

```json
{
  "headStartSeconds": 7,
  "resetWaitSeconds": 7,
  "catchHoldSeconds": 7,
  "catchRadiusMeters": 10,
  "catchMaxSpeedKmh": 3,
  "stillMaxSpeedKmh": 1,
  "copResetMinDistanceMeters": 1000,
  "gasStationRadiusMeters": 25,
  "copSpawnMinMeters": 50,
  "copSpawnMaxMeters": 150,
  "explodeOnCatch": false,
  "includeModVehicles": false
}
```

### Leaderboard record

`{ player, survivedSeconds, map, model, config, releasedAt, endedAt, endReason: "caught"|"disconnect" }`.
`survivedSeconds = endedAt - releasedAt`.
Cancelled rounds are not recorded.

## Constraints

- Server: BeamMP server 3.x Lua plugin API. Host runs the server themselves (location TBD by builder/host).
- Maps played: West Coast USA (main), Italy, BeamNG.Earth (mod map with fuel/charge icons on the minimap).
- Game version on host's client: 0.39.x.

## Left to the builder

- Exact BeamNG/BeamMP API calls (facility lookup, freeze, input action filtering, road-node placement,
  explode), verified against current game/BeamMP source.
- Event protocol names and payload shapes.
- Polling interval and smoothing.
- Test approach for `rules.lua` (plain `lua`/`luajit` available locally; `busted` not installed).
- Packaging script for the client zip.

## BeamNG.Earth (added 2026-11-15)

BeamNG.Earth gives every client its own floating origin (rebases per player), so raw BeamMP positions from different
players are not comparable, and its gas stations are generated at runtime (no facilities files). On map
`beamng_earth` the server switches to geo mode and tells clients via `cnr_mode {geo}`:
- clients report their car (and AI cars) as lat/lon/h + velocity via `cnr_geo` 4x/s using `beamngEarth_api.toGeo`,
  skipping frames where `api.rebasing()`; the server converts to one WGS84 ENU frame and ignores reports older than 2 s;
- positions sent to clients (cop placement, last seen, rejoin) are lat/lon, converted with `api.toGame`;
- last-seen pings set BeamNG.Earth's GPS destination (`api.gpsSet`, "Runner last seen") and the status line shows
  `api.gps().remaining` as the distance by road (straight line while the route is planning); cleared at round end;
- clients look up real gas stations with `api.places(..., {categories={'gas_station'}})` every 60 s or 1 km and the
  server merges them (50 m dedupe) into `data/stations/beamng_earth.json` as lat/lon.
One mod for all maps; a client on Earth without API v1 gets a warning.

## Reset buttons (revised 2026-11-15)

All of the game's reset/recovery buttons stay usable during a round and are routed through the round's reset rules
(the game's own handlers are intercepted: global `resetGameplay`, `spawn.teleportToLastRoad`, and the vehicle-side
`recovery.startRecovering`/`stopRecovering`/`loadHome`). When a reset is not allowed the button shows the reason.
- Reset vehicle, Recover/rewind (both): repair in place, upright, for runner and cops.
- Load home, Recover to last road: runner repairs in place; cops repair and move to the nearest road.
Everything else that resets, teleports or edits a vehicle is locked (the game's `competitive` action template plus
consoles, Lua reload, walking/photo mode and the big map's teleport). The server announces any jump not explained by
an allowed reset as "<name> teleported".
