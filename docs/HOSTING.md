# Hosting Cops and Robbers

Installing the mod on a BeamMP server, upgrading it, and running rounds from the host panel. Every `config.json` setting is listed in [Settings](CONFIG.md).

## Install

```
make package
```

- Copy `dist/Server/CopsAndRobbers` to the server's `Resources/Server/`.
- Copy `dist/Client/CopsAndRobbers.zip` to the server's `Resources/Client/`.
- Set `MaxCars` to at least 3 if you want to use practice rounds (the AI cars count as yours; watching the AI practise also takes 3, your own car is parked).
- Traffic counts too: every player needs room for their round car plus `trafficPerPlayer` traffic cars, so `MaxCars` of at
  least 1 + traffic per player (3 + traffic per player for practice rounds). With less room the mod spawns fewer traffic
  cars and the panel says so.

Start or restart BeamMP after copying the files. Check the server log for `Cops and Robbers <version> loaded` and
check for Lua errors. BeamMP downloads the client mod when players join. During rounds, Reset vehicle and Recover
repair in place. Load home and Recover to last road repair the runner in place and move cops to the nearest road.

## Upgrade an existing server

Overlay the packaged client ZIP and server plugin files. Keep the server's existing `config.json` and `data/`
inside `Resources/Server/CopsAndRobbers/`. For a local upgrade with `make install-local`, copy the installed
`config.json` to `server/CopsAndRobbers/config.json` in a disposable checkout before running the target, so the
package includes the local settings.

## Host panel

"Cops and Robbers Panel" has four tabs:

- **Round:** shows only what can be done now. The player list is the runner picker (the planned next runner is preselected: drawn at random among the players with the fewest runs, never the previous runner twice in a row). One main button does the next step: Start round, then GO, with a yellow line saying why it can't yet. Practice as runner and as cop (one "Practice: watch the AI" button while you sit out), New car, Cancel round, and the Automatic rounds switch. During a round the panel folds into a bar with the time, End chase and Cancel (a second click is needed during the chase). It opens again when the round ends.
- **Car:** Random car or Evolving build, the build summary, New build (choose a car or random) and Reset build, mod cars and excluded cars.
- **Map:** gas stations of this map, Add station here and Remove nearest.
- **Settings:** the common settings first, the rest under More settings, each with a one-line explanation. Changes save by themselves; a value that differs from the default is orange and has its own reset. Settings are locked during a round. "Reload config.json" picks up hand edits.

For a five-second lightning test, choose **Night** and **Thunderstorm** in the Sky settings. Under **More settings → Sky**, turn **Weather changes** off and set **Minimum strike interval** and **Maximum strike interval** to **5 s**. Turn **Lightning flashes** on in your player settings, then start a round and press **GO**. The first strike comes five seconds after the runner countdown starts, with another every five seconds. Watch the flashes outdoors. Thunder takes longer to arrive from distant strikes.

## Traffic

Traffic is off by default ([settings](CONFIG.md)). Set `trafficPerPlayer` above zero to spawn that many AI cars around each player during a round.
With **Traffic for the runner only** (`trafficRunnerOnly`), the runner's game spawns the traffic for better performance.
Practice rounds keep their traffic either way, except a practice you only watch (Sit out on), which has none. They spawn in prep, stand still until GO, and are removed when the round ends. There are no police or emergency
vehicles among them, and they have no name tags, so every car with lights is a cop and every name tag is a player. A
cop who drives into a traffic car gets the crash penalty ("crash penalty 10s (traffic)"), as with any crash only within
`copResetMinDistanceMeters` of the runner; one who gets hit by traffic doesn't. Traffic headlights follow the weather and switch on in rain, storms, thunderstorms, fog and snow. At night they follow the game's own lights.

Every player's game simulates everyone's traffic. If that gets heavy, BeamMP's "Simplify remote vehicles" option makes
other players' cars, traffic included, lighter to run.
