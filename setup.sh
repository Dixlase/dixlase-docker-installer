#!/bin/bash
set -e

# ====================================================
# Dixlase Sandbox セットアップスクリプト
# 用途: GitHub からコアをクローンし、クリーンな検証環境を構築
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO_URL="git@github-dixlase:Dixlase/dixlase-core.git"
BRANCH="${1:-main}"

echo "========================================"
echo "  Dixlase Sandbox Setup"
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

if [ ! -f "html/.env" ]; then
    cp .env.sandbox html/.env
    echo "  .env.sandbox → html/.env にコピーしました。"
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
        -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dixlase/OU=Sandbox/CN=localhost" 2>/dev/null
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
docker compose build
docker compose up -d

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
docker compose exec -T laravel.test composer install --no-interaction
echo "  npm install 実行中..."
docker compose exec -T laravel.test npm install

# APP_KEY を生成
docker compose exec -T laravel.test php artisan key:generate --force
echo "  APP_KEY を生成しました。"

# ストレージリンクを作成
docker compose exec -T laravel.test php artisan storage:link 2>/dev/null || true
echo "  ストレージリンクを作成しました。"

# キャッシュをクリア（DB 未作成時はスキップ）
docker compose exec -T laravel.test php artisan config:clear
docker compose exec -T laravel.test php artisan cache:clear 2>/dev/null || true
echo "  キャッシュをクリアしました。"

# -------------------------------------------------
# 6. アセットのビルド
# -------------------------------------------------
echo ""
echo "[6/6] フロントエンドアセットをビルド中..."
# hot ファイルを削除してビルド済みアセットを使用させる
docker compose exec -T laravel.test rm -f public/hot
docker compose exec -T laravel.test npm run build

# -------------------------------------------------
# 完了
# -------------------------------------------------
echo ""
echo "========================================"
echo "  Sandbox セットアップ完了!"
echo "========================================"
echo ""
echo "  アクセス URL:"
echo "    CMS:        https://localhost:8443"
echo "    phpMyAdmin:  http://localhost:8182"
echo "    Mailpit:     http://localhost:8126"
echo ""
echo "  次のステップ:"
echo "    1. https://localhost:8443 にアクセス"
echo "    2. インストールウィザードが表示されます"
echo "    3. セットアップ完了後、管理画面でプラグイン検証開始"
echo ""
echo "  便利なコマンド:"
echo "    docker compose logs -f          # ログを確認"
echo "    docker compose exec laravel.test bash  # コンテナに入る"
echo "    ./reset.sh                      # 環境を完全リセット"
echo "    ./update.sh                     # GitHub から最新を取得"
echo ""
