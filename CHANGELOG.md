# Changelog

All notable changes to the Dixlase Docker installer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the installer follows Semantic Versioning. Its version is independent of Dixlase core: the installer clones whichever core release it is pointed at.

A release is cut when behaviour on your machine changes (`setup.sh`, `update.sh`, `reset.sh`, `docker-compose.yml`, nginx, Dockerfile). Changes to documentation or CI alone wait for the next release. Each release lists what to do after updating under **Upgrade notes**.

To update the installer itself, run `git pull` in its directory, then follow the upgrade notes of every release you skipped. `./update.sh` updates Dixlase core in `html/`, not the installer.

## [0.1.1] — 2026-10-03

### Fixed

- `setup.sh` creates an empty Composer `auth.json` when the host has none, so a first run on a machine without GitHub credentials no longer fails. All Dixlase repositories are public, so no token is needed (#38).

### Added

- `setup.sh` and `update.sh` print the installer version next to the core version (#43).
- `VERSION` and this changelog (#43).

### Changed

- The README explains the file-integrity warning that can follow a core update, and how to regenerate the baseline once.
- The README shows how to clone a fixed installer version.
- CI: the end-to-end smoke test also runs with no credentials at all (#39), no longer needs a repository token, and pull requests are checked for a linked issue (#42).

### Upgrade notes

No action needed. If your checkout predates 2026-09-27 (before 0.1.0) and the web container keeps restarting with `unknown "dixlase_https_port" variable`, recreate it once: `docker compose up -d --force-recreate web`.

## [0.1.0] — 2026-10-01

Initial public release, published with Dixlase 0.1.0 (Beta 1).

### Added

- `setup.sh` — one-command local install: clones Dixlase core into `html/`, builds the PHP, nginx, MariaDB, Mailpit and Adminer stack, installs dependencies, builds assets and opens the install wizard. HTTP or HTTPS (self-signed certificate for `localhost`), with configurable ports.
- `update.sh` — pulls the latest core into `html/` (fast-forward or a clear explanation of what to do), runs migrations, rebuilds assets and caches.
- `reset.sh` — returns the environment to a clean state.
- Windows support through WSL2 or Git Bash, with shell scripts kept LF, and a ZIP-download path for users without `git`.
- Security defaults: only the site is published on the host, the host's SSH keys are not mounted, PHP that is not a real file is refused, and apt signatures are verified.
- English and Japanese comments and messages through `./convert-comments.sh`.
