# Dixlase Docker Installer — Coding Rules

For English, see [CLAUDE.md](./CLAUDE.md).

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
   - 本文: **英語の文章(段落と箇条書き)をひととおり書き**、空行を挟んで、**日本語の文章(段落と箇条書き)をひととおり書く**。行ごと・箇条書きごとに英日を交互に書かない
   - 英語と日本語の間に `---` の行は入れない(`git format-patch` / `git am` がメッセージの終わりと読むため)
   - Pull Request の説明も同じ並びにする

### 雛形

```
feat: add user profile page / ユーザープロファイルページを追加

Detailed English explanation wrapped at around 72 characters. Explain
the problem this commit is solving and why this particular solution
was chosen.

- Add ProfileController with show/edit actions
- Create profile Blade views with avatar upload

解決しようとしている問題と、この解決策を選んだ理由を日本語で説明する。
英語の本文と同じ内容を、英語のあとにまとめて書く。

- show / edit アクション付き ProfileController を追加
- アバターアップロード対応のプロファイル Blade ビューを作成
```

### 補足

- 外部コントリビューター (Dixlase コアメンテナーでない方) は英語のみのコミットメッセージも歓迎する。
- バイリンガル形式は本リポジトリのコアメンテナー運用ルールであり、プロジェクトのバイリンガル履歴を保つことを目的とする。
- 参考: Dixlase Core の `CONTRIBUTING.md` / `CONTRIBUTING.ja.md`、および `git log` の既存コミット例。

## ファイル編集の方針

- スクリプトはすべて POSIX 準拠の `bash` で記述する (macOS / Linux 双方で動作させる)。
- `sed -i` などの BSD/GNU 差異が出るコマンドは、両環境で動く形 (例: `sed -i.bak ... && rm *.bak`) を選ぶ。
- ハードコードされたパス・個人マシン依存の値は禁止する (公開配布物のため)。

## ソース内コメント・文字列の言語

- **ソースコード上のコメント・echo/read 文字列はすべて英語で書く** (デフォルトロケール)。日本語コメント・日本語 UI 文字列を直接書かない。
- 日本語が必要な場面 (例外):
  - `README.ja.md` のような `*.ja.md` ドキュメント
  - `lang/ja/` 配下の翻訳辞書 (本ディレクトリは日本語の正規ソース)
  - コミットメッセージのバイリンガル併記 (上記規約参照)
- 既存ファイルを編集する際に日本語コメント・日本語 UI 文字列を見つけたら:
  1. 英語に置き換える
  2. 該当の英語テキストと日本語の対訳を `lang/ja/<source-path>.tsv` に追記する
  3. `lang/en/<source-path>.tsv` にも identity (英→英) を追記する (`./convert-comments.sh` 経由で再生成可)

## 翻訳ライブラリ (`lang/{en,ja}/`)

各ソースファイル (`Dockerfile`、`setup.sh`、`nginx/nginx.conf` 等) は、対応する翻訳辞書を `lang/<locale>/<source-path>.tsv` に持つ。

### フォーマット

タブ区切りの 1 行 1 ペア:

```
<english-text>	<locale-text>
```

- 1 行に source 側テキストと target ロケール側テキストを `\t` で区切って記述する
- `lang/en/<file>.tsv` は identity (col1 == col2)。`lang/ja/<file>.tsv` は英→日の対訳
- 空行・カラム数不足の行は無視される
- コメント行 (`#` 始まり) も普通のエントリ。辞書ファイル内にメタコメントは入れない

### キーの作り方

- **コメント** (`# Text` 形式): 行頭インデントを含めず `# Text` をキーにする (sed の部分一致が行頭インデントを保持するため)
- **文字列リテラル** (`echo "..."` 等): 引用符内のテキストをそのままキーにする (前後の空白も含めて表示用整形を保つ)

### 一括変換スクリプト

`./convert-comments.sh` は辞書を読んでソースを書き換える bash スクリプト:

```bash
./convert-comments.sh ja                # 全ファイル: 英 -> 日
./convert-comments.sh ja setup.sh       # 単一ファイル: 英 -> 日
./convert-comments.sh ja --reverse      # 全ファイル: 日 -> 英 (復元)
```

実装上の注意 (改修する場合):
- 部分一致衝突を避けるため、キーは長い順に sed パターン化する
- sed の delimiter は `|` を使い、特殊文字 (`\` `.` `[` `]` `*` `^` `$` `|`) は bash の parameter expansion で escape する (BSD/GNU 双方で動かすため)
- `sed -i.bak ... && rm -f *.bak` の portable 形式を使う
