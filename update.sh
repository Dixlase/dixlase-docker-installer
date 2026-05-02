#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# Dixlase source update
# Pulls the latest code from GitHub and refreshes the container.
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BRANCH="${1:-main}"

echo "========================================"
echo "  Dixlase - Source update"
echo "  Branch: $BRANCH"
echo "========================================"
echo ""

if [ ! -d "html" ]; then
    echo "  html/ not found. Run setup.sh first."
    exit 1
fi

# Git pull
echo "[1/4] Pulling latest from GitHub..."
cd html
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"
cd ..

# Update Composer / npm dependencies
echo ""
echo "[2/4] Updating dependencies..."
docker compose exec -T dixlase.test composer install --no-interaction
echo "  composer install complete."

# Run migrations
echo ""
echo "[3/4] Running migrations..."
docker compose exec -T dixlase.test php artisan migrate --force
echo "  Migrations complete."

# Clear cache
echo ""
echo "[4/4] Clearing caches..."
docker compose exec -T dixlase.test php artisan config:clear
docker compose exec -T dixlase.test php artisan cache:clear
docker compose exec -T dixlase.test php artisan view:clear
echo "  Caches cleared."

echo ""
echo "========================================"
echo "  Update complete!"
echo "========================================"
