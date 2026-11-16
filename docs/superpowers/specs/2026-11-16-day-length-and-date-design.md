# Day length and date

Status: short design for review, 2026-11-16. Follows night and weather rounds (`2026-11-16-night-weather-design.md`) and changes three of its decisions: the sky is now always set, Time of day and Weather default to random, and rounds get a date.

## Why
- "Clock speed" is a bare multiplier (0 to 120×) that means little to a player. The game itself offers a short list of day lengths (Disabled, Fast 15 min, Moderate 30 min, Slow 2 h, Realtime 24 h). The panel should offer the same.
- The date decides how long day and night are, and when sunrise and sunset happen. Rounds never set it today, so each player keeps the date from their own freeroam start (the game's default is 20 June). Two players in one round can get "Sunrise" at different clock times and night lights switching at different moments.
- The date should fit the weather: snow belongs in December or January, not in June.

## Goals
- **Day length** replaces Clock speed in the panel's Sky group: Off, Fast (15 min), Moderate (30 min), Slow (2 h), Realtime (24 h). Default **Moderate**.
- **A date for every round**, picked with the weather, the same for every player (rejoiners too). No date setting in the panel.
- **The sky is always set.** "Map default" goes from Time of day and Weather; both default to **Random** (night chance and bad weather chance stay 25%).

## Non-goals
- A date picker or season setting in the panel. The weather decides the date.
- BeamNG.Earth. The sky stays off there, as today.
- Any "custom" day length. Only the five names.

## Anti-goals
- Players in one round getting a different date, sunrise or night length.
- A player's own date left changed after the round (the saved sky is restored, date included).

## Date windows
The server picks a random day inside the weather's window, together with the weather (so New sky and each new round pick again; New car keeps it).

| Weather | Date window |
|---|---|
| Snow | 1 Dec – 31 Jan |
| Fog | 1 Oct – 30 Nov |
| Rain, Storm | 1 Mar – 30 Apr or 1 Oct – 30 Nov |
| Clear, Cloudy | any day of the year (no 29 Feb) |

How much it matters: on West Coast USA (latitude 38°) a December day is about 9.5 h and a June day about 14.8 h; at Moderate that is roughly 6 extra real minutes of dark in a winter round. Maps tested for latitude: jungle_rock_island 22°, west_coast_usa 38°, italy 41°, east_coast_usa 44°.

## Approaches
1. **Server picks the date with the weather (chosen).** `sky.pick` adds the date; it travels in the round's sky info that every player already gets (setup, New car, rejoin), and recorded runs store it. One place for the rule, easy to test, the leaderboard knows the date.
2. Each client works out the date from the weather and the shared random seed. Saves one field, but the server and the leaderboard never know the date, and the rule lives in client code that is harder to test. Dropped.
3. Keep `clockSpeed` as a number and only show it as a list. Old configs keep loading, but values like 30× or 120× match no list entry, so the panel would need a "custom" row. Dropped for a new key.

## Design
**Settings (`cnr/config.lua`, panel `settings.js`)**
- New `dayLength` choice: `off`, `fast`, `moderate`, `slow`, `realtime`; default `moderate`. Seconds per full day: 900, 1800, 7200, 86400 (the game's `core_environment.dayCyclePresets`); `off` is a stopped clock.
- `clockSpeed` is removed. An old config line gets the usual "unknown setting clockSpeed ignored" warning and Moderate applies.
- `timeOfDay` and `weather` lose `map`; their defaults become `random`. An old `"map"` value is an invalid choice: warning, and Random applies.
- Panel: Day length shows as a choice with the labels above; help "How long a full day lasts once the chase starts". Time of day and Weather lists drop "Map default".

**Server sky (`cnr/sky.lua`)**
- `pick` returns `year`, `month`, `day` next to time and weather (nothing on Earth, as today). `year` is the server's current year (only the moon phase depends on it).
- The payload always carries time, weather and date off Earth, plus the day length in seconds when it is not `off`. The record stores `dayLength` (the name) and the date; old records keep their `clockSpeed` field, which nothing displays.

**Client sky (`copsAndRobbers/sky.lua`)**
- The round's state sets `year`, `month`, `day` in the same `setState` as the time.
- The named time ("sunrise", ...) is worked out against the round's date, not the player's current one: `getSolarTimeOfDayValue(key, state)` with the current time-of-day state copied and the round's date put in.
- The clock math stays as it is (stopped in prep, starts at GO, catches up for a rejoiner), driven by the day length in seconds instead of the speed.
- Restoring after the round already puts back the saved `getState()`, which includes the player's own date.

**Labels**
- The prep card and the "New sky" message add the date: "Sunset · Snow · 14 Dec".
- The leaderboard's Rounds tab keeps "Sunset · Snow": its rows already show the real date the round was played ("Mon 14 Dec 14:05"), and a second, in-game date next to it would read as a mistake. The run still records the date.

**Docs**
- README and FEATURES settings tables and the Night and weather section follow the new settings (no map default, Day length, date by weather).

## Calls made (not discussed, easy to change)
- Year is the server's current year.
- The date shows on the prep card and in the "New sky" message, not in the Rounds tab (changed after the plan review).
- New sky still only shows while Time of day or Weather is random (now the default, so normally always). It re-picks the date too.
- No 29 Feb in the clear and cloudy window.

## Left to the builder
- Payload field names and how the day length travels (seconds or name).
- Checking in game that setting the date moves "Sunrise" and the night lights window, and that restoring after the round puts the player's own date back.
