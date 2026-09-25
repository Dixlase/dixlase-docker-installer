For English, see [README.md](./README.md).

# Dixlase Docker インストーラー

[Dixlase](https://github.com/Dixlase/dixlase-core) を Docker で簡単に立ち上げるためのインストーラーです。  
1 コマンドで PHP-FPM / Nginx / MariaDB / Redis / Mailpit / Adminer を一括起動し、コアとデフォルトテーマの clone、自己署名 TLS 証明書の生成、PHP / JS 依存関係のコンテナ内インストールまでをまとめて行います。

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

セットアップ完了後、ブラウザで `http://localhost:40080` にアクセスしてください。  
初回アクセス時には Dixlase のインストールウィザードが表示されます。  
(`.env` で `HTTPS=true` に変更して `./setup.sh` を再実行すると、同梱の自己署名証明書を使った HTTPS に切り替わります。)

## デフォルトの URL

| サービス | URL |
| --- | --- |
| Dixlase | `http://localhost:40080` (`HTTPS=true` のときは `https://localhost:40443`) |
| Adminer (DB GUI) | `http://localhost:40081` |
| Mailpit (メール受信) | `http://localhost:40025` |

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

Docker Compose の `dev` プロファイルで `vite` コンテナを追加起動します。フロントエンドのソースを編集すると `http://localhost:40080` (`HTTPS=true` のときは `https://localhost:40443`) に hot-reload されます。

既存のセットアップでモードを切り替える場合は `./reset.sh --dev` または `./reset.sh` を実行してください。

## 設定

ホスト側のポートと DB 認証情報はすべてルートの `.env` で上書きできます。`setup.sh` 実行後に `.env` を編集し、`docker compose up -d` で再起動してください。

```env
HTTPS=false                  # true にすると自己署名証明書での TLS が有効になる
VITE=false                   # true にすると Vite dev サーバーを起動 (= --dev)
REDIS=false                  # true にすると Redis コンテナを起動する
CONTAINER_PREFIX=dixlase     # コンテナ名を <prefix>-app, <prefix>-mysql, ... にする
COMPOSE_PROJECT_NAME=dixlase # Docker Desktop や `docker compose ls` でのグループ名
APP_PORT=40080         # "4" = D = Dixlase の頭文字 (アルファベット 4 番目)
APP_SSL_PORT=40443
FORWARD_DB_PORT=40306
FORWARD_ADMINER_PORT=40081
FORWARD_MAILPIT_PORT=40025
FORWARD_REDIS_PORT=40379
FORWARD_VITE_PORT=40173

DB_DATABASE=dixlase
DB_USERNAME=dixlase
DB_PASSWORD=dixlase
DB_ROOT_PASSWORD=root
```

`HTTPS` / `VITE` / `REDIS` を切り替えたあとは `./setup.sh` を再実行してください。派生する `NGINX_VARIANT` / `COMPOSE_PROFILES` を反映させるためです。  
`.env` はユーザー所有領域なので、派生値は `setup.sh` が export するだけで書き戻しません。`docker compose down` のあとも同じで、profile 配下のサービス (Vite / Redis) を確実に戻すには `./setup.sh` (idempotent) を使ってください。

`REDIS` を有効化する場合は Laravel 側の `CACHE_STORE` / `SESSION_DRIVER` も `redis` に向けてください。`4xxxx` 名前空間 ("4" = D = Dixlase の頭文字、アルファベット 4 番目) は標準ポートと衝突しないためのデフォルトです。衝突がなく標準ポートで動かしたい場合は、`setup.sh` 実行前に `.env` で `APP_PORT=80` / `APP_SSL_PORT=443` に書き換えてください。

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
./convert-comments.sh ja setup.sh     # 単一ファイル
./convert-comments.sh ja --reverse    # 全ファイル: 日本語 → 英語 (復元)
```

翻訳辞書は `lang/<locale>/<source-path>.tsv` に配置されます (タブ区切りの `<英語テキスト>\t<ロケール側テキスト>` ペア)。  
フォーマットや新規ロケール追加方法は [CLAUDE.md](./CLAUDE.md) を参照してください。

## 便利なコマンド

```bash
docker compose logs -f                  # 全コンテナのログを追跡表示
docker compose exec dixlase.test bash   # アプリコンテナ内でシェルを開く
./update.sh                             # コアのチェックアウトを更新してスタックを再構成
./reset.sh                              # DB / ソース / ボリュームを削除して再セットアップ
```

## 更新

```bash
./update.sh                 # html/ を origin/main へ fast-forward し、スタックを再構成
./update.sh <branch>        # 同じ処理を別のブランチに対して実行
./update.sh --dev           # アセットビルドを省略（Vite 開発サーバーが配信）
```

`update.sh` は `html/` の **git チェックアウト**を進めます。ブランチを fast-forward し、
`composer install` を再実行し（同梱テーマのような private パッケージに必要なホストの
`~/.composer/auth.json` を渡します）、`dls:migration:resync` でマイグレーション台帳を
整合させ（コアがベースライン移行を採番し直している間は必須）、マイグレーションを実行し、
フロントエンドアセットを再ビルドし、コアのバージョン台帳を整合させます。
推測はしません — 追跡対象ファイルにローカル変更がある作業ツリー、detached `HEAD`、
fast-forward できない履歴では実行を止め、対処するコマンドを提示します。

**リリース版**のコアで動いているサイトは、代わりに `php artisan dls:core:update` を
使ってください。あちらはバックアップを取り、メンテナンス窓を保ち、ロールバックできます。
`update.sh` はそのいずれも行いません。

```bash
./reset.sh                  # DB / ソース / ボリュームを削除して setup を再実行
./reset.sh --dev            # 同じ処理を開発モードで再セットアップ
./reset.sh --images         # このスタック用にビルドしたイメージも削除
./reset.sh -y               # 確認プロンプトを省略
```

`reset.sh` は `.env` と `certs/` を残します。削除する対象は確認前にすべて表示されます。

## トラブルシューティング

### ウィザードが起動せず、フロントページに `No hint path defined for [themes]` が出る

原因: `html/` は消したが **MariaDB のデータ (`mysql/` ディレクトリまたは named volume) は残したまま** だった。コアの `CheckInstallationReady` ミドルウェアが残存マイグレーションを検出し「インストール完了状態」と判断、**`.env` に `INSTALLED=true` を自動書き込み (self-heal)** するためウィザードが起動しなくなる。発火時は `storage/logs/laravel.log` に必ず警告が出力される:

```
CheckInstallationReady: database shows an installed application
but the INSTALLED env flag was false. .env has been auto-restored
to INSTALLED=true...
```

対処: DB も一緒に wipe する。`./reset.sh` がコンテナ・named volumes・`html/`・`mysql/` を全部消して setup を再実行する正規ルートです。実行後 `/` を開くと `/install` にリダイレクトされ、空 DB に対してウィザードが走ります。

## ライセンス

本インストーラー (Dockerfile / シェルスクリプト / 設定テンプレート) は [MIT ライセンス](./LICENSE) の下で配布されます。フォーク・改変・カスタムデプロイに自由に利用できます。

Dixlase 本体のアプリケーションコードは別途 AGPL v3 ライセンスの下で配布されます。詳細は [Dixlase Core](https://github.com/Dixlase/dixlase-core) を参照してください。
