#!/bin/bash
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
    COMPOSE_PROFILE_ARGS="--profile dev"
    MODE_LABEL="開発モード (Vite hot-reload)"
else
    COMPOSE_PROFILE_ARGS=""
    MODE_LABEL="本番モード (ビルド済みアセット)"
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
    echo "[1/6] html/ が既に存在します。"
    read -p "  削除してクリーンクローンしますか? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "  html/ を削除中..."
        rm -rf html
        echo "  GitHub からクローン中..."
        git clone -b "$BRANCH" "$REPO_URL" html
    else
        echo "  既存の html/ をそのまま使用します。"
    fi
else
    echo "[1/6] GitHub からクローン中..."
    git clone -b "$BRANCH" "$REPO_URL" html
fi

# -------------------------------------------------
# 1.5. Fetch submodules (themes etc.)
# -------------------------------------------------
echo ""
echo "[1.5/6] サブモジュールを初期化中..."
cd html
# Clone directly instead of using a submodule (handles commits the core may not reach)
rm -rf themes/DixlaseOnePage
echo "  themes/DixlaseOnePage を取得中..."
git clone "$THEME_REPO_URL" themes/DixlaseOnePage
cd ..
echo "  サブモジュールの取得が完了しました。"

# -------------------------------------------------
# 2. Set up .env
# -------------------------------------------------
echo ""
echo "[2/6] .env をセットアップ中..."

# Root .env (used by Docker Compose to interpolate ports / DB credentials)
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "  .env.example → .env (Docker Compose 用) にコピーしました。"
else
    echo "  .env は既に存在します（スキップ）。"
fi

# Laravel .env (used by the application)
if [ ! -f "html/.env" ]; then
    cp .env.example html/.env
    echo "  .env.example → html/.env (Laravel 用) にコピーしました。"
else
    echo "  html/.env は既に存在します（スキップ）。"
fi

# -------------------------------------------------
# 3. Generate SSL certificate
# -------------------------------------------------
echo ""
echo "[3/6] SSL 証明書を生成中..."

if [ -f "certs/localhost.crt" ] && [ -f "certs/localhost.key" ]; then
    echo "  証明書は既に存在します（スキップ）。"
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
    echo "  証明書を生成しました。"
fi

# -------------------------------------------------
# 4. Build and start Docker containers
# -------------------------------------------------
echo ""
echo "[4/6] Docker コンテナをビルド・起動中..."
docker compose $COMPOSE_PROFILE_ARGS build
docker compose $COMPOSE_PROFILE_ARGS up -d

# Wait for containers to start
echo "  コンテナの起動を待機中..."
sleep 5

# -------------------------------------------------
# 5. Set up Laravel
# -------------------------------------------------
echo ""
echo "[5/6] Laravel をセットアップ中..."

# Reinstall because vendor/node_modules are missing on the host due to the volume mount
echo "  composer install 実行中..."
docker compose exec -T dixlase.test composer install --no-interaction
echo "  npm install 実行中..."
docker compose exec -T dixlase.test npm install

# Generate APP_KEY
docker compose exec -T dixlase.test php artisan key:generate --force
echo "  APP_KEY を生成しました。"

# Create the storage symlink
docker compose exec -T dixlase.test php artisan storage:link 2>/dev/null || true
echo "  ストレージリンクを作成しました。"

# Clear caches (skipped if DB does not exist yet)
docker compose exec -T dixlase.test php artisan config:clear
docker compose exec -T dixlase.test php artisan cache:clear 2>/dev/null || true
echo "  キャッシュをクリアしました。"

# -------------------------------------------------
# 6. Build assets (production mode only)
# -------------------------------------------------
echo ""
if [ "$DEV_MODE" = true ]; then
    echo "[6/6] 開発モード: Vite dev サーバーが vite コンテナで起動中..."
    echo "      ビルドはスキップされます (hot-reload 有効)。"
else
    echo "[6/6] フロントエンドアセットをビルド中..."
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

# Omit the port from the URL when it is the standard 443/80
[ "$APP_SSL_PORT_VAL" = "443" ] && SSL_URL="https://localhost" || SSL_URL="https://localhost:$APP_SSL_PORT_VAL"

echo ""
echo "========================================"
echo "  セットアップ完了!"
echo "========================================"
echo ""
echo "  アクセス URL:"
echo "    CMS:        $SSL_URL"
echo "    Adminer:    http://localhost:$FORWARD_ADMINER_PORT_VAL"
echo "    Mailpit:    http://localhost:$FORWARD_MAILPIT_PORT_VAL"
echo ""
echo "  次のステップ:"
echo "    1. $SSL_URL にアクセス"
echo "    2. インストールウィザードが表示されます"
echo "    3. セットアップ完了後、管理画面で運用開始"
echo ""
echo "  便利なコマンド:"
echo "    docker compose logs -f                  # ログを確認"
echo "    docker compose exec dixlase.test bash   # コンテナに入る"
echo "    ./reset.sh                              # 環境を完全リセット"
echo "    ./update.sh                             # GitHub から最新を取得"
echo ""
