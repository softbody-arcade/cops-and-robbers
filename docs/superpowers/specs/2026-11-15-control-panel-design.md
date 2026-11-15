# Control panel app: rounds and settings (short design)

## Intent
Run rounds and change settings with the mouse instead of typing `/cnr` commands. The panel is a separate, clickable UI app that is **not** placed automatically. Whoever adds it to their layout is the one running the game. The server does not check permissions, just as it doesn't for the chat commands. The user approved the proposal ("Sounds good") with settings applied automatically ("Automatic apply"). A leaderboard app comes later and is not part of this.

## Round tab
- **Status line:** phase, map and number of players. For example "No round", "Picking cars", "Prep: waiting for GO", "Countdown", "Runner head start" or "Chase 3:12". It also shows the runner's name, and "practice" during a test round.
- **Runner picker:** a dropdown with "Next (fewest runs)", "Same as last", "Random", then every online player by name.
- **Buttons.** Each is enabled only when it would do something:
  - **Start round** sends `start <choice>`. Enabled with no round running, or during a practice round, which it replaces.
  - **New car** sends `reroll`. Prep only.
  - **GO** sends `go`. Prep only.
  - **End chase** sends `end`. Head start and chase only.
  - **Cancel** sends `stop`. Any active round.
- **Automatic rounds:** an on/off switch. It sends `auto on`/`auto off` and works during a round.
- **Practice:** "as runner" sends `test runner` and "as cop" sends `test cop`. Enabled with no round running.
- **Reply line:** the server's answer to the last click, for example "A round is already running".

## Settings tab
- Every `config.json` setting in groups:
  - **Round:** head start, runner countdown, time limit (0 = off), auto next delay.
  - **Catching:** hold time, radius, max speed, explode on catch.
  - **Resets:** wait time, still speed, cop min distance, gas station radius.
  - **Crashes:** speed loss, penalty.
  - **Cops:** spawn min, spawn max, last seen interval.
  - **Cars:** include mod cars, excluded cars.
- Numbers get `[ − ] value unit [ + ]` with a sensible step per setting, for example 1 s, 100 m for the cop distance and 60 s for the time limit. On/off settings get a switch. Excluded cars are a comma-separated text field.
- A setting the panel doesn't know yet, such as a new key from a newer server, shows under "Other" with step 1.
- **Automatic apply (the user's call: "Automatic apply").** There is no Apply button.
  - A change is sent 0.5 s after the last click on that panel, so clicking `+` five times saves once. All values changed in that window go together.
  - The excluded cars field is sent on Enter or when it loses focus.
  - The server checks every value and saves them in a single write. If any value is invalid it saves nothing, replies with the error, and the panel snaps back to the server's values.
  - The reply line confirms each save, for example "Saved: head start 8 s".
  - Settings saves from the panel reply in the panel only, not in chat, so clicking a stepper doesn't spam chat.
- **Reset to default** saves all defaults at once, so it needs two clicks: "Reset to default" becomes "Click again to reset" for 3 s.
- **During a round** the setting controls are disabled and the tab shows "Stop the round first". The server refuses changes anyway.
- `autoNextRound` is on the Round tab only, so it doesn't appear in two places.

## How it works
- **Server:**
  - **New event `cnr_panel`** (JSON from the client):
    - `{action="open"}` subscribes the player and sends them the panel state.
    - `{action="close"}` unsubscribes them.
    - `{action="command", text=...}` runs one of the round commands above through the existing handlers. The allowlist is the current bindable list plus `start <anything>`, `auto on` and `auto off`.
    - `{action="settings", values={key=value,...}}` validates every value with `config.setValue`, writes `config.json` once, and rebuilds the round, as `/cnr set` does.
  - **`cnr_panelState`** goes to subscribers when they open the panel and whenever it changes. The tick compares the encoded state with the last one sent. It contains:
    - version, map, phase, runner, whether it is a practice round, and chase elapsed
    - online player names
    - the current settings with their defaults
    - the auto flag
  - **`cnr_panelReply {text}`** goes to the player who clicked. While a panel command runs, chat replies to that player are mirrored into it, so they still appear in chat too. Settings saves reply in the panel only.
  - Subscribers are dropped when they disconnect.
- **Client:**
  - `copsAndRobbers.panel(json)` forwards the app's requests to the server.
  - `cnr_panelState` and `cnr_panelReply` are passed to the UI as `CnRPanel` and `CnRPanelReply`.
  - It is kept out of `onUpdate`, which is near LuaJIT's upvalue limit.
- **Vue app:** `ui/modules/apps/CopsAndRobbersPanel/`
  - `app.json` sets `"vue": true` and `"interactive": "required"`, with a default size of about 440×520.
  - `app.vue` uses `useEvents()` for the two events and `useBridge().api.engineLua` for the calls, the same way the game's own AIControl app does. It uses BeamNG's components (`BngTabs`, `BngButton`, `BngSwitch`, `BngDropdown`, `BngInput`) where they fit.
  - On mount it sends `open`, and on unmount `close`.
  - The placement code never adds it.
- **Version:** 1.5.0.

## Approaches
- **Vue app (chosen):** the same UI system as the HUD, which the user picked as "the newest". It is clickable when the mouse is shown.
- **ImGui window:** needs no layout, but looks like a developer tool. Rejected, as it was for the HUD.
- **Panel sends chat-style text only (also for settings):** reuses the current path, but every save would turn into one `set` per value. That means a config write, a round rebuild and a chat line for each one, and half-applied changes when one value is invalid. Rejected in favour of one structured settings request (my call).

## Left to the builder
- Exact styling, the step size per setting, and the minimum per stepper (0, or one step for settings that must be above 0).
- Labels and units, which live in the Vue app next to the group list.
- Whether the panel shows a small "not connected to a Cops and Robbers server" state when no state has arrived.
