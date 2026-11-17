# HUD hide (2.9.5)

## Why
- **The user's ask:** "HUD should have a hide button for when we don't want to play cnr".
- **Today:** players on the server who are just driving around between rounds always have the lobby card at the bottom centre. The HUD app is sticky (`apps.lua`), so removing it through the game's app editor doesn't last, and chat commands are gone (`main.lua` `cnrOnChatMessage`), so there is no other way to put it away.

## Design (approved 2026-11-17)
- **A Hide button** on the lobby card (`HudLobby.vue`), after Settings, How to play, Leaderboard and Host panel.
- **Hidden:** the lobby card is replaced by a small tab at the same place (bottom centre), reading "Cops and Robbers" with an up-pointing icon. Clicking the tab shows the card again.
- **Only the lobby:** during a round (prep, the chase, the result) the HUD shows in full as now, whatever the choice. After the round, the lobby goes back to the player's choice.
- **Saved per player:** a new boolean `hudHidden` in `playerSettings.lua` (default false), stored in `settings/cnr_settings.json` with the other personal settings. It survives a restart and a rejoin.
- **Unchanged:**
  - the notices (`HudNotices`) still show above the tab
  - an open Leaderboard or Host panel stays open
  - the lobby's Settings view can only be opened from the full card
  - the Announcements app and the HUD's placement
- **Practice:** a player's own practice round counts as a round. The full HUD shows during it.

## Approaches
- **(a) Collapse to a small tab. Picked:** one click brings it back, and the player has nothing to remember.
- **(b) Hide fully until a round starts.** Rejected: there's no way back between rounds, since chat commands are gone.
- **(c) A key binding.** Rejected: the user hasn't asked for one, and players don't find unbound actions.

## Left to the builder
- **The tab:** its exact look, within the existing kit (`cnr-btn`, `CnrCard`, BngButton), the game's icon set, and `pointer-events: auto` only on the tab.
- **The plumbing:** whether the HUD sends the click through the existing `setting` action (`copsAndRobbers.lua` `action == "setting"`) or a new one. Reusing `setting` is preferred.

## Tests
- `playerSettings`: `hudHidden` loads with the default false, accepts booleans, rejects anything else, and round-trips through the file.
- **The HUD payload** (`hud.lua`) carries `hudHidden` in the lobby block (or the settings). The round payload is unaffected by it.
- `make vuecheck` passes. The Vue side shows the tab instead of the card when hidden in the lobby, and the full card otherwise.

## In-game check
- Hide and show in the lobby.
- The choice survives a rejoin.
- A round shows the full HUD, and after it the tab comes back.
- Notices show above the tab.
