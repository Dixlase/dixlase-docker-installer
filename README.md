# Dixlase Docker Installer

Dockerized installer for [Dixlase](https://github.com/Dixlase/dixlase-core) . This repository provides a one-command setup that brings up the full stack (PHP-FPM, Nginx, MariaDB, Redis, Mailpit, Adminer) with sensible defaults.

For Japanese, see [README.ja.md](./README.ja.md).

## Prerequisites

- **Docker Desktop** (macOS / Windows) or **Docker Engine + Docker Compose v2** (Linux)
- **Git**
- **OpenSSL** (used to generate a self-signed certificate for `localhost`)

## Quick Start

```bash
git clone https://github.com/Dixlase/dixlase-installer-docker.git dixlase
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
| Adminer (DB GUI) | `http://localhost:8081` |
| Mailpit (mail catcher) | `http://localhost:8025` |

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
HTTPS=false           # set to true to use TLS with a self-signed cert
VITE=false            # set to true to start the Vite dev server (= --dev)
REDIS=true            # set to false to skip the Redis container
APP_PORT=80
APP_SSL_PORT=443
FORWARD_DB_PORT=3306
FORWARD_ADMINER_PORT=8081
FORWARD_MAILPIT_PORT=8025
FORWARD_REDIS_PORT=6379
FORWARD_VITE_PORT=5173

DB_DATABASE=dixlase
DB_USERNAME=dixlase
DB_PASSWORD=password
DB_ROOT_PASSWORD=root
```

After flipping `HTTPS`, `VITE`, or `REDIS`, re-run `./setup.sh` so Docker Compose picks up the matching nginx config and active compose profiles. If you turn `REDIS` off, also point Laravel's `CACHE_STORE` and `SESSION_DRIVER` away from `redis`.

If port `80` or `443` is already in use on your machine (Apache, IIS, etc.), set `APP_PORT=8080` and `APP_SSL_PORT=8443` (or any free ports) in `.env` before running `setup.sh`.

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

## License

This installer (Dockerfiles, shell scripts, configuration templates) is released under the [MIT License](./LICENSE) so it can be freely forked, modified, and adapted for custom deployments.

The Dixlase application itself is licensed separately under AGPL v3 — see [Dixlase Core](https://github.com/Dixlase/dixlase-core).
