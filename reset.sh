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
echo "  Dixlase - 完全リセット"
echo "========================================"
echo ""
echo "  以下が削除されます:"
echo "    - Docker コンテナ・ボリューム"
echo "    - html/ (ソースコード)"
echo "    - mysql/ (データベース)"
echo ""
read -p "  本当にリセットしますか? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "  キャンセルしました。"
    exit 0
fi

echo ""
echo "[1/3] Docker コンテナを停止・削除中..."
docker compose down -v 2>/dev/null || true

echo ""
echo "[2/3] データを削除中..."
# node_modules etc. are created as root inside Docker, so delete via sudo
if [ -d "html" ]; then
    sudo rm -rf html/node_modules html/vendor
fi
rm -rf html
rm -rf mysql
echo "  html/ と mysql/ を削除しました。"

echo ""
echo "[3/3] 再セットアップを実行中..."
./setup.sh "$@"
