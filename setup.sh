#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# Dixlase setup script
# Purpose: Clone the core from GitHub and build the Docker environment.
#
# Usage:
#   ./setup.sh                  # Built-assets mode (no Vite dev server)
#   ./setup.sh --dev            # Development mode (Vite hot-reload)
#   ./setup.sh <branch>         # Clone the specified branch (default: main)
#   ./setup.sh --dev <branch>   # Development mode + specified branch
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Once the containers have run, app-entrypoint.sh owns several paths
# under html/ as www-data (storage/, bootstrap/cache/,
# resources/src/common/css/, plugins/, themes/) so php-fpm can write
# there. On hosts that do not virtualize bind-mount ownership (Linux)
# the host user can then no longer delete those paths or create entries
# inside them, which breaks re-running this script. Run such operations
# through a throwaway root container instead — the same approach
# reset.sh uses. Best-effort: a machine without a usable docker daemon
# has not run the containers either, so the host-side path still works.
docker_root() {
    docker run --rm -v "$SCRIPT_DIR:/work" alpine sh -c "$1" 2>/dev/null || true
}

# Repository URLs can be overridden via environment variables. Default is public HTTPS.
REPO_URL="${DIXLASE_REPO_URL:-https://github.com/Dixlase/dixlase-core.git}"

# Parse arguments: --dev flag and branch name
DEV_MODE=false
BRANCH="main"
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        *) BRANCH="$arg" ;;
    esac
done

if [ "$DEV_MODE" = true ]; then
    MODE_LABEL="Development mode (Vite hot-reload)"
else
    # Not called "production mode": this stack is a local trial, and the name
    # invited people to treat it as hardened for a server. All it decides is
    # whether Vite serves the assets or they are built ahead of time.
    MODE_LABEL="Built-assets mode (no Vite dev server)"
fi

echo "========================================"
echo "  Dixlase Setup"
echo "  Mode:   $MODE_LABEL"
echo "  Branch: $BRANCH"
echo "========================================"
echo ""

# -------------------------------------------------
# 1. Clone the core from GitHub
# -------------------------------------------------
if [ -d "html" ]; then
    echo "[1/6] html/ already exists."
    read -r -p "  Delete and re-clone? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "  Deleting html/..."
        docker_root 'rm -rf /work/html'
        rm -rf html
        echo "  Cloning from GitHub..."
        git clone -b "$BRANCH" "$REPO_URL" html
    else
        echo "  Keeping existing html/."
    fi
else
    echo "[1/6] Cloning from GitHub..."
    git clone -b "$BRANCH" "$REPO_URL" html
fi

cd html

# git clone of core left an empty placeholder directory for every
# submodule listed in core's .gitmodules. themes/DixlaseOnePage now
# arrives with composer install in step [5/6]; plugins are left to the
# wizard. Remove the empty placeholders so html/ does not look
# half-installed. rmdir is safe: it only deletes empty directories,
# so anything already populated by a re-run or local work is left
# untouched.
if [ -f .gitmodules ]; then
    while IFS= read -r submodule_path; do
        if [ -d "$submodule_path" ] && rmdir "$submodule_path" 2>/dev/null; then
            echo "  Removed empty submodule placeholder: $submodule_path"
        fi
    done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
fi

cd ..

# -------------------------------------------------
# 2. Set up .env
# -------------------------------------------------
echo ""
echo "[2/6] Setting up .env..."

# Root .env (used by Docker Compose to interpolate ports / DB credentials).
# It holds the database passwords and the php-fpm reset token, so create it
# 0600 instead of inheriting the shell's umask (0644 on most systems, which
# on a multi-user host means every account can read them). An existing .env
# is left exactly as the operator has it, permissions included.
if [ ! -f ".env" ]; then
    (umask 077 && cp .env.example .env)
    chmod 600 .env
    echo "  Copied .env.example -> .env (for Docker Compose, mode 600)."
else
    echo "  .env already exists (skipped)."
fi

# Generate a random php-fpm opcache-reset token if .env does not already
# carry a non-empty one. docker-compose interpolates it into the app
# container's CORE_FPM_RESET_TOKEN, and the deployed core reads it on both
# ends of the /system/fpm-cache-reset call so web-triggered core updates
# can refresh php-fpm's opcache over HTTP instead of signalling php-fpm
# (PID 1), which the www-data worker cannot do.
CORE_FPM_RESET_TOKEN_VAL=$(grep '^CORE_FPM_RESET_TOKEN=' .env | cut -d'=' -f2- | tr -d '[:space:]"')
if [ -z "$CORE_FPM_RESET_TOKEN_VAL" ]; then
    NEW_FPM_RESET_TOKEN=$(openssl rand -hex 32)
    if grep -q '^CORE_FPM_RESET_TOKEN=' .env; then
        sed -i.bak "s|^CORE_FPM_RESET_TOKEN=.*|CORE_FPM_RESET_TOKEN=${NEW_FPM_RESET_TOKEN}|" .env && rm -f .env.bak
    else
        printf 'CORE_FPM_RESET_TOKEN=%s\n' "$NEW_FPM_RESET_TOKEN" >> .env
    fi
    echo "  Generated CORE_FPM_RESET_TOKEN for php-fpm opcache reset."
fi

# Derive NGINX_VARIANT from the HTTPS flag and COMPOSE_PROFILES from
# VITE / REDIS. Values are exported to setup.sh's process environment
# so docker-compose picks them up below; we deliberately do NOT write
# them back to .env (.env is user-owned). --dev forces VITE on.
HTTPS_VAL=$(grep '^HTTPS=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
if [ "$HTTPS_VAL" = "true" ] || [ "$HTTPS_VAL" = "1" ]; then
    NGINX_VARIANT=https
else
    NGINX_VARIANT=http
fi

VITE_VAL=$(grep '^VITE=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
REDIS_VAL=$(grep '^REDIS=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
CRON_VAL=$(grep '^CRON=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
TOOLS_VAL=$(grep '^TOOLS=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
if [ "$DEV_MODE" = true ]; then
    VITE_VAL=true
fi
COMPOSE_PROFILES=""
if [ "$VITE_VAL" = "true" ] || [ "$VITE_VAL" = "1" ]; then
    COMPOSE_PROFILES="dev"
fi
# REDIS defaults to false when unset/empty.
if [ "$REDIS_VAL" = "true" ] || [ "$REDIS_VAL" = "1" ]; then
    [ -n "$COMPOSE_PROFILES" ] && COMPOSE_PROFILES="${COMPOSE_PROFILES},redis" || COMPOSE_PROFILES="redis"
fi
# CRON defaults to true when unset/empty so the Laravel scheduler runs
# out of the box (required for automatic extension update checks).
# Operators that already invoke `php artisan schedule:run` from a host
# cron set CRON=false to opt out.
if [ -z "$CRON_VAL" ] || [ "$CRON_VAL" = "true" ] || [ "$CRON_VAL" = "1" ]; then
    [ -n "$COMPOSE_PROFILES" ] && COMPOSE_PROFILES="${COMPOSE_PROFILES},cron" || COMPOSE_PROFILES="cron"
fi
# TOOLS defaults to true when unset (Adminer + Mailpit), which is also what
# a .env written before this flag existed means. Both are published on
# 127.0.0.1 only; TOOLS=false does not start them at all.
if [ -z "$TOOLS_VAL" ] || [ "$TOOLS_VAL" = "true" ] || [ "$TOOLS_VAL" = "1" ]; then
    [ -n "$COMPOSE_PROFILES" ] && COMPOSE_PROFILES="${COMPOSE_PROFILES},tools" || COMPOSE_PROFILES="tools"
fi

export NGINX_VARIANT COMPOSE_PROFILES

echo "  Selected nginx variant: nginx.$NGINX_VARIANT.conf (HTTPS=$HTTPS_VAL)"
echo "  Active compose profiles: ${COMPOSE_PROFILES:-none} (VITE=$VITE_VAL REDIS=${REDIS_VAL:-false} CRON=${CRON_VAL:-true} TOOLS=${TOOLS_VAL:-true})"

# Warn when the default database credentials are still in place AND something
# is published past this machine. Either alone is a normal state: the defaults
# are a convenience on a loopback-only stack, and a reachable bind address is
# a deliberate choice. Together they are an open database.
EXPOSED_SERVICES=""
for bind_var in DB_BIND_ADDRESS ADMINER_BIND_ADDRESS MAILPIT_BIND_ADDRESS VITE_BIND_ADDRESS; do
    bind_val=$(grep "^${bind_var}=" .env | cut -d'=' -f2 | tr -d '[:space:]"')
    case "$bind_val" in
        "" | 127.0.0.1 | localhost | ::1) ;;
        *) EXPOSED_SERVICES="${EXPOSED_SERVICES} ${bind_var}=${bind_val}" ;;
    esac
done
DEFAULT_CREDENTIALS=""
for cred_var in DB_PASSWORD DB_ROOT_PASSWORD; do
    cred_val=$(grep "^${cred_var}=" .env | cut -d'=' -f2 | tr -d '[:space:]"')
    cred_example=$(grep "^${cred_var}=" .env.example | cut -d'=' -f2 | tr -d '[:space:]"')
    if [ -n "$cred_example" ] && [ "$cred_val" = "$cred_example" ]; then
        DEFAULT_CREDENTIALS="${DEFAULT_CREDENTIALS} ${cred_var}"
    fi
done
if [ -n "$EXPOSED_SERVICES" ] && [ -n "$DEFAULT_CREDENTIALS" ]; then
    echo ""
    echo "  --- WARNING: default credentials on a reachable address ---"
    echo "    Still at the .env.example defaults:$DEFAULT_CREDENTIALS"
    echo "    Published beyond this machine:$EXPOSED_SERVICES"
    echo "    Anyone who can reach those ports can sign in to the database."
    echo "    Either set every *_BIND_ADDRESS back to 127.0.0.1, or change the"
    echo "    passwords in .env and start over with ./reset.sh (MariaDB reads"
    echo "    them only when its data directory is created)."
    echo "  -----------------------------------------------------------"
    echo ""
fi

# Sync DEV_MODE with the effective VITE flag so step [6/6] and other
# downstream logic reflect what actually runs.
if [ "$VITE_VAL" = "true" ] || [ "$VITE_VAL" = "1" ]; then
    DEV_MODE=true
fi

# -------------------------------------------------
# 3. Generate SSL certificate
# -------------------------------------------------
echo ""
echo "[3/6] Generating SSL certificate..."

if [ -f "certs/localhost.crt" ] && [ -f "certs/localhost.key" ]; then
    echo "  Certificate already exists (skipped)."
else
    mkdir -p certs
    openssl genrsa -out certs/localhost.key 2048 2>/dev/null
    openssl req -new -key certs/localhost.key -out certs/localhost.csr \
        -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dixlase/OU=Local/CN=localhost" 2>/dev/null
    openssl x509 -req -days 365 -in certs/localhost.csr \
        -signkey certs/localhost.key -out certs/localhost.crt \
        -extfile <(printf "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1") 2>/dev/null
    rm -f certs/localhost.csr
    chmod 600 certs/localhost.key
    chmod 644 certs/localhost.crt
    echo "  Certificate generated."
fi

# -------------------------------------------------
# 4. Build and start Docker containers
# -------------------------------------------------
echo ""
echo "[4/6] Building and starting Docker containers..."
# If containers from a previous run exist, offer to recreate them.
# Recreation guarantees a clean state and avoids Docker Desktop bind-mount
# caching where freshly built host files are not visible to running containers.
KEPT_CONTAINERS=false
EXISTING_CONTAINERS=$(docker compose ps -aq 2>/dev/null | wc -l | tr -d ' ')
if [ "$EXISTING_CONTAINERS" -gt 0 ]; then
    echo "  Existing containers detected ($EXISTING_CONTAINERS)."
    read -r -p "  Recreate them for a clean start? (y/N): " recreate
    if [ "$recreate" = "y" ] || [ "$recreate" = "Y" ]; then
        echo "  Removing existing containers..."
        docker compose down
    else
        echo "  Keeping existing containers (in-place restart)."
        KEPT_CONTAINERS=true
    fi
fi
# Active profiles are picked up from COMPOSE_PROFILES exported above.
docker compose build
docker compose up -d

# `up -d` leaves an already-running container untouched, so the
# entrypoint's self-heal would not run against the html/ tree the steps
# above just rewrote — and the ownership handed back to the host user
# for the theme clone would stay that way. Restart the app container to
# make the promised in-place restart real.
if [ "$KEPT_CONTAINERS" = true ]; then
    echo "  Restarting the app container to re-apply container-side ownership..."
    docker compose restart dixlase.test
fi

# `up -d` starts what the active profiles name; it does not stop a container
# whose flag was just turned off. Switching VITE / REDIS / CRON / TOOLS off and
# re-running setup.sh therefore left the old container running, so the stack no
# longer matched .env — a Vite dev server outliving the switch back to
# built-assets mode being the one that matters. The only documented answer used
# to be ./reset.sh, which deletes the database to stop a container.
#
# Every command here names all profiles, because a service in an inactive
# profile cannot be addressed otherwise. `rm -sf` stops and removes the
# container; named volumes (Redis) are untouched.
DISABLED_SERVICES=""
case ",${COMPOSE_PROFILES}," in *,dev,*) ;; *) DISABLED_SERVICES="$DISABLED_SERVICES vite" ;; esac
case ",${COMPOSE_PROFILES}," in *,redis,*) ;; *) DISABLED_SERVICES="$DISABLED_SERVICES redis" ;; esac
case ",${COMPOSE_PROFILES}," in *,cron,*) ;; *) DISABLED_SERVICES="$DISABLED_SERVICES cron" ;; esac
case ",${COMPOSE_PROFILES}," in *,tools,*) ;; *) DISABLED_SERVICES="$DISABLED_SERVICES adminer mailpit" ;; esac
for disabled_service in $DISABLED_SERVICES; do
    if [ -n "$(COMPOSE_PROFILES=cron,dev,redis,tools docker compose ps -aq "$disabled_service" 2>/dev/null)" ]; then
        echo "  Removing the $disabled_service container (turned off in .env)..."
        COMPOSE_PROFILES=cron,dev,redis,tools docker compose rm -sf "$disabled_service" >/dev/null 2>&1 || true
    fi
done

# Wait for containers to start
echo "  Waiting for containers to start..."
sleep 5

# -------------------------------------------------
# 5. Install Laravel dependencies
# -------------------------------------------------
# composer/npm install are the only things setup.sh has to do before
# the wizard runs — everything else (.env, key:generate, migrate,
# storage:link, cache:clear, dls:tailwind:regenerate-plugin-sources)
# is handled by core's CheckInstallationReady middleware and
# InstallConfirmController during the wizard flow.
echo ""
echo "[5/6] Installing Laravel dependencies..."

# Reinstall because vendor/node_modules are missing on the host due to the volume mount
echo "  Running composer install..."
docker compose exec -T dixlase.test composer install --no-interaction

# Dump the autoload again. composer.local.json — which is what registers the
# PSR-4 roots of the bundled theme and of every installed plugin — is generated,
# so a release ZIP does not carry it: the install above dumps the autoload with
# nothing to merge, and core's post-autoload-dump script writes the file only
# afterwards. Without this second dump the site boots unable to load the theme's
# ServiceProvider, and the front page 500s on the theme's own helper.
#
# Core tries to repair this itself after the wizard installs the theme, but that
# call runs `PHP_BINARY composer …`, and under php-fpm PHP_BINARY is php-fpm:
# it prints its usage, exits 64, and the failure is only a warning in the log.
# Until that is fixed in core, this one line is what keeps a ZIP install working
# (it is a no-op when the maps are already correct).
echo "  Refreshing the composer autoload (picks up composer.local.json)..."
docker compose exec -T dixlase.test composer dump-autoload --optimize --no-interaction
echo "  Running npm install..."
docker compose exec -T dixlase.test npm install

# Seed the Tailwind plugin-sources stub the theme build @imports.
# Core's dls:tailwind:regenerate-plugin-sources normally writes it.
# On a fresh clone neither has happened yet, so seed an empty stub
# in the exact format core emits when no plugin contributes sources
# — the wizard / lifecycle commands overwrite it later with the
# real aggregator output. Keep PLUGIN_SOURCES in sync with core's
# PluginSourceAggregator::OUTPUT_PATH.
#
# This runs after composer install, which is what places the theme, and
# writes through the container: the running containers already own
# resources/src/common/css as www-data, so a host-side write there fails
# with "Permission denied" on hosts that do not virtualize bind-mount
# ownership (Linux).
if [ -f html/themes/DixlaseOnePage/package.json ]; then
    PLUGIN_SOURCES=html/resources/src/common/css/dixlase-tailwind-plugin-sources.css
    if [ ! -f "$PLUGIN_SOURCES" ]; then
        IN_CONTAINER="${PLUGIN_SOURCES#html/}"
        docker compose exec -T dixlase.test sh -c \
            "mkdir -p \"\$(dirname '$IN_CONTAINER')\" && cat > '$IN_CONTAINER' && chown www-data:www-data '$IN_CONTAINER'" <<'EOF'
/*
 * AUTO-GENERATED placeholder seeded by dixlase-docker-installer.
 * The Dixlase install wizard and plugin lifecycle commands overwrite
 * this file via php artisan dls:tailwind:regenerate-plugin-sources.
 */

/* No enabled plugin currently declares Tailwind content sources. */
EOF
        echo "  Seeded $PLUGIN_SOURCES placeholder for theme build."
    fi
fi

# -------------------------------------------------
# 6. Build assets (production mode only)
# -------------------------------------------------
# Read the actual ports from .env and build the CMS URL. Omit the port
# when it is the standard 80 / 443 for the chosen scheme.
APP_PORT_VAL=$(grep '^APP_PORT=' .env | cut -d'=' -f2)
APP_SSL_PORT_VAL=$(grep '^APP_SSL_PORT=' .env | cut -d'=' -f2)
FORWARD_ADMINER_PORT_VAL=$(grep '^FORWARD_ADMINER_PORT=' .env | cut -d'=' -f2)
FORWARD_MAILPIT_PORT_VAL=$(grep '^FORWARD_MAILPIT_PORT=' .env | cut -d'=' -f2)

if [ "$NGINX_VARIANT" = "https" ]; then
    [ "$APP_SSL_PORT_VAL" = "443" ] && APP_URL="https://localhost" || APP_URL="https://localhost:$APP_SSL_PORT_VAL"
else
    [ "$APP_PORT_VAL" = "80" ] && APP_URL="http://localhost" || APP_URL="http://localhost:$APP_PORT_VAL"
fi

echo ""
if [ "$DEV_MODE" = true ]; then
    echo "[6/6] Development mode: Vite dev server is running in the vite container..."
    echo "      Build skipped (hot-reload enabled)."
else
    echo "[6/6] Building frontend assets..."
    # Remove the hot file so the built assets are used
    docker compose exec -T dixlase.test rm -f public/hot
    docker compose exec -T dixlase.test npm run build

    # Build theme assets via core's dls:theme:build artisan: it runs
    # npm install + npm run build inside themes/<name>/ and creates the
    # public/assets/themes/<name> symlink. The theme's tailwind.css
    # @imports resources/src/common/css/dixlase-tailwind-plugin-sources.css,
    # which core's dls:tailwind:regenerate-plugin-sources rewrites every
    # time plugins change (and the install wizard calls it after migrate).
    # The stub it needs on a fresh clone was seeded in step [5/6].
    if [ -f html/themes/DixlaseOnePage/package.json ]; then
        echo "  Building theme assets (themes/DixlaseOnePage)..."
        docker compose exec -T dixlase.test php artisan dls:theme:build DixlaseOnePage
    fi

    # Restart web so nginx sees freshly built assets. Docker Desktop bind
    # mounts on macOS sometimes hide files that appeared after the container
    # started; restarting forces nginx to re-read the mounted directory.
    echo "  Restarting web to refresh asset mount..."
    docker compose restart web
fi

# Hand the whole html/ tree to www-data (the container app user). The clone
# (host user) and the root-run `docker compose exec` build steps above leave
# files owned by the host user and root; on Linux (no Docker Desktop UID
# virtualization) the www-data php-fpm workers then cannot write .env,
# public/ (storage:link + theme asset symlinks) or storage/logs, so the
# install wizard fails its permission checks and 500s. Chown once here, after
# every file-creating step, so a fresh install works out of the box (no-op on
# macOS). Best-effort so one odd file cannot abort the install.
# The install wizard writes APP_URL into html/.env from the URL the operator
# used, so flipping HTTPS afterwards leaves it on the other scheme and port.
# Laravel then builds asset URLs like https://localhost:40080 — the TLS scheme
# with the plain-HTTP port — and every stylesheet and script fails in the
# browser while the page itself still answers 200. Say so instead; the value is
# not ours to overwrite, because a site behind a reverse proxy legitimately
# names an external URL here.
if [ -f "html/.env" ]; then
    APP_URL_IN_HTML=$(grep '^APP_URL=' html/.env | cut -d'=' -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]')
    case "$APP_URL_IN_HTML" in
        "") ;;
        http://*) [ "$NGINX_VARIANT" = "https" ] && APP_URL_MISMATCH=yes ;;
        https://*) [ "$NGINX_VARIANT" = "http" ] && APP_URL_MISMATCH=yes ;;
    esac
    if [ "${APP_URL_MISMATCH:-no}" = "yes" ]; then
        echo ""
        echo "  --- APP_URL in html/.env does not match the mode you just selected ---"
        echo "    html/.env has: $APP_URL_IN_HTML"
        echo "    this stack now serves: $APP_URL"
        echo "    Laravel builds asset URLs from APP_URL, so pages will load but"
        echo "    their CSS and JS will not. Set APP_URL in html/.env to the line"
        echo "    above (and FORCE_SSL=true when serving over TLS), then run:"
        echo "      docker compose exec dixlase.test php artisan config:clear"
        echo "    Leave it as it is if a reverse proxy in front owns that URL."
        echo "  ----------------------------------------------------------------"
    fi
fi

echo ""
echo "  Setting html/ ownership to www-data (container app user)..."
# .git is excluded on purpose: update.sh runs git fetch / checkout / pull
# in html/ as the host user, and git has to write objects and refs under
# .git. update.sh passes its own safe.directory exception so git tolerates
# the www-data-owned worktree root.
docker compose exec -T dixlase.test \
    sh -c 'find /var/www/html -name .git -prune -o -exec chown www-data:www-data {} +' || true

# -------------------------------------------------
# Done
# -------------------------------------------------
# APP_URL / port values were already computed at the top of step [6/6];
# reuse them here for the final summary.

echo ""
echo "========================================"
echo "  Setup complete!"
echo "========================================"
echo ""
echo "  Access URLs:"
echo "    CMS:        $APP_URL"
echo "    Adminer:    http://localhost:$FORWARD_ADMINER_PORT_VAL"
echo "    Mailpit:    http://localhost:$FORWARD_MAILPIT_PORT_VAL"
echo ""
echo "  Next steps:"
echo "    1. Open $APP_URL in your browser."
echo "    2. The install wizard will appear."
echo "    3. After install, start operations in the admin panel."
echo ""
echo "  Useful commands:"
echo "    docker compose logs -f                  # View logs"
echo "    docker compose exec dixlase.test bash   # Open a shell in the container"
echo "    ./reset.sh                              # Full reset of the environment"
echo "    ./update.sh                             # Pull latest from GitHub"
echo ""
