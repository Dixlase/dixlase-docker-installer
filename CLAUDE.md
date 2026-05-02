# Dixlase Docker Installer — Coding Rules

このリポジトリで作業するすべての貢献者 (人間・AI 双方) が従うべきルール。

## Commit Message Convention

Dixlase プロジェクト全体で統一されたコミットメッセージ規約に従う。

### 必須ルール

1. **`Co-Authored-By:` 行を付けない**
   - Claude / `noreply@anthropic.com` を含む一切の `Co-Authored-By` 行を禁止する。

2. **Conventional Commits プレフィックスを使用する**
   - `feat:` — 新機能
   - `fix:` — バグ修正
   - `refactor:` — 動作を変えないコード改善
   - `docs:` — ドキュメントのみの変更
   - `test:` — テストの追加・更新
   - `chore:` — ツーリング、依存関係、その他のメンテナンス

3. **バイリンガル形式 (英 / 日)**
   - Subject 行: `<type>: <English> / <日本語>` (` / ` で区切る)
   - 本文: 英語段落 → 日本語段落の順
   - 各箇条書き: 英語行 + インデントした日本語訳のペア

### 雛形

```
feat: add user profile page / ユーザープロファイルページを追加

Detailed English explanation wrapped at around 72 characters. Explain
the problem this commit is solving and why this particular solution
was chosen.
解決しようとしている問題と、この解決策を選んだ理由を日本語でも説明する。
英語段落と同じ内容を日本語でも併記する。

- Add ProfileController with show/edit actions
  show / edit アクション付き ProfileController を追加
- Create profile Blade views with avatar upload
  アバターアップロード対応のプロファイル Blade ビューを作成
```

### 補足

- 外部コントリビューター (Dixlase コアメンテナーでない方) は英語のみのコミットメッセージも歓迎する。
- バイリンガル形式は本リポジトリのコアメンテナー運用ルールであり、プロジェクトのバイリンガル履歴を保つことを目的とする。
- 参考: Dixlase Core の `CONTRIBUTING.md` / `CONTRIBUTING.ja.md`、および `git log` の既存コミット例。

## ファイル編集の方針

- スクリプトはすべて POSIX 準拠の `bash` で記述する (macOS / Linux 双方で動作させる)。
- `sed -i` などの BSD/GNU 差異が出るコマンドは、両環境で動く形 (例: `sed -i.bak ... && rm *.bak`) を選ぶ。
- ハードコードされたパス・個人マシン依存の値は禁止する (公開配布物のため)。
