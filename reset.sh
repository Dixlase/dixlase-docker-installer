#!/bin/bash
set -e

# ====================================================
# Dixlase Sandbox 完全リセット
# DB・ソース・Docker ボリュームをすべて削除して再構築
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "  Dixlase Sandbox - 完全リセット"
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
# node_modules 等は Docker 内で root 作成のためコンテナ経由で削除
if [ -d "html" ]; then
    sudo rm -rf html/node_modules html/vendor
fi
rm -rf html
rm -rf mysql
echo "  html/ と mysql/ を削除しました。"

echo ""
echo "[3/3] 再セットアップを実行中..."
./setup.sh "$@"
