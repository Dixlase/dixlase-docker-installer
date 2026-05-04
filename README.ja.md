# Dixlase Docker インストーラー

[Dixlase](https://github.com/Dixlase/dixlase-core) を Docker で簡単に立ち上げるためのインストーラーです。1 コマンドで PHP-FPM / Nginx / MariaDB / Redis / Mailpit / Adminer を一括起動します。

For English, see [README.md](./README.md).

## 動作要件

- **Docker Desktop** (macOS / Windows) または **Docker Engine + Docker Compose v2** (Linux)
- **Git**
- **OpenSSL** (`localhost` 用の自己署名証明書を生成するために使用)

## クイックスタート

```bash
git clone https://github.com/Dixlase/dixlase-docker-installer.git dixlase
cd dixlase
./setup.sh
```

セットアップ完了後、ブラウザで `http://localhost` にアクセスしてください。初回アクセス時には Dixlase のインストールウィザードが表示されます。 (`.env` で `HTTPS=true` に変更して `./setup.sh` を再実行すると、同梱の自己署名証明書を使った HTTPS に切り替わります。)

## setup.sh が行う処理

1. Dixlase コアリポジトリを `./html/` にクローン
2. デフォルトテーマを `./html/themes/DixlaseOnePage/` にクローン
3. `.env.example` を `./.env` (Docker Compose のポート / DB 認証情報用) にコピー。Laravel 側の `./html/.env` はブラウザで初回アクセスした際に Dixlase インストールウィザードが生成します。
4. 自己署名 TLS 証明書を `./certs/` に生成
5. Docker コンテナをビルド・起動
6. `composer install`、`npm install`、(本番モードの場合) `npm run build` を実行

## デフォルトの URL

| サービス | URL |
| --- | --- |
| Dixlase CMS | `http://localhost` (`HTTPS=true` のときは `https://localhost`) |
| Adminer (DB GUI) | `http://localhost:8081` |
| Mailpit (メール受信) | `http://localhost:8025` |

## 動作モード

### 本番モード (デフォルト)

```bash
./setup.sh
```

`npm run build` で静的アセットをビルドします。Vite dev サーバーは **起動しません**。

### 開発モード (Vite hot-reload)

```bash
./setup.sh --dev
```

Docker Compose の `dev` プロファイルで `vite` コンテナを追加起動します。フロントエンドのソースを編集すると `http://localhost` (`HTTPS=true` のときは `https://localhost`) に hot-reload されます。

既存のセットアップでモードを切り替える場合は `./reset.sh --dev` または `./reset.sh` を実行してください。

## 設定

ホスト側のポートと DB 認証情報はすべてルートの `.env` で上書きできます。`setup.sh` 実行後に `.env` を編集し、`docker compose up -d` で再起動してください。

```env
HTTPS=false                  # true にすると自己署名証明書での TLS が有効になる
VITE=false                   # true にすると Vite dev サーバーを起動 (= --dev)
REDIS=false                  # true にすると Redis コンテナを起動する
CONTAINER_PREFIX=dixlase     # コンテナ名を <prefix>-app, <prefix>-mysql, ... にする
COMPOSE_PROJECT_NAME=dixlase # Docker Desktop や `docker compose ls` でのグループ名
APP_PORT=80
APP_SSL_PORT=443
FORWARD_DB_PORT=3306
FORWARD_ADMINER_PORT=8081
FORWARD_MAILPIT_PORT=8025
FORWARD_REDIS_PORT=6379
FORWARD_VITE_PORT=5173

DB_DATABASE=dixlase
DB_USERNAME=dixlase
DB_PASSWORD=dixlase
DB_ROOT_PASSWORD=root
```

`HTTPS` / `VITE` / `REDIS` を切り替えたあとは `./setup.sh` を再実行してください。派生する `NGINX_VARIANT` / `COMPOSE_PROFILES` は `setup.sh` が自身の `docker compose up` 呼び出し向けに export するだけで、`.env` には書き戻しません — `.env` はユーザー所有領域です。`docker compose down` のあとも同様で、素の `docker compose up -d` では profile 配下のサービス (Vite / Redis) が起動しないため、再起動には `./setup.sh` (idempotent) を使うのが確実です。

`REDIS` を有効化する場合は Laravel 側の `CACHE_STORE` / `SESSION_DRIVER` も `redis` に向けてください。

ローカルマシンで `80` / `443` ポートが既に使われている場合 (Apache / IIS など) は、`setup.sh` を実行する前に `.env` で `APP_PORT=8080` / `APP_SSL_PORT=8443` などの空きポートに変更してください。

### リポジトリ URL の上書き

フォークやミラーから取得したい場合は、環境変数で URL を上書きできます。

```bash
export DIXLASE_REPO_URL=https://github.com/your-org/dixlase-core.git
export DIXLASE_THEME_REPO_URL=https://github.com/your-org/theme-dixlase-onepage.git
./setup.sh
```

## ローカライゼーション

インストーラースクリプトのコメントと UI メッセージはデフォルトで英語です。日本語に切り替える (または戻す) には付属の変換スクリプトを使います:

```bash
./convert-comments.sh ja              # 全ファイル: 英語 → 日本語
./convert-comments.sh ja setup.sh     # 単一ファイル: 英語 → 日本語
./convert-comments.sh ja --reverse    # 全ファイル: 日本語 → 英語 (復元)
```

翻訳辞書は `lang/<locale>/<source-path>.tsv` に配置されます (タブ区切りの `<英語テキスト>\t<ロケール側テキスト>` ペア)。新しいロケールを追加したり既存のものを拡張する場合は、既存ファイルと同じ場所に新しい TSV を置いてください。フォーマットの詳細は [CLAUDE.md](./CLAUDE.md) を参照してください。

## 便利なコマンド

```bash
docker compose logs -f                  # 全コンテナのログを追跡表示
docker compose exec dixlase.test bash   # アプリコンテナ内でシェルを開く
./update.sh                             # コアを git pull し、マイグレーションを実行
./reset.sh                              # DB / ソース / ボリュームを削除して再セットアップ
```

## リポジトリ構成

```
.
├── Dockerfile              # PHP-FPM 8.3 + Composer + Node 20
├── Dockerfile.vite         # Vite dev サーバー (--dev 指定時のみ使用)
├── docker-compose.yml      # サービス定義
├── nginx/nginx.http.conf   # Nginx vhost — HTTP のみ・リダイレクトなし (HTTPS=false)
├── nginx/nginx.https.conf  # Nginx vhost — HTTP→HTTPS リダイレクト + TLS (HTTPS=true)
├── php/php.ini             # PHP ランタイム設定 (アップロードサイズ、メモリ等)
├── .env.example            # 環境変数テンプレート (setup 時に .env にコピーされる)
├── setup.sh                # 初回セットアップ
├── update.sh               # コアを最新化してマイグレーションを実行
├── reset.sh                # 全状態を削除して再セットアップ
├── convert-comments.sh     # スクリプトのコメント / メッセージをロケール間で切り替える
├── entrypoint.sh           # Vite コンテナのエントリポイント
└── lang/{en,ja}/           # 翻訳辞書 (TSV)
```

## ライセンス

本インストーラー (Dockerfile / シェルスクリプト / 設定テンプレート) は [MIT ライセンス](./LICENSE) の下で配布されます。フォーク・改変・カスタムデプロイに自由に利用できます。

Dixlase 本体のアプリケーションコードは別途 AGPL v3 ライセンスの下で配布されます。詳細は [Dixlase Core](https://github.com/Dixlase/dixlase-core) を参照してください。
