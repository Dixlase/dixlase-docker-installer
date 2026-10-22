# Changelog

All notable changes to the Dixlase Docker installer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the installer follows Semantic Versioning. Its version is independent of Dixlase core: the installer clones whichever core release it is pointed at.

A release is cut when behaviour on your machine changes (`setup.sh`, `update.sh`, `reset.sh`, `docker-compose.yml`, nginx, Dockerfile). Changes to documentation or CI alone wait for the next release. Each release lists what to do after updating under **Upgrade notes**.

To update the installer itself, run `git pull` in its directory, then follow the upgrade notes of every release you skipped. `./update.sh` updates Dixlase core in `html/`, not the installer.

## [0.1.10] — 2026-10-22

### Fixed

- The database service no longer tracks a floating tag. It ran `image: mariadb:latest`, so `./setup.sh`, `docker compose pull` or a plain `docker compose up -d` could start a different MariaDB server against an existing `mysql/`. MariaDB upgrades a data directory in place when it starts, and that is one-way: the directory records the server that last touched it (`mysql/mariadb_upgrade_info`) and no older server will open it afterwards, so a pull could change the database version with no way back short of a dump taken beforehand. The tag has already crossed 12.2 to 12.3, and data directories on the older line are still in use. The service now names `${DB_IMAGE:-mariadb:12.3}` — a MariaDB LTS line, so patch releases still arrive while a pull never crosses the line — and `DB_IMAGE` in `.env` either pins a single version (`mariadb:12.3.3`) or holds an install on the line its data directory records. `setup.sh` stops before it starts the stack when the two differ, and says how to keep the database where it is or move it on purpose; `update.sh` never starts the database container, so it says the same thing rather than stopping. A tag that cannot be read as a version (`latest`, a digest, no tag at all, a registry carrying a port) makes both scripts skip the comparison rather than guess (#78).

### Changed (CI)

- The install step of the update smoke job passes `--db-*` and no `DB_*` environment variables. They worked around a core defect that core fixed in 0.1.15, and while they were there the job installed with the environment already pointing at the right database — which is the condition that hid the bug. It now installs the way an operator does, so the one layout this installer always has, a database in another container, is covered from the command line (#71).
- `test.yml` fails if the database service goes back to a floating tag (#78).

### Upgrade notes

**If your database is not on MariaDB 12.3, say so in `.env` before you run any Docker command.** `cat mysql/mariadb_upgrade_info` names the server that last upgraded the data directory. 12.3.x means there is nothing to do — that is the new default. Anything older goes in `.env` first:

```bash
DB_IMAGE=mariadb:12.2   # the line the data directory is already on
```

`./setup.sh` stops rather than start a different line against an existing data directory, and `./update.sh` says so in its summary, but a bare `docker compose up -d` is not guarded and would upgrade the directory in place.

To move the database to a newer line on purpose: shut the stack down cleanly, take a dump with the line it is on now, set `DB_IMAGE` to the line you want, and start it again. The move cannot be undone, which is what the dump is for. README describes this under "Moving the database to a newer MariaDB".

Nothing else is needed for a working install, and this release does not ask for an image rebuild.

## [0.1.9] — 2026-10-22

### Fixed

- `./update.sh --rebuild` builds the images again and replaces the containers with them, which is what moves an install to a newer PHP. `update.sh` advanced the core checkout, ran composer, the migrations and the asset build and cleared the caches — all inside the containers that were already running — and built nothing at all. The `Dockerfile` stands on the floating `php:8.3-fpm` tag, and a floating tag moves for an install only when the image is built again, so an install kept the PHP it was first built with however often `update.sh` ran, with nothing in the output to say so. The PHP 8.3.36 security release made that urgent. The rebuild sits after the core update and before composer, so dependencies are resolved by the PHP that will serve them; it builds the app image, and `cron`'s as well when that container is running, replaces those containers and restarts `web` so nginx reaches the new app container at once. `mysql` stays out of it (`--no-deps`). `--no-cache` rebuilds every layer for the case where the base image did not move, and on its own it is refused rather than quietly ignored. Every run now prints the PHP the container runs, and a run without `--rebuild` says how to move it (#73).
- The image still builds while `pecl.php.net` cannot serve the redis extension. The extension had one source and no retry, so the build failed outright whenever that download did not answer — as it did for about an hour on 2026-10-22, right after the PHP 8.3.36 security release, the moment every PHP image is being rebuilt and a rebuild matters most. The version is pinned through a `REDIS_VERSION` build argument, PECL is tried three times, and the same version's tag on GitHub is the fallback, built with `docker-php-source` and `docker-php-ext-install`. When neither source answers, the build fails with a message naming both, and the step ends by asserting the extension is loaded, so a build that installed nothing cannot pass as one that did (#74).

### Changed (CI)

- The update smoke job runs `./update.sh --rebuild` and asserts that the PHP version the summary reports is the version the container runs, then checks that the site still answers (#73).

### Changed (docs)

- The documentation calls the product Dixlase rather than Dixlase CMS, which is the name the licence texts in core already use (#72).
- README and README.ja say when and how to move an install to a newer PHP. SECURITY and SECURITY.ja say that an update of an upstream image reaches an install only through a rebuild (#73).

### Upgrade notes

Run `./update.sh --rebuild` once after `git pull`. An install keeps the PHP its image was built with, so a PHP security release — 8.3.36, here — reaches it only through a rebuild. This supersedes the note in 0.1.8 that `./update.sh` does not rebuild images: it still does not, unless you ask for it with `--rebuild`.

The rebuild replaces the app container, and the cron container when it is running. `mysql` is left alone, and the rebuild itself writes nothing into `html/`, so the database and the site's files are not part of it. The site is served from the old container until the new image is built, and `web` is restarted at the end so nginx picks the new one up at once.

If the build cannot finish — `pecl.php.net` or Docker Hub not answering — the containers keep running on the image they have, but the run stops after `html/` has already been advanced and before composer and the migrations, so the site is then serving a core checkout whose dependencies and database have not caught up with it. Run `./update.sh --rebuild` again once the download answers; it picks the run up from the beginning and is safe to repeat.

The services that use an upstream image directly (`mariadb`, `nginx`, `adminer`, `mailpit`, `redis`) take an update through `docker compose pull && docker compose up -d`. They are not part of `--rebuild`, which builds the images this repository defines.

## [0.1.8] — 2026-10-20

### Fixed

- The app and cron containers no longer nest the `public/storage` symlink. Both build from the same image, mount the same `html/` and run the same entrypoint with nothing ordering one after the other, so both could reach the link step while the link did not exist yet. The first `ln` created it; the second ran against a path that was by then a symlink to a directory, which writes the link *inside* it and leaves `storage/app/public/public` pointing at nothing. On Linux that dangling path used to stop the ownership step of `setup.sh`, so part of `html/` kept the host user's ownership: the install wizard could not write `.env`, and an update could not rewrite the integrity baseline. The entrypoint uses `ln -sfn` now, so the container that loses the race writes the same link instead of a nested one, and it removes a nested link left by an earlier start. A `public/storage` left dangling is repaired as well (#46).
- `setup.sh` and `reset.sh` no longer end a run without a word when a question has no answer behind it. `read` returns non-zero at end of input and both scripts run under `set -e`, so a pipeline one answer short stopped at a step whose output said nothing. `setup.sh` uses a piped or typed answer when there is one and otherwise prints what it assumed, and what it assumes always keeps what is on disk — `html/`, `mysql/` and the containers all stay — even where the interactive default deletes. `reset.sh` exists to delete, so it has nothing safe to assume: it says it needs an answer or `-y`, and stops (#66).
- `setup.sh` names the core release in its completion summary, above the installer version, which is what the 0.1.1 changelog said both scripts would do. A fresh install never printed which core release it had just put on disk. `unknown` is printed when the file cannot be read, and `update.sh` pads its own line to match and falls back to `unknown` instead of printing an empty value (#45).

### Changed (CI)

- The smoke test asserts that `html/public/storage` resolves and that nothing is nested under it. That job runs with the `cron` profile on, so the window the entrypoint fix closes is open on every run (#46).

### Upgrade notes

The entrypoint lives in the app image, so the storage-link fix reaches a running stack when the image is rebuilt: `git pull`, then `./setup.sh` (which builds), or `docker compose build && docker compose up -d`. `./update.sh` does not rebuild images.

A `storage/app/public/public` left by an earlier run is removed by the new entrypoint the first time it starts. Nothing else is needed — `chown -h` has tolerated that link since 0.1.1, so an install that works today keeps working.

If you drive `./setup.sh` from a script, note that a question it cannot get an answer to is now answered with the option that keeps what is on disk, rather than ending the run. `./reset.sh` in a script needs `-y`, as before, and now says so instead of stopping silently.

## [0.1.7] — 2026-10-20

### Fixed

- `./setup.sh` offers to remove `mysql/` when it re-clones `html/`. It used to replace `html/` and leave the database files of the earlier install in place, and the fresh core then found a fully migrated database while `INSTALLED=false`, took it for an install waiting to be finalized, and sent every step of the install wizard straight to the completion screen — offering to finalize an install whose administrator account belonged to the previous one, and whose encrypted values the new `APP_KEY` cannot read. A `mysql/` that still holds data is now explained before the clone and removed when you press Enter: the database container is removed first, then the files through a throwaway container, the way `reset.sh` does it, and the run stops with instructions if they cannot be removed. Answering `n` keeps `mysql/` and warns that the wizard will skip ahead. Keeping the existing `html/` never touches `mysql/`, and an empty `mysql/` is cleared without asking (#64).

### Upgrade notes

Nothing to do for a working install.

If a re-run of `./setup.sh` has already left you with an install wizard that jumps to the completion screen, start over from an empty database: update the installer with `git pull` and run `./setup.sh` again — it now offers to remove `mysql/` for you — or use `./reset.sh`, which removes `html/` and `mysql/` together.

## [0.1.6] — 2026-10-19

### Fixed

- `./setup.sh --dev` (and so `./reset.sh --dev`) no longer leaves `html/node_modules` broken. Two `npm install` runs were writing it at once: `docker compose up -d` started the vite container, whose entrypoint installs node_modules when it finds none, while step `[5/6]` ran `npm install` in the app container on the same tree. The two deleted each other's directories, and Vite stopped with `npm error ENOTEMPTY` followed by `sh: 1: vite: not found`; restarting it failed with `Cannot find module` from inside the half-written tree. In development mode the stack now comes up with `--scale vite=0`, and vite is started right after step `[5/6]`, where its entrypoint finds node_modules complete and skips its own install. A vite container started on its own with no node_modules still installs them. It was a race, so it did not happen on every run (#62).

### Upgrade notes

Nothing to do unless a `--dev` setup already left you with a Vite container that will not start. In that case, update the installer with `git pull`, delete the half-written tree through the app container (it is owned by `www-data`, so the host user cannot) and run the setup again:

```bash
docker compose exec -T dixlase.test rm -rf /var/www/html/node_modules
./setup.sh --dev
```

Built-assets mode (`./setup.sh` with no `--dev`) was never affected, and no existing install is touched by updating the installer.

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
