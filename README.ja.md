For English, see [README.md](./README.md).

# Dixlase Docker インストーラー

[Dixlase](https://github.com/Dixlase/dixlase-core) を Docker で簡単に立ち上げるためのインストーラーです。  
1 コマンドで PHP-FPM / Nginx / MariaDB / Redis / Mailpit / Adminer を一括起動し、コアとデフォルトテーマの clone、自己署名 TLS 証明書の生成、PHP / JS 依存関係のコンテナ内インストールまでをまとめて行います。

## 動作要件

- **Docker Desktop** (macOS / Windows) または **Docker Engine + Docker Compose v2** (Linux)
- **Git**
- **OpenSSL** (`localhost` 用の自己署名証明書を生成するために使用)
- **Bash シェル。** `setup.sh` は POSIX 準拠の Bash スクリプトです。macOS と Linux には
  最初から入っています。Windows では WSL2 か Git Bash が必要です
  ([Windows で使う場合](#windows-で使う場合))。

## クイックスタート

```bash
git clone https://github.com/Dixlase/dixlase-docker-installer.git dixlase
cd dixlase
./setup.sh
```

`git` を使わない場合は、GitHub からリポジトリの ZIP をダウンロード (「Code」→「Download
ZIP」) して展開し、展開先で `./setup.sh` を実行してください。スクリプトの実行権限は
保たれ、`.env` は初回実行時に `.env.example` から生成されます。git のチェックアウトが
必要なのは `./update.sh` だけで、ZIP でインストールした場合のコアの更新は管理画面から
行います。

初回は数分かかります (コアの clone、PHP と JS の依存関係のインストール、テーマの
ビルド)。**`setup.sh` がサイトの URL を表示するまで待ってください** — アセットの
ビルドが終わる前からサイトは応答するため、先に開くと Laravel のエラー画面が出ます。

## Windows で使う場合

`setup.sh` は Bash スクリプトなので、**PowerShell と CMD では実行できません**。動く方法は
2 つです。

- **WSL2 (推奨)。** Docker Desktop で *Use the WSL 2 based engine* を有効にし、
  *Resources → WSL Integration* で使うディストロの連携をオンにします。そのうえで
  ディストロの中で `sudo apt install -y git openssl` を実行し、**`/mnt/c` ではなく**
  Linux 側のホームに clone して (`/mnt/c` はバインドマウントが遅く、所有権も対応しません)
  `./setup.sh` を実行します。ブラウザは Windows 側でそのまま
  `http://localhost:40080` を開けます。
- **Git Bash。** こちらでも動きますが、このリポジトリの `.gitattributes` より古い git を
  使っている場合は `--config core.autocrlf=input` を付けて clone してください。ホストの
  パスが化けるときは `reset.sh` の前に `MSYS_NO_PATHCONV=1` を付けます。

セットアップ完了後、ブラウザで `http://localhost:40080` にアクセスしてください。  
初回アクセス時には Dixlase のインストールウィザードが表示されます。  
(`.env` で `HTTPS=true` に変更して `./setup.sh` を再実行すると、同梱の自己署名証明書を使った
HTTPS に切り替わります。すでに HTTP でインストール済みのサイトでは、あわせて `html/.env` の
`APP_URL` を HTTPS の URL に変更し `FORCE_SSL=true` にしたうえで
`docker compose exec dixlase.test php artisan config:clear` を実行してください。Laravel は
`APP_URL` からアセットの URL を組み立てるため、そのままではページは開けても CSS と JS が
読み込めません。食い違っている場合は `setup.sh` が警告します。)

## デフォルトの URL

| サービス | URL |
| --- | --- |
| Dixlase | `http://localhost:40080` (`HTTPS=true` のときは `https://localhost:40443`) |
| Adminer (DB GUI) | `http://localhost:40081` |
| Mailpit (メール受信) | `http://localhost:40025` |

全インターフェースに公開されるのは CMS 本体だけです。Adminer・Mailpit・MariaDB・
Vite 開発サーバーは `127.0.0.1` に束縛されており、このマシンからのみ応答します
（Adminer と Mailpit は自前のパスワードを持ちません）。Adminer と Mailpit は
`.env` の `TOOLS` フラグ（既定は有効）の対象でもあり、`TOOLS=false` にして
`./setup.sh` を再実行すると、そもそも起動しません。

## 動作モード

### ビルド済みアセットモード (デフォルト)

```bash
./setup.sh
```

`npm run build` で静的アセットをビルドします。Vite dev サーバーは **起動しません**。
（以前は「本番モード」と呼んでいましたが、このスタックがしていない約束に読めるため
改名しました。下の「サーバーで使う場合」を参照してください。）

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
CRON=true                    # Laravel のスケジューラを毎分実行する
TOOLS=true                   # Adminer と Mailpit を起動する (127.0.0.1 のみ)
CONTAINER_PREFIX=dixlase     # コンテナ名を <prefix>-app, <prefix>-mysql, ... にする
COMPOSE_PROJECT_NAME=dixlase # Docker Desktop や `docker compose ls` でのグループ名
APP_PORT=40080         # "4" = D = Dixlase の頭文字 (アルファベット 4 番目)
APP_SSL_PORT=40443
FORWARD_DB_PORT=40306
FORWARD_ADMINER_PORT=40081
FORWARD_MAILPIT_PORT=40025
FORWARD_VITE_PORT=40173      # Redis はホスト側ポートを意図的に公開しない

DB_BIND_ADDRESS=127.0.0.1    # ツール類はこのマシンからのみ応答する
ADMINER_BIND_ADDRESS=127.0.0.1
MAILPIT_BIND_ADDRESS=127.0.0.1
VITE_BIND_ADDRESS=127.0.0.1

DB_DATABASE=dixlase
DB_USERNAME=dixlase
DB_PASSWORD=dixlase
DB_ROOT_PASSWORD=root
```

`HTTPS` / `VITE` / `REDIS` を切り替えたあとは `./setup.sh` を再実行してください。派生する `NGINX_VARIANT` / `COMPOSE_PROFILES` を反映させるためです。  
`.env` はユーザー所有領域なので、派生値は `setup.sh` が export するだけで書き戻しません。`docker compose down` のあとも同じで、profile 配下のサービス (Vite / Redis) を確実に戻すには `./setup.sh` (idempotent) を使ってください。

`REDIS` を有効化する場合は Laravel 側の `CACHE_STORE` / `SESSION_DRIVER` も `redis` に向けてください。`4xxxx` 名前空間 ("4" = D = Dixlase の頭文字、アルファベット 4 番目) は標準ポートと衝突しないためのデフォルトです。衝突がなく標準ポートで動かしたい場合は、`setup.sh` 実行前に `.env` で `APP_PORT=80` / `APP_SSL_PORT=443` に書き換えてください。

## サーバーで使う場合

既定値はローカルで試すためのものです。DB パスワードは `dixlase`、MariaDB の root
パスワードは `root` で、それを受け取るツール類は自前のパスワードを持ちません。
サイト以外がすべて `127.0.0.1` で待ち受けている限り問題ありませんが、そうでなくなった
瞬間に開いた扉になります。このホストを外に出す前に:

- **`.env` の `DB_PASSWORD` と `DB_ROOT_PASSWORD` を変更する。** MariaDB はデータ
  ディレクトリの作成時にしかこれを読まないので、最初の `./setup.sh` の前に変更するか、
  後から MariaDB 側で変更してください（`./reset.sh` でやり直す方法もありますが、
  データベースは削除されます）。
- **`*_BIND_ADDRESS` はすべて `127.0.0.1` のままにする。** 既定のパスワードが残った
  まま loopback より広く束縛されている場合、`setup.sh` が警告します。ツールへは
  SSH トンネル経由で接続してください: `ssh -L 40081:127.0.0.1:40081 you@host`。
- **到達可能なホストで `--dev`（`VITE=true`）を使わない。** Vite 開発サーバーは
  `/@fs/` パス経由で `html/` 配下のファイルを読めます。
- **`TOOLS=false` も検討する。** Adminer と Mailpit をそもそも起動しません。
- ホストの SSH 鍵はコンテナへ**マウントしません**。DixlaseDeploy プラグインで
  デプロイする場合は `docker-compose.deploy.yml` で明示的に有効化してください —
  コンテナ内で動くものは（依存パッケージの install スクリプトを含め）その鍵を読めます。

このスタックが何を守り、何を守らないかの全体像は `SECURITY.ja.md` にあります。

### リポジトリ URL の上書き

フォークやミラーから取得したい場合は、環境変数で URL を上書きできます。

```bash
export DIXLASE_REPO_URL=https://github.com/your-org/dixlase-core.git
./setup.sh
```

同梱テーマはこのインストーラーが clone するのではなく、コアが Composer の依存関係として
取得します。そのためテーマのフォークを使いたい場合は、ここではなくフォークしたコア側で
指定します。

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
