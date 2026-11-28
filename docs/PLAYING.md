# Playing Cops and Robbers

How the mod looks and works for players: the apps, the HUD, the car modes and the leaderboard. Hosts find setup in [Hosting](HOSTING.md); every rule and feature in detail is in [Features](FEATURES.md).

## The apps

The mod talks to players only through five apps. It sends no chat messages or pop-ups, and has no chat commands. Everything is clickable with the mouse.

| App | How it opens |
|---|---|
| **Cops and Robbers Announcements** | Added automatically on join. Role title, countdowns, GO and the result after a round. |
| **Cops and Robbers HUD** | Added automatically on join. Lobby card between rounds, prep line, chase line and catch bar, the spectating card, notices. |
| **Cops and Robbers How to play** | The How to play button on the lobby card or the prep line. It also opens by itself the first time a player joins. |
| **Cops and Robbers Panel** | The Host panel button on the lobby card or the prep line, or Esc > UI Apps. |
| **Cops and Robbers Leaderboard** | The Leaderboard button on the lobby card, or Esc > UI Apps. |

Announcements and the HUD can be moved and resized in the layout editor; if removed, they come back by themselves. To put the HUD away between rounds, use Hide on the lobby card. Leaving the server removes the apps the mod placed. Apps you add yourself in the layout editor stay, including ones you removed and then added back. How to play, Host panel and Leaderboard remember their size and position separately for each HUD layout when you close them or leave the server. Leaderboard and How to play hide themselves during a round you play in.

## How to play

A five-tab card (Basics, Runner, Cop, Resets, Rules) that reads its numbers from the server's current settings, so it always matches the round (for example "no time limit" or "sight is off").

## HUD

- **Lobby card** (between rounds): who is online, a line saying whether a round is waiting, buttons for Settings, How to play, Leaderboard, Host panel, Sit out and Hide, and a yellow line for a standing problem (a missing reset binding or outdated client mod).
- **Sit out:** keeps you out of rounds until you press it again (it then reads Play). You're never the runner, and when a round is set up your car leaves the map and comes back where it stood when the round ends. It lasts until you leave the server. Pressed during a round, it counts from the next one. Start only refuses when everyone sits out. Practice still works: with Sit out on, the panel's **Practice: watch the AI** runs an AI runner against two AI cops and you spectate them.
- **Spectating:** players who sit out watch the round. Anyone who joins or reconnects after the first car pick also watches until the round ends. The card shows "SPECTATING · Bob" (or "free camera"), the round clock and the helicopter, with Sit out (or Play), How to play, Leaderboard, Host panel and Settings. The game's own switch-car keys (Tab and Ctrl+Tab by default) go through the players' cars, the runner's too, and free camera (Shift+C by default) works. Spectators don't drive, can't spawn a car and count for nothing in the round. After the round they're back in the lobby and play the next one unless they sit out.
- **Hide:** folds the lobby card into a small "Cops and Robbers" tab at the same place; click the tab to bring the card back. The yellow warning lines still show above the tab. Your choice is saved in your own game. Your rounds always show the full HUD, and the lobby after them goes back to your choice.
- **Player settings.** The Settings button is available in the lobby, during prep, while chasing and while spectating. It opens a card with your car colour, six switches and a choice. **Auto headlights** (on by default) switches your low beam on at night and in rain, storms, thunderstorms, fog and snow. The lights go off again at sunrise in clear weather. The mod only acts when the conditions change, so your own light key still works. **Siren** (off by default) adds sound to a cop's light bar after release if the host allows Cop sirens. Turning off **Searchlight beam** (on by default) hides the beam in the air to help the frame rate while keeping its light and glare. Turning off **Helicopter sound** (on by default) fades out the rotor on your game. Turning off **Helicopter model** (on by default) hides the helicopter's body and aviation lights. The body is a flying Ibishu Pigeon van in its Bird Response livery, made once from your own game's Pigeon. Turning off **Lightning flashes** (on by default) hides flashes and bolts while thunder still plays. Cops can set **Route to the runner** to Always, Out of sight (default) or Never. These settings are saved in your own game and apply on every server. The chase line and How to play follow your game's distance and speed units. The Host panel uses metric units.
- **Colour:** a colour picker with a hex field, "No colour" and Done. The colour is used for every round car, repaints at once in prep and otherwise applies from the next round.
- **Prep:** the centre shows your role ("YOU'RE THE RUNNER" or "YOU'RE A COP", and for cops the runner's name). The bottom shows "Waiting for the host to press GO" with the Settings, How to play and Host panel buttons. In evolving mode it shows the runner's queued change instead, with Apply change for the runner.
- **Countdowns:** "RUNNER STARTS IN", "COPS RELEASED IN" and "CRASH PENALTY", then "GO!" or "PENALTY OVER".
- **Chase:** role, time (with the time limit when there is one), SPOTTED or HIDDEN for the runner, IN SIGHT or live and last-seen positions for cops (with how long ago a last-seen point was), the distance, and the reset status. A catch bar shows while the catch timer runs: red "BEING CAUGHT" for the runner, blue "HOLDING RUNNER" for cops.
  - **Sight range** is the clear-day distance in the direction the cop looks with the driving camera. Practice AI cops use their car heading. The mirrors give half range directly behind the car (200 m by default). Looking straight back gives full range (400 m by default). Buildings and terrain can block sight from the car. Darkness and bad weather shorten range. At night the runner's headlights and streetlights shining on the runner extend it.
  - **SPOTTED / HIDDEN** shows whether any cop on the ground has sight. One cop spotting the runner shares their live position, minimap marker and name tag with all cops. The helicopter shares the same information while tracking, even when the runner's HUD says HIDDEN. With Sight range Off, ground spotting is disabled and the runner's minimap marker and name tag stay visible to cops.
- **Notices:** rule breaks (illegal resets, teleports, parts changes, crash penalties), build changes and personal warnings appear as short lines above the chase line or the lobby card (or its tab), at most two at a time.
- **Result:** the title, the runner's time and who caught them, the map's top 3 and "Next round in N" with automatic rounds.

## Evolving car mode

Switch "Evolving car" on in the panel. Instead of a random car each round, everyone drives one shared **build**:

- Start a build from a random car or one you pick (vanilla configs and base cars from mods the server hands out).
- In each round's prep, only the runner may change **one thing** (an engine swap, one performance stage, one
  axle of wheels, plus whatever a swap needs to work). Everyone sees the queued change live in their HUD and keeps
  each other honest.
- The runner presses **Apply change** on the change card in the HUD (not the panel) to lock it in: every car is rebuilt with it (the screen shows APPLYING CHANGES until everyone has
  loaded, at most 20 s), then GO. Parts someone doesn't have are flagged in the HUD.
- The build is saved after every change and continues next session until "Reset build" (backups are kept in
  `data/build-<time>.json`). Practice rounds use the build but never change it.

## Leaderboard

"Cops and Robbers Leaderboard" has the look of the game's multiplayer scoreboard and four tabs: **Runners** (best survival times), **Cops** (catches, assists, fastest catch), **Players** (stats per player) and **Rounds** (every recorded round, newest first, with a timeline of what happened and each cop's share of sight). Filter by map, car mode and traffic. It refreshes after every round.

## Players and cops

Players are recognised by their BeamMP account (leaderboard, colors, who runs next); guests by name, which
changes every session. Cops get a light bar with lights on (no siren unless the cop turns it on in Settings and the host allows Cop sirens): when the round car has none, the light bar
parts of a police config of the same model are added for cops.
