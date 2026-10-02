# Dixlase Docker Installer — Coding Rules

For Japanese, see [CLAUDE.ja.md](./CLAUDE.ja.md).

Rules every contributor (human or AI) must follow when working in this repository.

## Commit Message Convention

Follow the unified commit message convention used across all Dixlase projects.

### Required rules

1. **No `Co-Authored-By:` line**
   - Forbid every `Co-Authored-By` line, including Claude / `noreply@anthropic.com`.

2. **Use a Conventional Commits prefix**
   - `feat:` — new feature
   - `fix:` — bug fix
   - `refactor:` — code change that does not alter behaviour
   - `docs:` — documentation-only change
   - `test:` — adding or updating tests
   - `chore:` — tooling, dependencies, other maintenance

3. **Bilingual format (English / Japanese)**
   - Subject line: `<type>: <English> / <日本語>` (separated by ` / `)
   - Body: **the whole English text first** (paragraphs and bullets), a blank line, **then the whole Japanese text** (paragraphs and bullets). Do not alternate the languages line by line or bullet by bullet
   - Do not put a `---` line between the two halves: `git format-patch` / `git am` read it as the end of the message
   - Pull request descriptions follow the same order

### Template

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

### Notes

- External contributors (anyone who is not a Dixlase core maintainer) are welcome to use English-only commit messages.
- The bilingual format is a core-maintainer rule for this repository, intended to keep the project's bilingual history intact.
- References: `CONTRIBUTING.md` / `CONTRIBUTING.ja.md` in Dixlase Core, and existing commits in `git log`.

## File editing policy

- Write all scripts in POSIX-compliant `bash` so they run on both macOS and Linux.
- For commands that differ between BSD and GNU (e.g. `sed -i`), pick a form that works in both environments (e.g. `sed -i.bak ... && rm *.bak`).
- Hardcoded paths and machine-specific values are forbidden (this is a public installer).

## Language of in-source comments and strings

- **All comments and `echo` / `read` strings in source code must be written in English** (the default locale). Do not write Japanese comments or Japanese UI strings directly.
- Exceptions where Japanese is required:
  - `*.ja.md` documents such as `README.ja.md`
  - Translation dictionaries under `lang/ja/` (this directory is the canonical Japanese source)
  - Bilingual commit messages (see the convention above)
- When you find Japanese comments or Japanese UI strings while editing an existing file:
  1. Replace them with English
  2. Append the English-to-Japanese pair to `lang/ja/<source-path>.tsv`
  3. Append the identity (English-to-English) to `lang/en/<source-path>.tsv` (regenerable via `./convert-comments.sh`)

## Translation library (`lang/{en,ja}/`)

Each source file (`Dockerfile`, `setup.sh`, `nginx/nginx.conf`, etc.) has a corresponding translation dictionary at `lang/<locale>/<source-path>.tsv`.

### Format

Tab-separated, one pair per line:

```
<english-text>	<locale-text>
```

- One source-side text and one target-locale text per line, separated by `\t`
- `lang/en/<file>.tsv` is identity (col1 == col2). `lang/ja/<file>.tsv` is the English-to-Japanese mapping.
- Empty lines and lines with too few columns are ignored.
- Comment lines (starting with `#`) are ordinary entries. Do not put meta comments inside dictionary files.

### Key construction

- **Comments** (`# Text` form): use `# Text` as the key, without leading indentation (sed's partial match preserves the line's indentation).
- **String literals** (`echo "..."` etc.): use the text inside the quotes verbatim as the key, including surrounding whitespace, so display formatting is preserved.

### Bulk conversion script

`./convert-comments.sh` is a bash script that reads the dictionaries and rewrites source files:

```bash
./convert-comments.sh ja                # all files: en -> ja
./convert-comments.sh ja setup.sh       # single file: en -> ja
./convert-comments.sh ja --reverse      # all files: ja -> en (restore)
```

Implementation notes (when modifying the script):
- To avoid partial-match collisions, sort keys by length (longest first) before turning them into sed patterns.
- Use `|` as the sed delimiter, and escape special characters (`\` `.` `[` `]` `*` `^` `$` `|`) via bash parameter expansion (works on both BSD and GNU sed).
- Use the portable `sed -i.bak ... && rm -f *.bak` form.
