# Spectators and sitting out

## Why
- **Mid-round joiners get a broken game.** A player who joins mid-round is placed into the round as a cop. But BeamMP's client holds a new car back on every other game until that player's own car has been nearly stopped (under 2 m/s) for 3 s. In a chase that almost never happens, so nobody sees the joiner (2.9.5, LuckyBoi_i).
- **The user's decision:** "Players that join mid game should be spectators that are allowed to switch between cars (in this same fix add sitout with same mechanic) free cam is also allowed", then "let's just drop this and make them spectator as proposed".

## Design (approved 2026-11-17)
- **Who spectates:**
  - a player who joins while a round is running (a new name, not a rejoin)
  - every player who has **Sit out** on when a round is set up
- **Spectators are not in the round.** They have no role, and no rule counts them:
  - catching, sight, the nearest cop, the helicopter's guidance
  - resets and penalties
  - the leaderboard and records
  - the round's player count
- **Mid-round joiners:**
  - BeamMP already joins them without a car, in free camera.
  - The mod spawns no round car for them and sends no setup that places them.
  - They spectate until the round ends.
- **Sit out:**
  - **The toggle:** on the lobby card, next to Hide ("Sit out" while off, "Play" while on). It is stored per player on the server for the session; disconnecting clears it.
  - **Changing it:** works in the lobby. Once a round is set up (picking onward), a change applies to the next round.
  - **The runner:** a player sitting out is never picked as the runner.
  - **Enough players:** a round needs two players who aren't sitting out. Otherwise Start says why ("Need two players who aren't sitting out").
  - **Their car:** taken off the map for the round, so it isn't in the chase. When the round ends it is put back where it stood, with the same model and configuration.
- **Spectating:**
  - **The camera:** switches between every round player's car, the runner included. That's the user's choice, trusting spectators on voice chat.
  - **Free camera** is allowed.
  - **No blocks:** the round's blocks on switching vehicles and on free camera don't apply to spectators.
  - **No driving:** a spectator never controls another player's car.
- **HUD while spectating:**
  - "SPECTATING · <name>", with the watched player's name or "free camera"
  - the round clock and the runner's status line, as a cop would see them
  - no reset, penalty or role actions
- **After the round:** spectators are back in the lobby like everyone else, and play the next round unless Sit out is on.
- **Unchanged:**
  - **Rejoins:** a player who left mid-round and rejoins still resumes their role (`leftPlayers`, with 2.9.5's placement grace).
  - **Practice rounds:** unchanged.
  - **The lobby's online count:** includes spectators.

## Approaches
- **(a) Spectators outside `round.players`. Picked:** every existing rule already skips players who aren't in the round, so nothing has to learn about a new role.
- **(b) A "spectator" role inside `round.players`.** Rejected: every rule (catch, sight, crash, resets, helicopter, leaderboard) would need a new exception.
- **(c) Force-loading the joiner's car on every game.** Rejected by the user: it stutters each game, and the user chose spectating instead.

## Left to the builder
- **Taking a sitting-out player's car off the map and back:** for example, the player's own game saves model, config and pose, deletes the car at setup and respawns it at round end; BeamMP syncs both. It must survive a round that is cancelled, a map change and the player leaving.
- **The camera switching:** BeamMP lets a player enter a remote car to watch it. Cycle through the round players' cars with the game's own switch-vehicle keys, and keep free camera on its usual key.
- **The HUD layout,** within the existing kit.

## Tests
- **Server:**
  - a mid-round joiner gets no setup, no role and no place in `players`
  - a rejoin still resumes
  - Sit out excludes a player from the runner pick and the roles
  - Start is refused with fewer than two players who aren't sitting out
  - the toggle persists across rounds, is cleared on disconnect, and a change during a round applies next round
- **Client:**
  - a spectator's HUD and the lifted camera blocks
  - a sitting-out player's car is removed at setup and restored at round end, cancel and map change
  - nothing is left behind

## In-game check
- Join mid-round: you are spectating with free camera, can cycle through every car, the runner included, and nobody sees a phantom car.
- Sit out: your car disappears for the round and comes back where it stood.
- The round still needs two players.
