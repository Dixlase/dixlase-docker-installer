# Dixlase Docker Installer

Dockerized installer for [Dixlase](https://github.com/Dixlase/dixlase-core) . This repository provides a one-command setup that brings up the full stack (PHP-FPM, Nginx, MariaDB, Redis, Mailpit, Adminer) with sensible defaults.

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

After setup completes, open `http://localhost` in your browser. The first visit shows the Dixlase install wizard. (Set `HTTPS=true` in `.env` and re-run `./setup.sh` to switch to HTTPS with a bundled self-signed certificate.)

## What the setup script does

1. Clones the Dixlase core repository into `./html/`
2. Clones the default theme into `./html/themes/DixlaseOnePage/`
3. Copies `.env.example` to `./.env` (used by Docker Compose for ports and DB credentials). Laravel's own `./html/.env` is created by the Dixlase install wizard on first browser visit.
4. Generates a self-signed TLS certificate in `./certs/`
5. Builds and starts the Docker containers
6. Runs `composer install`, `npm install`, and (in production mode) `npm run build`

## Default URLs

| Service | URL |
| --- | --- |
| Dixlase CMS | `http://localhost` (or `https://localhost` when `HTTPS=true`) |
| Adminer (DB GUI) | `http://localhost:40081` |
| Mailpit (mail catcher) | `http://localhost:40025` |

## Modes

### Production mode (default)

```bash
./setup.sh
```

Builds frontend assets with `npm run build`. The Vite dev server is **not** started.

### Development mode (Vite hot-reload)

```bash
./setup.sh --dev
```

Brings up an extra `vite` container under the `dev` Docker Compose profile. Frontend changes are reflected via hot-reload at `http://localhost` (or `https://localhost` when `HTTPS=true`).

To switch an existing setup between modes, run `./reset.sh --dev` or `./reset.sh`.

## Configuration

All host-side ports and database credentials can be overridden via `.env` (root). Edit it after `setup.sh` has run, then restart with `docker compose up -d`.

```env
HTTPS=false                  # set to true to use TLS with a self-signed cert
VITE=false                   # set to true to start the Vite dev server (= --dev)
REDIS=false                  # set to true to start the Redis container
CONTAINER_PREFIX=dixlase     # name containers <prefix>-app, <prefix>-mysql, ...
COMPOSE_PROJECT_NAME=dixlase # group label in Docker Desktop / `docker compose ls`
APP_PORT=40080         # "4" = D = Dixlase, alphabetically the 4th letter
APP_SSL_PORT=40443
FORWARD_DB_PORT=40306
FORWARD_ADMINER_PORT=40081
FORWARD_MAILPIT_PORT=40025
FORWARD_REDIS_PORT=40379
FORWARD_VITE_PORT=40173

DB_DATABASE=dixlase
DB_USERNAME=dixlase
DB_PASSWORD=dixlase
DB_ROOT_PASSWORD=root
```

After flipping `HTTPS`, `VITE`, or `REDIS`, re-run `./setup.sh` so Docker Compose picks up the matching nginx config and active compose profiles. The derived `NGINX_VARIANT` / `COMPOSE_PROFILES` are exported by `setup.sh` for its own `docker compose up` call and are *not* written back to `.env` — `.env` stays user-owned. The same applies after `docker compose down`: raw `docker compose up -d` from a fresh shell will skip profiled services (Vite, Redis), so prefer `./setup.sh` (idempotent) to bring everything back up.

When you enable `REDIS`, also point Laravel's `CACHE_STORE` and `SESSION_DRIVER` at `redis`.

The defaults use the `4xxxx` namespace ("4" = D = Dixlase, alphabetically the 4th letter) so they do not collide with services already bound to standard ports. If you have no conflict and prefer `80` / `443`, set `APP_PORT=80` and `APP_SSL_PORT=443` in `.env` before running `setup.sh`.

### Repository URL override

If you need to install from a fork or mirror, set:

```bash
export DIXLASE_REPO_URL=https://github.com/your-org/dixlase-core.git
export DIXLASE_THEME_REPO_URL=https://github.com/your-org/theme-dixlase-onepage.git
./setup.sh
```

## Localization

Comments and user-facing messages in the installer scripts default to English. To switch them to Japanese (or back), use the bundled converter:

```bash
./convert-comments.sh ja              # All files: English -> Japanese
./convert-comments.sh ja setup.sh     # One file: English -> Japanese
./convert-comments.sh ja --reverse    # All files: Japanese -> English (revert)
```

Translation dictionaries live at `lang/<locale>/<source-path>.tsv` (tab-separated `<english-text>\t<locale-text>` pairs). To add a new locale or extend an existing one, drop a new TSV next to the existing files; see [CLAUDE.md](./CLAUDE.md) for the format.

## Useful commands

```bash
docker compose logs -f                  # tail all container logs
docker compose exec dixlase.test bash   # open a shell inside the app container
./update.sh                             # git pull the core and run migrations
./reset.sh                              # destroy DB / source / volumes and re-run setup
```

## Repository layout

```
.
├── Dockerfile              # PHP-FPM 8.3 + Composer + Node 20
├── Dockerfile.vite         # Vite dev server (only used with --dev)
├── docker-compose.yml      # Service definitions
├── nginx/nginx.http.conf   # Nginx vhost — HTTP only, no redirect (HTTPS=false)
├── nginx/nginx.https.conf  # Nginx vhost — HTTP→HTTPS redirect + TLS (HTTPS=true)
├── php/php.ini             # PHP runtime overrides (upload size, memory, etc.)
├── .env.example            # Environment template (copied to .env on setup)
├── setup.sh                # Initial setup
├── update.sh               # Pull latest core and re-run migrations
├── reset.sh                # Wipe state and re-run setup
├── convert-comments.sh     # Switch script comments / messages between locales
├── entrypoint.sh           # Vite container entrypoint
└── lang/{en,ja}/           # Translation dictionaries (TSV)
```

## Troubleshooting

### The install wizard does not start; the front page shows `No hint path defined for [themes]` instead

Symptom: after wiping `html/`, re-extracting the source, and running `composer install` + `npm install` + `npm run build`, opening `http://localhost:<port>/` returns a 500 with `InvalidArgumentException: No hint path defined for [themes]` (or skips the install wizard and tries to render the front page).

Cause: the **MariaDB data volume / `mysql/` directory was not wiped along with `html/`**. The core's `CheckInstallationReady` middleware detects the leftover migrations, decides "the database already shows a completed install", and **self-heals `.env` by writing `INSTALLED=true`** — preventing the install wizard from running. The middleware logs a warning to `storage/logs/laravel.log` whenever this happens:

```
CheckInstallationReady: database shows an installed application
but the INSTALLED env flag was false. .env has been auto-restored
to INSTALLED=true...
```

This behaviour is intentional and correct for production (it recovers from an accidentally deleted `.env`), but it gets in the way when you intentionally want to re-test the install flow from a clean state.

Fix: also wipe the database when re-testing. The canonical one-shot path is:

```bash
./reset.sh                              # destroys containers, named volumes, html/, AND mysql/, then re-runs setup
```

If you prefer to wipe manually:

```bash
docker compose down -v                  # stop and delete THIS project's containers + named volumes
rm -rf mysql                            # delete the bind-mounted MariaDB data
find html -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
docker compose up -d                    # restart so the wizard can boot against an empty DB
```

After this, opening `/` redirects to `/install` and the wizard runs against an empty database.

## License

This installer (Dockerfiles, shell scripts, configuration templates) is released under the [MIT License](./LICENSE) so it can be freely forked, modified, and adapted for custom deployments.

The Dixlase application itself is licensed separately under AGPL v3 — see [Dixlase Core](https://github.com/Dixlase/dixlase-core).
