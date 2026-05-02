# Dixlase Docker Installer

Dockerized installer for [Dixlase](https://github.com/Dixlase/dixlase-core) — a Laravel-based CMS. This repository provides a one-command setup that brings up the full stack (PHP-FPM, Nginx, MariaDB, Redis, Mailpit, Adminer) with sensible defaults.

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

After setup completes, open `https://localhost` in your browser. The first visit shows the Dixlase install wizard.

## What the setup script does

1. Clones the Dixlase core repository into `./html/`
2. Clones the default theme into `./html/themes/DixlaseOnePage/`
3. Copies `.env.example` to both `./.env` (Docker Compose) and `./html/.env` (Laravel)
4. Generates a self-signed TLS certificate in `./certs/`
5. Builds and starts the Docker containers
6. Runs `composer install`, `npm install`, `php artisan key:generate`, and (in production mode) `npm run build`

## Default URLs

| Service | URL |
| --- | --- |
| Dixlase CMS | `https://localhost` |
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

Brings up an extra `vite` container under the `dev` Docker Compose profile. Frontend changes are reflected via hot-reload at `https://localhost`.

To switch an existing setup between modes, run `./reset.sh --dev` or `./reset.sh`.

## Configuration

All host-side ports and database credentials can be overridden via `.env` (root). Edit it after `setup.sh` has run, then restart with `docker compose up -d`.

```env
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

If port `80` or `443` is already in use on your machine (Apache, IIS, etc.), set `APP_PORT=8080` and `APP_SSL_PORT=8443` (or any free ports) in `.env` before running `setup.sh`.

### Repository URL override

If you need to install from a fork or mirror, set:

```bash
export DIXLASE_REPO_URL=https://github.com/your-org/dixlase-core.git
export DIXLASE_THEME_REPO_URL=https://github.com/your-org/theme-dixlase-onepage.git
./setup.sh
```

### Optional: GitHub token for extension downloads

If you plan to install commercial extensions, set the `EXTENSION_GITHUB_TOKEN` value in `./html/.env` to a GitHub Classic PAT with `repo` scope.

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
├── nginx/nginx.conf        # Nginx vhost (HTTP→HTTPS, FastCGI, Vite proxy)
├── php/php.ini             # PHP runtime overrides (upload size, memory, etc.)
├── .env.example            # Environment template (copied to .env on setup)
├── setup.sh                # Initial setup
├── update.sh               # Pull latest core and re-run migrations
├── reset.sh                # Wipe state and re-run setup
└── entrypoint.sh           # Vite container entrypoint
```

## License

Released under the AGPL v3 license, consistent with [Dixlase Core](https://github.com/Dixlase/dixlase-core).
