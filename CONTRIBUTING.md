# Contributing to Cops and Robbers

Thanks for helping. Cops and Robbers is a chase minigame for BeamNG.drive multiplayer (BeamMP), part of [Softbody Arcade](https://github.com/softbody-arcade).

The full rules, for people and for coding agents alike, are in [AGENTS.md](AGENTS.md). This page is the short version, and [Roles](docs/ROLES.md) explains what each team can do.

## Set up

1. Install the prerequisites listed in [Development](docs/DEVELOPMENT.md#prerequisites).
2. Clone the repo and run `make hooks` once. This turns on the privacy check that runs before every push.
3. Commit with your GitHub noreply address (`git config user.email ID+login@users.noreply.github.com`), never a personal or work email.
4. Run `make doctor` to check your tools, hooks and email, then check everything works: `make test`, `make vuecheck` and `make package`.

## Pick something to work on

- The [Softbody Arcade board](https://github.com/orgs/softbody-arcade/projects/1) shows all work.
  - The **Quick wins** view lists important issues that need little effort.
  - Issues labelled `good first issue` or `help wanted` are open for contributors.
- Comment on the issue before you start. The maintainer starts the card and assigns it to you.
- Contributors don't move cards themselves.
- Have an idea or found a bug? Open an issue with one of the templates.

## Make a change

1. Create a branch from `develop` named `feature/<topic>` or `fixes/<topic>`. `develop` is the default branch, and every PR targets it; `main` only receives releases.
2. Push early, and open a draft pull request that says `Fixes #<issue>`.
3. Follow the design, test and review rules in [AGENTS.md](AGENTS.md#design-and-implementation).
   - New gameplay gets a short spec and plan first.
   - Every change comes with tests where the result can be checked automatically.
4. CI must be green: `test`, `luajit`, `vuecheck`, `privacy` and `package`.
5. If players would see, hear or feel your change, say so in the pull request. The maintainer decides whether it needs a playtest before merging, or defers the check to an In-game check issue.

## Playtesting

Playtesters pick up issues of type **In-game check**:
1. Follow the setup and action in each check.
2. Post what you saw as a comment: pass or fail, and what happened.
3. File a **Bug** for anything else you notice.

## Privacy

Never commit personal data or details of any live server:
- IP addresses
- email addresses other than GitHub noreply ones
- SSH logins
- home-folder paths
- how or where a server runs

The pre-push hook and CI enforce this with `scripts/privacy-check`.

## Licence

By contributing you agree that your contribution is licensed under the [MIT Licence](LICENSE).
