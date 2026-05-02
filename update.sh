#!/bin/bash
set -e

# ====================================================
# Dixlase Sandbox ソース更新
# GitHub から最新のコードを pull してコンテナを再構築
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BRANCH="${1:-main}"

echo "========================================"
echo "  Dixlase Sandbox - ソース更新"
echo "  Branch: $BRANCH"
echo "========================================"
echo ""

if [ ! -d "html" ]; then
    echo "  html/ が見つかりません。setup.sh を先に実行してください。"
    exit 1
fi

# Git pull
echo "[1/4] GitHub から最新を取得中..."
cd html
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"
cd ..

# Composer/npm 更新
echo ""
echo "[2/4] 依存パッケージを更新中..."
docker compose exec -T laravel.test composer install --no-interaction
echo "  composer install 完了。"

# マイグレーション
echo ""
echo "[3/4] マイグレーションを実行中..."
docker compose exec -T laravel.test php artisan migrate --force
echo "  マイグレーション完了。"

# キャッシュクリア
echo ""
echo "[4/4] キャッシュをクリア中..."
docker compose exec -T laravel.test php artisan config:clear
docker compose exec -T laravel.test php artisan cache:clear
docker compose exec -T laravel.test php artisan view:clear
echo "  キャッシュクリア完了。"

echo ""
echo "========================================"
echo "  更新完了! https://localhost:8443"
echo "========================================"
