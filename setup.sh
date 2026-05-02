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

COMPOSE_PROFILE_ARGS=()
if [ "$DEV_MODE" = true ]; then
    COMPOSE_PROFILE_ARGS=(--profile dev)
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

# Laravel .env (used by the application)
if [ ! -f "html/.env" ]; then
    cp .env.example html/.env
    echo "  Copied .env.example -> html/.env (for Laravel)."
else
    echo "  html/.env already exists (skipped)."
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
docker compose "${COMPOSE_PROFILE_ARGS[@]}" build
docker compose "${COMPOSE_PROFILE_ARGS[@]}" up -d

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

# Generate APP_KEY
docker compose exec -T dixlase.test php artisan key:generate --force
echo "  Generated APP_KEY."

# Create the storage symlink
docker compose exec -T dixlase.test php artisan storage:link 2>/dev/null || true
echo "  Created storage symlink."

# Clear caches (skipped if DB does not exist yet)
docker compose exec -T dixlase.test php artisan config:clear
docker compose exec -T dixlase.test php artisan cache:clear 2>/dev/null || true
echo "  Cleared caches."

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
APP_SSL_PORT_VAL=$(grep '^APP_SSL_PORT=' .env | cut -d'=' -f2)
FORWARD_ADMINER_PORT_VAL=$(grep '^FORWARD_ADMINER_PORT=' .env | cut -d'=' -f2)
FORWARD_MAILPIT_PORT_VAL=$(grep '^FORWARD_MAILPIT_PORT=' .env | cut -d'=' -f2)

# Omit the port from the URL when it is the standard 443/80
[ "$APP_SSL_PORT_VAL" = "443" ] && SSL_URL="https://localhost" || SSL_URL="https://localhost:$APP_SSL_PORT_VAL"

echo ""
echo "========================================"
echo "  Setup complete!"
echo "========================================"
echo ""
echo "  Access URLs:"
echo "    CMS:        $SSL_URL"
echo "    Adminer:    http://localhost:$FORWARD_ADMINER_PORT_VAL"
echo "    Mailpit:    http://localhost:$FORWARD_MAILPIT_PORT_VAL"
echo ""
echo "  Next steps:"
echo "    1. Open $SSL_URL in your browser."
echo "    2. The install wizard will appear."
echo "    3. After install, start operations in the admin panel."
echo ""
echo "  Useful commands:"
echo "    docker compose logs -f                  # View logs"
echo "    docker compose exec dixlase.test bash   # Open a shell in the container"
echo "    ./reset.sh                              # Full reset of the environment"
echo "    ./update.sh                             # Pull latest from GitHub"
echo ""
