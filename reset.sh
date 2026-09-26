#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# Dixlase complete reset
# Deletes all DB / source / Docker volumes and rebuilds from scratch.
#
# Usage:
#   ./reset.sh             # Re-setup in production mode
#   ./reset.sh --dev       # Re-setup in development mode
#   ./reset.sh --images    # Also remove the images built for this stack
#   ./reset.sh -y          # Skip the confirmation prompt
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --images and -y are consumed here; everything else (--dev, a branch name)
# is passed on to setup.sh unchanged.
REMOVE_IMAGES=false
ASSUME_YES=false
SETUP_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --images) REMOVE_IMAGES=true ;;
        -y|--yes) ASSUME_YES=true ;;
        *) SETUP_ARGS+=("$arg") ;;
    esac
done

echo "========================================"
echo "  Dixlase - Full reset"
echo "========================================"
echo ""
echo "  The following will be deleted:"
echo "    - Docker containers and volumes"
echo "    - html/ (source code)"
echo "    - mysql/ (database files)"
if [ "$REMOVE_IMAGES" = true ]; then
    echo "    - the Docker images built for this stack"
fi
echo ""
echo "  Kept: .env, certs/ and everything else in this directory."
echo ""
if [ "$ASSUME_YES" = true ]; then
    echo "  Confirmation skipped (-y)."
else
    read -r -p "  Are you sure you want to reset? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "  Cancelled."
        exit 0
    fi
fi

echo ""
echo "[1/3] Stopping and removing Docker containers..."
# Name every profile: without them `down` leaves the profile-gated services
# running, and the next setup.sh then stops at its "Existing containers
# detected" prompt instead of starting from scratch. These are profile names,
# not service names — the Vite container is in the "dev" profile, so the
# earlier "vite" here matched nothing and left it running in --dev setups.
DOWN_ARGS=(-v --remove-orphans)
# --rmi local drops only the images compose built here, so the next setup.sh
# rebuilds them: the way to pick up a changed Dockerfile layer that Docker
# would otherwise serve from its cache. Pulled images (mysql, adminer,
# mailpit) are shared with other stacks and are left alone.
if [ "$REMOVE_IMAGES" = true ]; then
    DOWN_ARGS+=(--rmi local)
fi
COMPOSE_PROFILES=cron,dev,redis,tools docker compose down "${DOWN_ARGS[@]}" 2>/dev/null || true

echo ""
echo "[2/3] Removing data..."
# Use a throwaway container to remove root-owned files (avoids host-side sudo).
if [ -d "html" ] || [ -d "mysql" ]; then
    docker run --rm -v "$(pwd):/work" alpine \
        sh -c 'rm -rf /work/html /work/mysql' 2>/dev/null || true
fi
# Final host-side cleanup for any non-root remnants.
rm -rf html mysql 2>/dev/null || true
# Both removals above swallow their errors, so check the result instead of
# handing setup.sh a half-deleted tree it would only report as "html/
# already exists".
if [ -d "html" ] || [ -d "mysql" ]; then
    echo "  Could not remove html/ or mysql/ (files left behind):"
    [ -d "html" ] && echo "    html/ still exists."
    [ -d "mysql" ] && echo "    mysql/ still exists."
    echo ""
    echo "  Remove them by hand, then run ./reset.sh again. If they are"
    echo "  root-owned and Docker is not running, start Docker first: the"
    echo "  removal above uses a container to avoid asking for sudo."
    exit 1
fi
echo "  Removed html/ and mysql/."

echo ""
echo "[3/3] Re-running setup..."
./setup.sh "${SETUP_ARGS[@]}"
