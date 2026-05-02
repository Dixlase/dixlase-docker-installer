#!/bin/bash
set -e

# ====================================================
# Dixlase complete reset
# Deletes all DB / source / Docker volumes and rebuilds from scratch.
#
# Usage:
#   ./reset.sh             # Re-setup in production mode
#   ./reset.sh --dev       # Re-setup in development mode
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "  Dixlase - Full reset"
echo "========================================"
echo ""
echo "  The following will be deleted:"
echo "    - Docker containers and volumes"
echo "    - html/ (source code)"
echo "    - mysql/ (database files)"
echo ""
read -p "  Are you sure you want to reset? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "  Cancelled."
    exit 0
fi

echo ""
echo "[1/3] Stopping and removing Docker containers..."
docker compose down -v 2>/dev/null || true

echo ""
echo "[2/3] Removing data..."
# Use a throwaway container to remove root-owned files (avoids host-side sudo).
if [ -d "html" ] || [ -d "mysql" ]; then
    docker run --rm -v "$(pwd):/work" alpine \
        sh -c 'rm -rf /work/html /work/mysql' 2>/dev/null || true
fi
# Final host-side cleanup for any non-root remnants.
rm -rf html mysql 2>/dev/null || true
echo "  Removed html/ and mysql/."

echo ""
echo "[3/3] Re-running setup..."
./setup.sh "$@"
