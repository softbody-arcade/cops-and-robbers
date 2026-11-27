# Cops and Robbers for BeamMP

Server plugin plus auto-downloaded client mod that enforces our cops-and-robbers rules: one runner, the rest cops, a police helicopter, changing weather and a leaderboard. Part of [Softbody Arcade](https://github.com/softbody-arcade).

## Install

1. Get `CopsAndRobbers.zip` and `CopsAndRobbers-server.tar.gz` from the latest [release](https://github.com/softbody-arcade/cops-and-robbers/releases), or build them with `make package`.
2. Put `CopsAndRobbers.zip` (the client mod) in the server's `Resources/Client/`.
3. Extract `CopsAndRobbers-server.tar.gz` into the server's `Resources/Server/`, which gives `Resources/Server/CopsAndRobbers/` (the server plugin).
4. Restart BeamMP. BeamMP hands the client mod to players when they join.

Car limits, upgrades and the host panel are in [Hosting](docs/HOSTING.md).

## Documentation

- [Playing](docs/PLAYING.md): the apps, HUD, car modes and leaderboard
- [Hosting](docs/HOSTING.md): install, upgrade, host panel and traffic
- [Settings](docs/CONFIG.md): every `config.json` setting
- [Features](docs/FEATURES.md): every rule and feature in detail
- [Development](docs/DEVELOPMENT.md): prerequisites, tests, releases and code layout
- [Roles](docs/ROLES.md): who can do what
- [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md)

All documentation lives in [`docs/`](docs/README.md), which is also an Obsidian vault.

## Credits

The helicopter's rotor sound is "Helicopter Rotor Loop" by qubodup, https://freesound.org/people/qubodup/sounds/187681/, CC0
(shipped as a mono OGG in `client/art/sound/cnr/heli_rotor.ogg`, made louder by +6 dB with a limiter).

The thunder clips use three CC0 originals. To recreate the shipped clips, use [tools/thunder/cut.sh](tools/thunder/cut.sh).

- [sfx_thunder blast.wav by bajko](https://freesound.org/people/bajko/sounds/399656/)
- [Distant Thunder Clap_Gentle.wav by mikala_oidua](https://freesound.org/people/mikala_oidua/sounds/347562/)
- [230405 Thunder DRY rolling distant low rumbles, roof, EM272s, Toronto 7am by TRP](https://freesound.org/people/TRP/sounds/717845/)

## Licence

[MIT](LICENSE)
