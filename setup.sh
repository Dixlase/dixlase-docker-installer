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
rm -rf themes/DixlaseOnePage
echo "  Fetching themes/DixlaseOnePage..."
git clone "$THEME_REPO_URL" themes/DixlaseOnePage

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
# Active profiles are picked up from COMPOSE_PROFILES exported above.
docker compose build
docker compose up -d

# Wait for containers to start
echo "  Waiting for containers to start..."
sleep 5

# -------------------------------------------------
# 5. Set up Laravel
# -------------------------------------------------
echo ""
echo "[5/6] Setting up Laravel..."

# Reinstall because vendor/node_modules are missing on the host due to the volume mount
echo "  Running composer install..."
docker compose exec -T dixlase.test composer install --no-interaction
echo "  Running npm install..."
docker compose exec -T dixlase.test npm install

# Artisan steps require html/.env. On a clean install that file is created by
# the Dixlase install wizard, so these steps run only on re-runs.
if [ -f html/.env ]; then
    docker compose exec -T dixlase.test php artisan key:generate --force
    echo "  Generated APP_KEY."

    docker compose exec -T dixlase.test php artisan storage:link 2>/dev/null || true
    echo "  Created storage symlink."

    docker compose exec -T dixlase.test php artisan config:clear
    docker compose exec -T dixlase.test php artisan cache:clear 2>/dev/null || true
    echo "  Cleared caches."
else
    echo "  Skipping artisan steps — the install wizard will run them."
fi

# -------------------------------------------------
# 6. Build assets (production mode only)
# -------------------------------------------------
echo ""
if [ "$DEV_MODE" = true ]; then
    echo "[6/6] Development mode: Vite dev server is running in the vite container..."
    echo "      Build skipped (hot-reload enabled)."
else
    echo "[6/6] Building frontend assets..."
    # Remove the hot file so the built assets are used
    docker compose exec -T dixlase.test rm -f public/hot
    docker compose exec -T dixlase.test npm run build
fi

# -------------------------------------------------
# Done
# -------------------------------------------------
# Read the actual ports from .env and display them
APP_PORT_VAL=$(grep '^APP_PORT=' .env | cut -d'=' -f2)
APP_SSL_PORT_VAL=$(grep '^APP_SSL_PORT=' .env | cut -d'=' -f2)
FORWARD_ADMINER_PORT_VAL=$(grep '^FORWARD_ADMINER_PORT=' .env | cut -d'=' -f2)
FORWARD_MAILPIT_PORT_VAL=$(grep '^FORWARD_MAILPIT_PORT=' .env | cut -d'=' -f2)

# Build CMS URL based on the HTTPS flag; omit the port when it is the
# standard 80 / 443 for the chosen scheme.
if [ "$NGINX_VARIANT" = "https" ]; then
    [ "$APP_SSL_PORT_VAL" = "443" ] && APP_URL="https://localhost" || APP_URL="https://localhost:$APP_SSL_PORT_VAL"
else
    [ "$APP_PORT_VAL" = "80" ] && APP_URL="http://localhost" || APP_URL="http://localhost:$APP_PORT_VAL"
fi

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
