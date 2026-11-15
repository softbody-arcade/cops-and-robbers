# Leaderboard app and player stats (short design, part of 1.7.0)

## Intent
Everyone can see who survives longest, who catches most, and per-player stats, including the new sight-based ones, in a clickable app. The user approved the proposal. The current leaderboard can be wiped: "this will be from scratch".

## Data (from scratch)
- **Format:** `data/leaderboard.json` becomes `{ format = 2, runs = [...] }`.
  - On load, a file without `format = 2` is moved aside to `data/leaderboard-1.6.json` (never deleted) and an empty board starts.
  - A broken file is moved aside as before.
- **Run record:** the existing fields (player, key, survivedSeconds, model, config, map, endedAt, endReason, catchers, catcherKeys), plus:
  - `cops`: keys of every human cop who took part. Names come from the latest run, like today.
  - `sightedBy`: keys of cops who saw the runner at least once.
  - `hiddenSeconds`: chase seconds while no cop had sight.
  - `lostCount`: how often all cops lost sight.
  - `chaseSeconds`: equal to survivedSeconds.
  - When sight is off (`sightMaxMeters = 0`), `hiddenSeconds` and `lostCount` are left out and their stats show "–".
- **Practice rounds** are never recorded, as today.

## Stats (computed on the server from runs, per map filter)
- **Runners:** each player's best survival, with the car and the map. `/cnr top` and the result card's top 3 keep using this.
- **Cops:** each player's catches, credited by `catcherKeys`.
- **Players:**
  - **runs:** runs as runner
  - **best / average:** survival time as runner
  - **escapes:** runs ending `escaped`
  - **catches**
  - **assists:** caught runs where the player is in `sightedBy` but not in `catcherKeys`
  - **hidden %:** the sum of hiddenSeconds over the sum of chaseSeconds, for runs that have it
  - **lost them:** the sum of lostCount
- **Map filter:** "this map" (default), "all maps", or any map in the runs.

## App
- **"Cops and Robbers Leaderboard":** a Vue app, clickable and not auto-placed, which collapses like the panel. It has three tabs (RUNNERS, COPS, PLAYERS) and a map dropdown.
  - Clicking a player row shows all of that player's stats.
  - It shows "Not on a Cops and Robbers server" when not connected.
- **Server:**
  - Event `cnr_board {action = "open" | "close" | "filter", map}`. Subscribers get `cnr_boardState {map, maps, filter, runners, cops, players}` on open, on filter change, and after each recorded run. Each player has their own filter.
- **Client:**
  - `copsAndRobbers.board(msg)` forwards to the server.
  - `cnr_boardState` → `CnRBoard`. Each runner row's model key is replaced with the car's display name (`game.carName`).
  - It resets on mode/leave, like the panel.

## Approaches
- **Separate app (chosen):** anyone can open it. The control panel stays for whoever runs the game.
- **A tab in the panel:** rejected, because the panel is for one person.

## Left to the builder
- Styling.
- Column choice per tab at 440 px width.
- The detail view's layout.
