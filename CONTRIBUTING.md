# Contributing to the Dixlase Docker Installer

For Japanese, see [CONTRIBUTING.ja.md](./CONTRIBUTING.ja.md).

Thank you for your interest in Dixlase.

## Current Status

Dixlase is in early development. **External pull requests are not currently
accepted** — this installer follows the same contribution policy as
[Dixlase Core](https://github.com/Dixlase/dixlase-core/blob/main/CONTRIBUTING.md),
so that the project has one consistent answer across its repositories while the
Core contribution process is being finalized. This document will be replaced with
a full PR-based contribution guide when that changes.

**Welcome now, via [Issues](https://github.com/Dixlase/dixlase-docker-installer/issues):**

- Bug reports — a clear description, steps to reproduce, expected vs. actual
  behaviour, and environment details (host OS, Docker / Docker Desktop version,
  and whether you are on the HTTP or HTTPS variant)
- Feature suggestions — the use case, proposed behaviour, and alternatives
  considered
- Documentation / translation error reports
- Questions and feedback

**Not accepted yet:** pull requests of any kind (code, documentation,
translations). External PRs opened while this policy is in effect are **closed
without code review** — if your PR addresses a real problem, please re-file it as
an Issue and a maintainer will implement a fix independently.

> Code snippets included in bug reports are treated as **reference information
> only**; a maintainer will independently re-implement any fix. This keeps the
> installer aligned with the contribution policy of the wider Dixlase project.

## Use of AI Tools

AI tools are part of modern development. Every submission must nevertheless be
backed by human understanding:

- **Translation and polishing:** using AI to translate a report into English or
  refine your writing is welcome; no disclosure needed. Reports in Japanese are
  also accepted.
- **AI-generated substance:** if AI tools generated the substance of a report
  (analysis, reproduction hypothesis, proposed fix), state so in the report.
- **You must understand what you submit:** you need to be able to answer
  questions about your report in your own words. Reports whose authors cannot
  explain them when asked are closed as invalid.
- **No fully automated submissions:** reports generated and filed by autonomous
  tools without human verification are closed on sight.

## Security Vulnerabilities

**Do not report security vulnerabilities through public issues.** Follow the
procedure in [SECURITY.md](./SECURITY.md). The reproducibility and AI-disclosure
requirements above apply equally to security reports.

Note the scope split: this repository covers the Docker packaging (Dockerfiles,
Compose, nginx configuration, shell scripts). Vulnerabilities in Dixlase CMS
itself belong to [Dixlase Core](https://github.com/Dixlase/dixlase-core).

## Reporting installer bugs effectively

The installer is mostly shell and Docker glue, so a good report usually needs
little more than the failing output. What helps most:

- The **commit hash** you are on (`git -C <installer dir> rev-parse --short HEAD`)
- Which step of `./setup.sh` failed — the script prints `[1/6]` … `[6/6]`
- The **full output of the failing step**, not just the last few lines. Composer
  and Docker errors are often explained several lines above the final message.
- Whether it reproduces on a second run, and whether `./reset.sh` changes anything

Two known classes of failure are **not** installer bugs, and checking them first
saves everyone time:

- **GitHub outages.** Dependency installation pulls archives from GitHub. During
  an incident this surfaces as `HTTP/2 429` or, confusingly, as
  `Could not authenticate against github.com`. Check
  <https://www.githubstatus.com> before filing.
- **Docker Desktop bind-mount timing on macOS.** Files written inside the
  container are occasionally not visible to the next operation immediately.

## For maintainers and forks

The checks below are what CI runs. They are documented here because they are also
what you need if you fork this repository for your own deployment.

```bash
# Shell syntax + lint (the exact set CI checks)
for f in setup.sh reset.sh update.sh entrypoint.sh convert-comments.sh; do bash -n "$f"; done
shellcheck setup.sh reset.sh update.sh entrypoint.sh convert-comments.sh

# Compose validity
docker compose config --quiet

# Translation round-trip — must be byte-identical
mkdir /tmp/before
cp setup.sh reset.sh update.sh Dockerfile Dockerfile.vite docker-compose.yml .env.example /tmp/before/
cp -r nginx /tmp/before/
./convert-comments.sh ja
./convert-comments.sh ja --reverse
diff -r /tmp/before/nginx nginx && for f in setup.sh reset.sh update.sh Dockerfile Dockerfile.vite docker-compose.yml .env.example; do diff -q "/tmp/before/$f" "$f"; done
```

If you add or change a comment or an `echo` string in a file that has a
dictionary under `lang/`, add the matching entry to `lang/en/<file>.tsv`
(identity) and `lang/ja/<file>.tsv` (translation), and keep every existing key
present verbatim — CI verifies that each dictionary key still exists in its
source file, and that the round trip is byte-for-byte identical.

Commit messages follow Conventional Commits with a bilingual subject and body;
the full rules are in [CLAUDE.md](./CLAUDE.md).

The end-to-end smoke workflow (`.github/workflows/smoke.yml`) clones the private
Dixlase Core repository and cannot run without a maintainer token. It runs on
pushes to `main` and via `workflow_dispatch`; a maintainer runs it against a
branch before merging.

## License

This installer is distributed under the [MIT License](./LICENSE).

## Questions?

Open an [Issue](https://github.com/Dixlase/dixlase-docker-installer/issues) or
email info@dixlase.org.

Even before pull requests open, your bug reports and feedback are valuable
contributions.
