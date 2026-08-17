# Dixlase Docker インストーラへのコントリビュート

英語版は [CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

Dixlase に関心をお寄せいただきありがとうございます。

## 現在のステータス

Dixlase は開発初期段階にあります。**現時点では外部からの Pull Request を受け付けて
いません。** 本インストーラは
[Dixlase Core](https://github.com/Dixlase/dixlase-core/blob/main/CONTRIBUTING.ja.md)
と同一のコントリビューション方針に従います。Core のコントリビューション体制が確定する
までの間、プロジェクト全体で一貫した回答を維持するためです。方針が変わり次第、本書は
PR ベースの完全なコントリビューションガイドに差し替えます。

**現在歓迎しているもの（[Issues](https://github.com/Dixlase/dixlase-docker-installer/issues) 経由）:**

- バグ報告 — 明確な説明、再現手順、期待される挙動と実際の挙動、環境情報
  （ホスト OS、Docker / Docker Desktop のバージョン、HTTP と HTTPS のどちらの構成か）
- 機能提案 — ユースケース、提案する挙動、検討した代替案
- ドキュメント / 翻訳の誤りの報告
- 質問・フィードバック

**まだ受け付けていないもの:** あらゆる Pull Request（コード、ドキュメント、翻訳）。
本方針の期間中に作成された外部 PR は、**コードレビューを行わずクローズ**します。
実在する問題を扱う PR であれば、Issue として再提出してください。メンテナが独立して
修正を実装します。

> バグ報告に含まれるコードスニペットは**参考情報としてのみ**扱い、修正はメンテナが
> 独立して再実装します。これにより Dixlase プロジェクト全体のコントリビューション方針との
> 整合を保ちます。

## AI ツールの利用について

AI ツールは現代の開発の一部です。ただし、提出物は人間の理解に裏打ちされている必要が
あります。

- **翻訳・推敲:** 報告を英語に翻訳する、文章を整えるといった用途での AI 利用は歓迎します。
  開示は不要です。日本語での報告も受け付けます。
- **AI が実質を生成した場合:** 分析・再現の仮説・修正案といった報告の実質を AI ツールが
  生成した場合は、その旨を報告内に記載してください。
- **提出内容を理解している必要があります:** ご自身の言葉で報告について質問に答えられる
  必要があります。質問に説明できない報告は invalid としてクローズします。
- **完全自動の提出は不可:** 人間の検証を経ずに自律ツールが生成・提出した報告は、確認
  次第クローズします。

## セキュリティ脆弱性

**セキュリティ脆弱性を公開 issue で報告しないでください。** [SECURITY.md](./SECURITY.md)
の手順に従ってください。上記の再現性および AI 開示の要件はセキュリティ報告にも同様に
適用されます。

スコープの区分にご注意ください。本リポジトリが扱うのは Docker パッケージング
（Dockerfile、Compose、nginx 設定、シェルスクリプト）です。Dixlase CMS 本体の脆弱性は
[Dixlase Core](https://github.com/Dixlase/dixlase-core) の管轄です。

## インストーラのバグを効果的に報告するには

本インストーラはほぼシェルと Docker の接着剤なので、多くの場合は失敗時の出力があれば
十分です。特に有用な情報は次のとおりです。

- 使用している**コミットハッシュ**（`git -C <インストーラのディレクトリ> rev-parse --short HEAD`）
- `./setup.sh` のどのステップで失敗したか（スクリプトは `[1/6]` 〜 `[6/6]` を表示します）
- 失敗したステップの**出力全体**。末尾数行だけでは不十分です。Composer や Docker の
  エラーは、最終行より数行上に本当の原因が書かれていることがよくあります。
- 再実行しても再現するか、`./reset.sh` で状況が変わるか

なお、以下の 2 つは**インストーラの不具合ではありません**。先に確認いただけると双方の
時間が節約できます。

- **GitHub の障害。** 依存関係のインストールは GitHub からアーカイブを取得します。障害中は
  `HTTP/2 429`、あるいは紛らわしいことに `Could not authenticate against github.com` として
  現れます。報告前に <https://www.githubstatus.com> をご確認ください。
- **macOS の Docker Desktop における bind mount のタイミング。** コンテナ内で書き込んだ
  ファイルが、直後の操作から一時的に見えないことがあります。

## メンテナおよびフォーク利用者向け

以下は CI が実行しているチェックです。本リポジトリを自身のデプロイ用にフォークする場合にも
必要になるため、ここに記載しています。

```bash
# シェルの構文チェックと lint（CI が対象にしている集合そのもの）
for f in setup.sh reset.sh update.sh entrypoint.sh convert-comments.sh; do bash -n "$f"; done
shellcheck setup.sh reset.sh update.sh entrypoint.sh convert-comments.sh

# Compose の妥当性
docker compose config --quiet

# 翻訳のラウンドトリップ — バイト単位で一致する必要があります
mkdir /tmp/before
cp setup.sh reset.sh update.sh Dockerfile Dockerfile.vite docker-compose.yml .env.example /tmp/before/
cp -r nginx /tmp/before/
./convert-comments.sh ja
./convert-comments.sh ja --reverse
diff -r /tmp/before/nginx nginx && for f in setup.sh reset.sh update.sh Dockerfile Dockerfile.vite docker-compose.yml .env.example; do diff -q "/tmp/before/$f" "$f"; done
```

`lang/` に辞書があるファイルのコメントや `echo` 文字列を追加・変更した場合は、
`lang/en/<file>.tsv`（identity）と `lang/ja/<file>.tsv`（翻訳）に対応するエントリを追加し、
**既存のキーはすべて verbatim のまま維持**してください。CI は各辞書キーがソースファイルに
存在すること、およびラウンドトリップがバイト単位で一致することを検証します。

コミットメッセージは Conventional Commits に従い、subject と本文をバイリンガルで記述します。
完全なルールは [CLAUDE.md](./CLAUDE.md) にあります。

E2E のスモークワークフロー（`.github/workflows/smoke.yml`）は private な Dixlase Core
リポジトリをクローンするため、メンテナ用トークンなしでは実行できません。`main` への
push と `workflow_dispatch` で動作し、マージ前にメンテナがブランチに対して実行します。

## ライセンス

本インストーラは [MIT License](./LICENSE) で配布されています。

## 質問

[Issue](https://github.com/Dixlase/dixlase-docker-installer/issues) を作成するか、
info@dixlase.org までご連絡ください。

Pull Request の受付が始まる前であっても、バグ報告とフィードバックは価値あるコントリビュー
ションです。
