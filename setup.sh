#!/bin/bash
set -e

# ====================================================
# Dixlase セットアップスクリプト
# 用途: GitHub からコアをクローンし、Docker 環境を構築
#
# 使い方:
#   ./setup.sh                  # 本番モード (ビルド済みアセット運用)
#   ./setup.sh --dev            # 開発モード (Vite hot-reload 有効)
#   ./setup.sh <branch>         # 指定ブランチをクローン (デフォルト: main)
#   ./setup.sh --dev <branch>   # 開発モード + ブランチ指定
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO_URL="git@github-dixlase:Dixlase/dixlase-core.git"

# 引数パース: --dev フラグとブランチ名
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
# 1. GitHub からコアをクローン
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
# 1.5. サブモジュール（テーマ等）を取得
# -------------------------------------------------
echo ""
echo "[1.5/6] サブモジュールを初期化中..."
cd html
# サブモジュールではなく直接クローン（コアが参照するコミットが存在しない場合に対応）
rm -rf themes/DixlaseOnePage
echo "  themes/DixlaseOnePage を取得中..."
git clone git@github-dixlase:Dixlase/theme-dixlase-onepage.git themes/DixlaseOnePage
cd ..
echo "  サブモジュールの取得が完了しました。"

# -------------------------------------------------
# 2. .env のセットアップ
# -------------------------------------------------
echo ""
echo "[2/6] .env をセットアップ中..."

# ルート .env (Docker Compose 用) — ポート/DB認証情報の補間に使用
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "  .env.example → .env (Docker Compose 用) にコピーしました。"
else
    echo "  .env は既に存在します（スキップ）。"
fi

# Laravel .env (アプリケーション用)
if [ ! -f "html/.env" ]; then
    cp .env.example html/.env
    echo "  .env.example → html/.env (Laravel 用) にコピーしました。"
else
    echo "  html/.env は既に存在します（スキップ）。"
fi

# 開発環境の .env から EXTENSION_GITHUB_TOKEN を取得して設定
DEV_ENV="/Volumes/Data/Works/Dixlase/Core/docker/html/.env"
if [ -f "$DEV_ENV" ]; then
    TOKEN=$(grep '^EXTENSION_GITHUB_TOKEN=' "$DEV_ENV" | cut -d'=' -f2)
    if [ -n "$TOKEN" ] && grep -q '^EXTENSION_GITHUB_TOKEN=$' "html/.env"; then
        sed -i '' "s/^EXTENSION_GITHUB_TOKEN=$/EXTENSION_GITHUB_TOKEN=$TOKEN/" "html/.env"
        echo "  開発環境から EXTENSION_GITHUB_TOKEN を自動設定しました。"
    fi
fi

# -------------------------------------------------
# 3. SSL 証明書の生成
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
# 4. Docker イメージのビルドと起動
# -------------------------------------------------
echo ""
echo "[4/6] Docker コンテナをビルド・起動中..."
docker compose $COMPOSE_PROFILE_ARGS build
docker compose $COMPOSE_PROFILE_ARGS up -d

# コンテナの起動を待つ
echo "  コンテナの起動を待機中..."
sleep 5

# -------------------------------------------------
# 5. Laravel のセットアップ
# -------------------------------------------------
echo ""
echo "[5/6] Laravel をセットアップ中..."

# ボリュームマウントにより vendor/node_modules がホスト側で欠落しているため再インストール
echo "  composer install 実行中..."
docker compose exec -T dixlase.test composer install --no-interaction
echo "  npm install 実行中..."
docker compose exec -T dixlase.test npm install

# APP_KEY を生成
docker compose exec -T dixlase.test php artisan key:generate --force
echo "  APP_KEY を生成しました。"

# ストレージリンクを作成
docker compose exec -T dixlase.test php artisan storage:link 2>/dev/null || true
echo "  ストレージリンクを作成しました。"

# キャッシュをクリア（DB 未作成時はスキップ）
docker compose exec -T dixlase.test php artisan config:clear
docker compose exec -T dixlase.test php artisan cache:clear 2>/dev/null || true
echo "  キャッシュをクリアしました。"

# -------------------------------------------------
# 6. アセットのビルド (本番モードのみ)
# -------------------------------------------------
echo ""
if [ "$DEV_MODE" = true ]; then
    echo "[6/6] 開発モード: Vite dev サーバーが vite コンテナで起動中..."
    echo "      ビルドはスキップされます (hot-reload 有効)。"
else
    echo "[6/6] フロントエンドアセットをビルド中..."
    # hot ファイルを削除してビルド済みアセットを使用させる
    docker compose exec -T dixlase.test rm -f public/hot
    docker compose exec -T dixlase.test npm run build
fi

# -------------------------------------------------
# 完了
# -------------------------------------------------
# .env から実際のポートを読み取って表示
APP_PORT_VAL=$(grep '^APP_PORT=' .env | cut -d'=' -f2)
APP_SSL_PORT_VAL=$(grep '^APP_SSL_PORT=' .env | cut -d'=' -f2)
FORWARD_ADMINER_PORT_VAL=$(grep '^FORWARD_ADMINER_PORT=' .env | cut -d'=' -f2)
FORWARD_MAILPIT_PORT_VAL=$(grep '^FORWARD_MAILPIT_PORT=' .env | cut -d'=' -f2)

# ポート 443/80 の場合は URL から省略
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
