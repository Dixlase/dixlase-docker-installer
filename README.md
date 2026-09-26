# Dixlase Docker Installer

Dockerized installer for [Dixlase](https://github.com/Dixlase/dixlase-core).  
One command brings up the full stack (PHP-FPM / Nginx / MariaDB / Redis / Mailpit / Adminer), clones core and the default theme, generates a self-signed TLS cert, and installs PHP / JS dependencies inside the containers.

For Japanese, see [README.ja.md](./README.ja.md).

## Prerequisites

- **Docker Desktop** (macOS / Windows) or **Docker Engine + Docker Compose v2** (Linux)
- **Git**
- **OpenSSL** (used to generate a self-signed certificate for `localhost`)

## Quick Start

```bash
git clone https://github.com/Dixlase/dixlase-docker-installer.git dixlase
cd dixlase
./setup.sh
```

After setup completes, open `http://localhost:40080` in your browser.  
The first visit shows the Dixlase install wizard.  
(Set `HTTPS=true` in `.env` and re-run `./setup.sh` to switch to HTTPS with a bundled
self-signed certificate. On a site that was already installed over HTTP, also change
`APP_URL` in `html/.env` to the HTTPS URL and set `FORCE_SSL=true`, then
`docker compose exec dixlase.test php artisan config:clear` — Laravel builds asset URLs
from `APP_URL`, so pages would load without their CSS and JS otherwise. `setup.sh` warns
when the two disagree.)

## Default URLs

| Service | URL |
| --- | --- |
| Dixlase CMS | `http://localhost:40080` (`https://localhost:40443` when `HTTPS=true`) |
| Adminer (DB GUI) | `http://localhost:40081` |
| Mailpit (mail catcher) | `http://localhost:40025` |

Only the CMS is published on all interfaces. Adminer, Mailpit, MariaDB and the
Vite dev server are bound to `127.0.0.1`, so they answer from this machine only —
neither Adminer nor Mailpit has a password of its own. Adminer and Mailpit are
also behind the `TOOLS` flag in `.env` (on by default); set `TOOLS=false` and
re-run `./setup.sh` to not start them at all.

## Modes

### Built-assets mode (default)

```bash
./setup.sh
```

Builds frontend assets with `npm run build`. The Vite dev server is **not** started.
(This used to be called "production mode", which read as a promise the stack does
not make — see "Using this on a server" below.)

### Development mode (Vite hot-reload)

```bash
./setup.sh --dev
```

Brings up an extra `vite` container under the `dev` Compose profile. Frontend changes are reflected via hot-reload at `http://localhost:40080` (`https://localhost:40443` when `HTTPS=true`).

To switch an existing setup between modes, run `./reset.sh --dev` or `./reset.sh`.

## Configuration

All host-side ports and DB credentials can be overridden via `.env` (root). Edit it after `setup.sh` has run, then restart with `docker compose up -d`.

```env
HTTPS=false                  # set to true to use TLS with a self-signed cert
VITE=false                   # set to true to start the Vite dev server (= --dev)
REDIS=false                  # set to true to start the Redis container
CRON=true                    # run Laravel's scheduler every minute
TOOLS=true                   # start Adminer and Mailpit (127.0.0.1 only)
CONTAINER_PREFIX=dixlase     # name containers <prefix>-app, <prefix>-mysql, ...
COMPOSE_PROJECT_NAME=dixlase # group label in Docker Desktop / `docker compose ls`
APP_PORT=40080         # "4" = D = Dixlase, alphabetically the 4th letter
APP_SSL_PORT=40443
FORWARD_DB_PORT=40306
FORWARD_ADMINER_PORT=40081
FORWARD_MAILPIT_PORT=40025
FORWARD_VITE_PORT=40173      # Redis has no host-side port on purpose

DB_BIND_ADDRESS=127.0.0.1    # the tools answer from this machine only;
ADMINER_BIND_ADDRESS=127.0.0.1
MAILPIT_BIND_ADDRESS=127.0.0.1
VITE_BIND_ADDRESS=127.0.0.1

DB_DATABASE=dixlase
DB_USERNAME=dixlase
DB_PASSWORD=dixlase
DB_ROOT_PASSWORD=root
```

After flipping `HTTPS`, `VITE`, or `REDIS`, re-run `./setup.sh` so the derived `NGINX_VARIANT` / `COMPOSE_PROFILES` take effect.  
`.env` stays user-owned — those derived values are exported by `setup.sh` and never written back. The same applies after `docker compose down`: prefer `./setup.sh` (idempotent) over raw `docker compose up -d` so profiled services (Vite / Redis) come back up.

When you enable `REDIS`, also point Laravel's `CACHE_STORE` and `SESSION_DRIVER` at `redis`. The `4xxxx` port namespace ("4" = D = Dixlase, alphabetically the 4th letter) avoids common host-port conflicts; if you prefer `80` / `443`, set `APP_PORT=80` / `APP_SSL_PORT=443` in `.env` before running `setup.sh`.

## Using this on a server

The defaults are built for a local trial: the database password is `dixlase`, the
MariaDB root password is `root`, and the tools that accept them have no password
of their own. That is fine while everything but the site listens on `127.0.0.1`,
and an open door as soon as it does not. Before you expose this host:

- **Change `DB_PASSWORD` and `DB_ROOT_PASSWORD` in `.env`.** MariaDB reads them
  only when its data directory is created, so do it before the first
  `./setup.sh`, or change them inside MariaDB afterwards (or start over with
  `./reset.sh`, which deletes the database).
- **Leave every `*_BIND_ADDRESS` at `127.0.0.1`.** `setup.sh` warns when a
  default password is still in place and something is bound wider than
  loopback. Reach the tools through an SSH tunnel instead:
  `ssh -L 40081:127.0.0.1:40081 you@host`.
- **Do not run `--dev` (`VITE=true`) on a reachable host.** The Vite dev server
  can read files under `html/` through its `/@fs/` paths.
- **Consider `TOOLS=false`** so Adminer and Mailpit are not started at all.
- The host's SSH keys are **not** mounted into the container. If you deploy with
  the DixlaseDeploy plugin, opt in through `docker-compose.deploy.yml` — anything
  running in the container can read those keys, install scripts included.

`SECURITY.md` has the full list of what this stack does and does not protect.

### Repository URL override

Set these to install from a fork or mirror:

```bash
export DIXLASE_REPO_URL=https://github.com/your-org/dixlase-core.git
export DIXLASE_THEME_REPO_URL=https://github.com/your-org/theme-dixlase-onepage.git
./setup.sh
```

## Localization

Installer comments and messages default to English. Switch them with the bundled converter:

```bash
./convert-comments.sh ja              # all files: English -> Japanese
./convert-comments.sh ja setup.sh     # one file
./convert-comments.sh ja --reverse    # all files: Japanese -> English (revert)
```

Translation dictionaries live at `lang/<locale>/<source-path>.tsv` (tab-separated `<english-text>\t<locale-text>` pairs).  
See [CLAUDE.md](./CLAUDE.md) for the format and how to add a new locale.

## Useful commands

```bash
docker compose logs -f                  # tail all container logs
docker compose exec dixlase.test bash   # open a shell inside the app container
./update.sh                             # update the core checkout and refresh the stack
./reset.sh                              # destroy DB / source / volumes and re-run setup
```

## Updating

```bash
./update.sh                 # fast-forward html/ to origin/main, then refresh the stack
./update.sh <branch>        # the same, against another branch
./update.sh --dev           # skip the asset build (the Vite dev server serves them)
```

`update.sh` advances the **git checkout** in `html/`: it fast-forwards the branch, re-runs
`composer install` (passing the host's `~/.composer/auth.json` through, which private packages
such as the bundled theme need), realigns the migration bookkeeping with
`dls:migration:resync` (required while core still renumbers its baseline migrations),
runs the migrations, rebuilds the frontend assets and reconciles the core version ledger.
It never guesses: a worktree with local changes to tracked files, a detached `HEAD`, or a
history that no longer fast-forwards stops the run and names the command that resolves it.

A site running a **released** core should update with `php artisan dls:core:update` instead.
That path takes a backup, holds a maintenance window and can roll back; `update.sh` does
none of that.

```bash
./reset.sh                  # destroy DB / source / volumes, then re-run setup
./reset.sh --dev            # the same, re-setup in development mode
./reset.sh --images         # also remove the images built for this stack
./reset.sh -y               # skip the confirmation prompt
```

`reset.sh` keeps `.env` and `certs/`; everything it deletes is listed before it asks.

## Troubleshooting

### Wizard does not start; front page shows `No hint path defined for [themes]`

Cause: `html/` was wiped but the **MariaDB data (`mysql/` directory or named volume) was kept**. Core's `CheckInstallationReady` middleware sees the leftover migrations, decides the install is complete, and **self-heals `.env` by setting `INSTALLED=true`** — which skips the wizard. The warning is logged to `storage/logs/laravel.log`:

```
CheckInstallationReady: database shows an installed application
but the INSTALLED env flag was false. .env has been auto-restored
to INSTALLED=true...
```

Fix: wipe DB and `html/` together with `./reset.sh` (drops containers, named volumes, `html/`, and `mysql/`, then re-runs setup). After that, opening `/` redirects to `/install` and the wizard runs against an empty DB.

## License

This installer (Dockerfiles, shell scripts, configuration templates) is released under the [MIT License](./LICENSE) so it can be freely forked, modified, and adapted.

The Dixlase application itself is licensed separately under AGPL v3 — see [Dixlase Core](https://github.com/Dixlase/dixlase-core).
