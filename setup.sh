#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# Dixlase setup script
# Purpose: Clone the core from GitHub and build the Docker environment.
#
# Usage:
#   ./setup.sh                  # Production mode (pre-built assets)
#   ./setup.sh --dev            # Development mode (Vite hot-reload)
#   ./setup.sh <branch>         # Clone the specified branch (default: main)
#   ./setup.sh --dev <branch>   # Development mode + specified branch
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Repository URLs can be overridden via environment variables. Default is public HTTPS.
REPO_URL="${DIXLASE_REPO_URL:-https://github.com/Dixlase/dixlase-core.git}"
THEME_REPO_URL="${DIXLASE_THEME_REPO_URL:-https://github.com/Dixlase/theme-dixlase-onepage.git}"

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
    MODE_LABEL="Production mode (pre-built assets)"
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

# -------------------------------------------------
# 1.5. Fetch submodules (themes etc.)
# -------------------------------------------------
echo ""
echo "[1.5/6] Initializing submodules..."
cd html
# Clone directly instead of using a submodule (handles commits the core may not reach)
# Mirror the html/ prompt: if themes/DixlaseOnePage already has content
# (user kept html/ above, or has local theme work), ask before
# overwriting; otherwise (fresh clone or empty submodule placeholder)
# just clone.
if [ -d "themes/DixlaseOnePage" ] && [ -n "$(ls -A themes/DixlaseOnePage 2>/dev/null)" ]; then
    echo "  themes/DixlaseOnePage already exists."
    read -r -p "  Delete and re-clone? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "  Deleting themes/DixlaseOnePage..."
        rm -rf themes/DixlaseOnePage
        echo "  Fetching themes/DixlaseOnePage..."
        git clone "$THEME_REPO_URL" themes/DixlaseOnePage
    else
        echo "  Keeping existing themes/DixlaseOnePage."
    fi
else
    rm -rf themes/DixlaseOnePage
    echo "  Fetching themes/DixlaseOnePage..."
    git clone "$THEME_REPO_URL" themes/DixlaseOnePage
fi

# git clone of core left an empty placeholder directory for every
# submodule listed in core's .gitmodules. Anything not explicitly
# cloned above (plugins, additional themes) is left to the install
# wizard. Remove the empty placeholders so html/ does not look
# half-installed. rmdir is safe: it only deletes empty directories,
# so any submodule we have already populated (themes/DixlaseOnePage
# above, or anything the wizard added on a re-run) is left untouched.
if [ -f .gitmodules ]; then
    while IFS= read -r submodule_path; do
        if [ -d "$submodule_path" ] && rmdir "$submodule_path" 2>/dev/null; then
            echo "  Removed empty submodule placeholder: $submodule_path"
        fi
    done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
fi

cd ..
echo "  Submodule fetch complete."

# -------------------------------------------------
# 2. Set up .env
# -------------------------------------------------
echo ""
echo "[2/6] Setting up .env..."

# Root .env (used by Docker Compose to interpolate ports / DB credentials)
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "  Copied .env.example -> .env (for Docker Compose)."
else
    echo "  .env already exists (skipped)."
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

export NGINX_VARIANT COMPOSE_PROFILES

echo "  Selected nginx variant: nginx.$NGINX_VARIANT.conf (HTTPS=$HTTPS_VAL)"
echo "  Active compose profiles: ${COMPOSE_PROFILES:-none} (VITE=$VITE_VAL REDIS=${REDIS_VAL:-false})"

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
EXISTING_CONTAINERS=$(docker compose ps -aq 2>/dev/null | wc -l | tr -d ' ')
if [ "$EXISTING_CONTAINERS" -gt 0 ]; then
    echo "  Existing containers detected ($EXISTING_CONTAINERS)."
    read -r -p "  Recreate them for a clean start? (y/N): " recreate
    if [ "$recreate" = "y" ] || [ "$recreate" = "Y" ]; then
        echo "  Removing existing containers..."
        docker compose down
    else
        echo "  Keeping existing containers (in-place restart)."
    fi
fi
# Active profiles are picked up from COMPOSE_PROFILES exported above.
docker compose build
docker compose up -d

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
echo "  Running npm install..."
docker compose exec -T dixlase.test npm install

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
    # @imports resources/css/dixlase-tailwind-plugin-sources.css, which
    # core's dls:tailwind:regenerate-plugin-sources rewrites every time
    # plugins change (and the install wizard calls it after migrate).
    # On a fresh clone neither has happened yet, so seed an empty stub
    # in the exact format core emits when no plugin contributes sources
    # — the wizard / lifecycle commands overwrite it later with the
    # real aggregator output.
    if [ -f html/themes/DixlaseOnePage/package.json ]; then
        PLUGIN_SOURCES=html/resources/css/dixlase-tailwind-plugin-sources.css
        if [ ! -f "$PLUGIN_SOURCES" ]; then
            mkdir -p "$(dirname "$PLUGIN_SOURCES")"
            cat > "$PLUGIN_SOURCES" <<'EOF'
/*
 * AUTO-GENERATED placeholder seeded by dixlase-docker-installer.
 * The Dixlase install wizard and plugin lifecycle commands overwrite
 * this file via php artisan dls:tailwind:regenerate-plugin-sources.
 */

/* No enabled plugin currently declares Tailwind content sources. */
EOF
            echo "  Seeded $PLUGIN_SOURCES placeholder for theme build."
        fi
        echo "  Building theme assets (themes/DixlaseOnePage)..."
        docker compose exec -T dixlase.test php artisan dls:theme:build DixlaseOnePage
    fi

    # Restart web so nginx sees freshly built assets. Docker Desktop bind
    # mounts on macOS sometimes hide files that appeared after the container
    # started; restarting forces nginx to re-read the mounted directory.
    echo "  Restarting web to refresh asset mount..."
    docker compose restart web
fi

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
