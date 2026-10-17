# Changelog

All notable changes to the Dixlase Docker installer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the installer follows Semantic Versioning. Its version is independent of Dixlase core: the installer clones whichever core release it is pointed at.

A release is cut when behaviour on your machine changes (`setup.sh`, `update.sh`, `reset.sh`, `docker-compose.yml`, nginx, Dockerfile). Changes to documentation or CI alone wait for the next release. Each release lists what to do after updating under **Upgrade notes**.

To update the installer itself, run `git pull` in its directory, then follow the upgrade notes of every release you skipped. `./update.sh` updates Dixlase core in `html/`, not the installer.

## [0.1.5] — 2026-10-17

### Changed (docs)

- The documentation, the comments in `docker-compose.yml` and `docker-compose.deploy.yml`, and `.env.example` no longer name a plugin that is not distributed publicly. Everything they say stays: the host's SSH keys are **not** mounted into the app container, and `docker-compose.deploy.yml` mounts them read-only for people who deploy from inside it — where every process in the container can then read those keys. What the mount is for is now described by what it does, deployment tooling run inside the container, rather than by the name of something a reader of this repository cannot obtain, open a link to or check. The `artisan` commands that only that plugin ships are gone with the name (#60).

### Upgrade notes

Nothing to do. This release changes text only. No script, compose file, environment variable, volume or service name changed, so `docker-compose.deploy.yml` and a `COMPOSE_FILE` line already set in your `.env` keep working exactly as before.

## [0.1.4] — 2026-10-15

### Fixed

- `./update.sh` can update `html/` on Linux again. `setup.sh` hands `html/` to `www-data` so php-fpm can write there, and Linux — unlike macOS — enforces that ownership on a bind mount, so the host user could no longer write inside `html/`. Every git command that moves the checkout failed, starting with the `html/.gitignore` restore, and the update stopped at step `[1/6]` with `Permission denied`. Those writes now go through the app container, which runs as root. `.git` is still handed back to you, so your own git commands in `html/` keep working. This had been the case since 0.1.0; macOS was never affected (#58).
- The commands `update.sh` prints when it stops — `git stash`, `git checkout -- .`, `git reset --hard` — name a form that works on Linux. The host-side ones it printed before would have been refused for the same reason (#58).

### Changed (CI)

- The smoke test runs the update path, which it never did: it installs the release before the newest one, installs Dixlase from the command line, updates to the newest release and then to `main`. `update.sh` is in the workflow's path filter now, so a change to it runs the end-to-end test instead of nothing (#56).

### Upgrade notes

If `./update.sh` stopped on Linux with `error: unable to unlink old '.gitignore': Permission denied`, this release clears it. Update the installer with `git pull`, then run `./update.sh` again. The run that failed stopped at `[1/6]`, before composer, the migrations and the assets, so there is nothing to undo.

Nothing to do otherwise.

## [0.1.3] — 2026-10-15

### Changed

- `setup.sh` installs core's **newest release** instead of the tip of core's development branch. It reads the newest `vX.Y.Z` tag from the core repository with `git ls-remote` — no GitHub API, so no rate limit and no new dependency — and clones that. An explicit ref still wins: `./setup.sh main` installs the development branch, `./setup.sh v0.1.11` installs that release. When no tag can be read (a fork with no releases, or no network), the run says so and falls back to `main` instead of failing (#54).
- `update.sh` moves an install made from a release tag to the newest release. It used to refuse, because a tag checkout is a detached `HEAD` and there was no branch to update. An install that tracks a branch is fast-forwarded exactly as before (#54).
- The banner of `setup.sh` reads `Core:` rather than `Branch:`, since the value can now be a tag, and the Japanese dictionaries cover that banner — it was the one part of the output that stayed English after `./convert-comments.sh ja` (#54).
- The README describes the release-based install and both update paths, in both languages (#53, #54).

### Fixed

- The ownership step at the end of `setup.sh` and `update.sh` no longer prints `cannot dereference` for a plugin or theme whose public asset link points at a missing directory. `chown -h` changes the link itself instead of following it, so a successful run no longer ends on what looked like a failure (#47).

### Changed (CI)

- The smoke test runs on pull requests, not only on pushes to `main` and the nightly schedule. A pull request that broke the end-to-end install used to go green and surface only after the merge (#51).
- The credential-free smoke job asserts that the install is core's newest release: `html/` checked out at that tag, and a `VERSION` that is not a `-dev` build (#54).

### Upgrade notes

Your existing install is not touched by updating the installer: `html/` stays on whatever it is on now, and nothing in this release moves it.

What changes is the next fresh install. `./setup.sh` with no argument now gives you core's newest release, not `main`. If you want the development branch, name it: `./setup.sh main`.

A release install leaves `html/` on a detached `HEAD` — that is simply what a tag checkout is in git — and `./update.sh` moves it to the next release. An install that came from `main` keeps following `main` when you run `./update.sh` with no argument.

## [0.1.2] — 2026-10-10

### Removed

- The `composer_auth` build secret, and with it the empty Composer `auth.json` that `setup.sh` created in the user's home directory to satisfy it. The secret existed only because the bundled theme used to live in a private repository; every package core requires is public now, so a build needs no credential and the installer no longer writes outside its own directory (#49).

### Changed

- `update.sh` no longer passes the host's Composer credentials into the container, and its `composer install` failure hint now names the causes that remain — the container's network, github.com, and the `repositories` entries in `html/composer.json` — instead of telling you a `dixlase/*` package is private and needs a token (#49).
- CI: the credential-free smoke test asserts that `setup.sh` writes no `auth.json`, the opposite of what it asserted before (#49).

### Upgrade notes

No action needed. `setup.sh` no longer creates `~/.composer/auth.json`, and a file an earlier run left behind is not touched: if it holds only `{}` you can delete it, and if you have since put a token in it, leave it — other tools may read it.

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
