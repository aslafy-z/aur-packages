# AUR packages

Personal AUR packages, managed in a GitHub repository.

- Pull requests and pushes to `main` build and `namcap`-validate only the
  packages they touch, in a clean container. A change to the CI workflow or to
  `scripts/` builds every package instead, as do the weekly and manual runs.
- Anything running on `main` publishes to the AUR; pull requests never do. The
  weekly run is therefore also what retries a publish that failed.
- Renovate opens pull requests for new upstream versions, with checksums for
  every architecture already recomputed in the same commit.
- `.SRCINFO` is generated in CI and is not tracked here.

Packages live in `packages/`. Run `mise run pkg:list` to see them.

## Requirements

[mise](https://mise.jdx.dev) provides the tooling. `makepkg` and `namcap` come
from pacman, since mise manages developer tools rather than system packages.

```bash
sudo pacman -S --needed base-devel namcap
mise trust && mise install
```

## Tasks

```bash
mise tasks          # list everything below with descriptions
mise run <task>     # run one
```

| Task | Purpose |
| --- | --- |
| `pkg:list` | List packages in this repository |
| `pkg:new <pkg>` | Scaffold a new package from a PKGBUILD skeleton |
| `pkg:adopt <pkg>` | Clone an existing AUR package and take over as maintainer |
| `pkg:refresh <pkg>` | Recompute every checksum array |
| `pkg:bump <pkg> <version>` | Set a new version and refresh checksums |
| `pkg:build <pkg>` | Build locally in a clean tree and run `namcap` |
| `pkg:drop <pkg>` | Remove a package from this repository |
| `check:deps` | Verify system dependencies are installed |
| `lint` | Shellcheck the helper scripts and validate task definitions |

Tasks change the working tree and stop. Committing, pushing and opening pull
requests are left to you.

## Adding a package

1. `mise run pkg:new <pkg>` and fill in the generated `packages/<pkg>/PKGBUILD`.
2. Point the `# renovate:` comment on the `pkgver=` line at the real upstream,
   otherwise the package is never considered for automatic upgrades.
3. `mise run pkg:refresh <pkg>` to fill in the checksums.
4. `mise run pkg:build <pkg>` to confirm it builds.
5. Open a pull request. CI builds it; merging to `main` publishes it.

## Checksums

`mise run pkg:refresh` replaces `updpkgsums`, which is unsafe for this
repository. `updpkgsums` downloads each source to its `name::` target, so a
package whose per-architecture sources rename to the same local filename gets
one download and one hash copied into every `sha256sums_*` array, silently
wrong for every architecture but the first. `kftray-appimage` is exactly that
shape. `scripts/refresh-sums.sh` fetches each source to a slot-unique path
instead, so the arrays cannot collide.

## Automatic upgrades

Renovate runs [self-hosted](.github/workflows/renovate.yml) on a daily
schedule. It reads the `# renovate:` annotation on each `pkgver=` line, and a
`postUpgradeTasks` hook runs `scripts/refresh-sums.sh` before the commit is
created, so the version bump and the correct checksums arrive together.

Self-hosting is what makes that possible: `allowedCommands`, which gates
`postUpgradeTasks`, cannot be set from a repository config, and the hosted
Renovate app permits only an undocumented set of commands that will not include
a repository-local script.

Two secrets are required, from a GitHub App installed on this repository:
`RENOVATE_APP_CLIENT_ID` and `RENOVATE_APP_PRIVATE_KEY`. A GitHub App token is
used rather than `GITHUB_TOKEN` because pull requests opened with
`GITHUB_TOKEN` do not trigger other workflows, which would leave upgrade pull
requests with no build or `namcap` checks.
