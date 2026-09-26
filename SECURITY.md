# Security Policy

For Japanese, see [SECURITY.ja.md](./SECURITY.ja.md).

This repository is the Docker-based installer for Dixlase CMS. It is a thin layer
of Dockerfiles, Compose definitions, nginx configuration and shell scripts — most
application-level security issues belong to [Dixlase Core](https://github.com/Dixlase/dixlase-core),
not here. See [Scope](#scope) below.

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest commit on `main` | ✅ |
| Older commits / tags | ❌ |

The installer is distributed from `main` rather than as versioned releases, so
fixes land on `main` and operators re-run `./setup.sh` (or `./update.sh`) to pick
them up.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Use either private channel:

- **GitHub Private Vulnerability Reporting (preferred)** — [Open a security advisory](https://github.com/Dixlase/dixlase-docker-installer/security/advisories/new).
  Submissions are protected by HTTPS and visible only to maintainers.
- **Email:** security@dixlase.org

Please include as much of the following as possible:

- The commit hash of the installer you are running
- Step-by-step instructions to reproduce, and your host OS / Docker version
- Proof-of-concept commands, configuration, or screenshots
- The impact: what an attacker gains, and under what preconditions
- Any suggested mitigation

### Report Requirements

To be triaged, a report must identify the **specific commit** affected and
include a **working proof of concept or concrete reproduction steps** against the
installer as written. Reports describing theoretical weaknesses with no
reproduction path, or describing code paths that do not exist in this repository,
are closed as invalid.

### Use of AI Tools in Security Reports

- If AI tools were used to identify, analyze, or describe the issue, **disclose
  this in the report**. Disclosure does not lower the priority of a valid report.
- **You must be able to answer follow-up questions in your own words.** Reports
  whose authors cannot explain them when asked are closed as invalid.
- **Raw, unverified scanner or AI output is not accepted** as a vulnerability
  report. A human must have verified the finding against this repository first.

### No Bug Bounty

Dixlase does not operate a bug bounty program and offers no monetary reward.
Valid reports are credited in the advisory and release notes unless you prefer to
remain anonymous.

## What to Expect

1. **Acknowledgment** — we confirm receipt once we have seen the report
2. **Initial assessment** — we reproduce the issue and assess impact
3. **Remediation plan** — for confirmed issues, we develop a fix strategy
4. **Fix** — merged to `main` as promptly as severity and complexity allow
5. **Public disclosure** — coordinated with the reporter, after the fix is available

We aim to acknowledge reports promptly and to practise coordinated disclosure: we
ask that you give us a reasonable opportunity to respond before disclosing
publicly, and we credit you in the advisory unless you wish to remain anonymous.

## Scope

### In scope

- `Dockerfile`, `Dockerfile.vite`, `docker-compose.yml`
- `nginx/*.conf` (TLS settings, header handling, upstream routing)
- `setup.sh`, `reset.sh`, `update.sh`, `entrypoint.sh`, `app-entrypoint.sh`,
  `convert-comments.sh`
- `.env.example` defaults and the certificate generation in `setup.sh`
- `mysql-initdb/` bootstrap scripts

### Out of scope

- **Dixlase Core itself** — report at
  [Dixlase/dixlase-core](https://github.com/Dixlase/dixlase-core) and see its
  `SECURITY.md`
- Third-party plugins and themes not maintained by exc-D inc.
- Vulnerabilities in upstream images (`php`, `mariadb`, `nginx`, `adminer`,
  `mailpit`, `redis`) already disclosed and patched upstream — we will bump, but
  the finding belongs upstream
- Operator misconfiguration of a deployed instance (we may help mediate)
- Social engineering, physical security, and resource-exhaustion DoS without a
  novel vulnerability

## Security-relevant defaults of this installer

**This installer targets local development.** It is not hardened for exposure to
the public internet, and several defaults are convenience-oriented. Operators who
deploy it beyond a workstation must review the following.

### The bundled TLS certificate is self-signed

`setup.sh` generates a 2048-bit RSA key and a 365-day self-signed certificate for
`CN=localhost` (`certs/localhost.key`, mode `600`). It exists so the local HTTPS
variant works, and is **not suitable for any deployment reachable by others**.
Replace it with a real certificate, or terminate TLS at a proxy in front.

### HTTP is the default

`.env.example` ships `HTTPS=false`, which selects `nginx/nginx.http.conf` and
serves plain HTTP with no redirect. This is deliberate — browsers block
self-signed-certificate pages on first visit, which would hide the install
wizard. Set `HTTPS=true` and re-run `./setup.sh` to switch to the TLS variant.

### Published ports

Ports below are the values shipped in `.env.example` (Dixlase uses a `4xxxx`
namespace to avoid clashing with other local services). `docker-compose.yml`
carries different fallbacks for the case where a variable is unset.

| Service | Default binding | Variable |
|---|---|---|
| web (HTTP) | `40080` on all interfaces | `APP_PORT` |
| web (HTTPS) | `40443` on all interfaces | `APP_SSL_PORT` |
| MySQL | **`127.0.0.1:40306`** | `DB_BIND_ADDRESS` / `FORWARD_DB_PORT` — host-only by default |
| Adminer | **`127.0.0.1:40081`** | `ADMINER_BIND_ADDRESS` / `FORWARD_ADMINER_PORT` — **database administration UI**, `tools` profile |
| Mailpit | **`127.0.0.1:40025`** | `MAILPIT_BIND_ADDRESS` / `FORWARD_MAILPIT_PORT` — captured outbound mail is readable, `tools` profile |
| Redis | not published | only reachable at `redis:6379` inside the compose network, `redis` profile |
| Vite | **`127.0.0.1:40173`** | `VITE_BIND_ADDRESS` / `FORWARD_VITE_PORT` — only with the `dev` profile |

Two things follow from this table:

- **Only the site is published on all interfaces.** Everything else answers from
  this machine only. Setting any `*_BIND_ADDRESS` to `0.0.0.0` publishes a service
  that trusts whoever reaches it: MariaDB accepts the credentials in `.env`,
  Adminer hands them over for you, Mailpit shows every captured mail, and the Vite
  dev server can read files under `html/`. Automated bots scan for exactly this.
  If you need access from another machine, use an SSH tunnel
  (`ssh -L 40081:127.0.0.1:40081 you@host`) rather than a wider bind.
- **Redis has no host-side port at all.** It runs without a password, so a
  published `6379` would let anyone read and forge sessions when `SESSION_DRIVER`
  is `redis`. Containers reach it over the compose network.
- **Adminer and Mailpit are also behind a flag.** `TOOLS=false` in `.env` (then
  `./setup.sh`) does not start them at all.

### Default credentials

`.env.example` ships development credentials (`DB_PASSWORD`, `DB_ROOT_PASSWORD`).
They are a convenience while everything but the site is on `127.0.0.1`, and an
open door as soon as it is not. Change them for anything other than a local,
unexposed workstation — before the first `./setup.sh`, because MariaDB reads them
only when its data directory is created. `setup.sh` warns when a default is still
in place and a service is bound wider than loopback.

### Host SSH keys are not mounted (opt-in)

The DixlaseDeploy plugin's CLI needs the host's SSH keys to authenticate to remote
hosts, but every process in the app container could read them — including the
install scripts of any composer or npm dependency, which `setup.sh` and
`update.sh` run as root. The mount is therefore **not** in `docker-compose.yml`.
Deploy users opt in with `docker-compose.deploy.yml`, either per command
(`docker compose -f docker-compose.yml -f docker-compose.deploy.yml …`) or by
setting `COMPOSE_FILE` in `.env`. Prefer a key dedicated to deployment.

### php-fpm opcache reset endpoint

The app container receives `CORE_FPM_RESET_URL` and `CORE_FPM_RESET_TOKEN`
(generated by `setup.sh` into the root `.env`). Core uses them to refresh
php-fpm's opcache after a web-triggered update by POSTing to
`/system/fpm-cache-reset`. That route is served by the same nginx listener as the
site, so it is reachable by anything that can reach the site; the shared token is
what protects it. Treat the token as a secret, and consider restricting the
location to your Docker network if you expose the site publicly.

### Build-time Composer credentials

`Dockerfile` reads `~/.composer/auth.json` through a BuildKit secret mount so the
private theme dependency can be fetched. The token is available only during
`docker compose build` and is never written into the resulting image.

### File ownership inside the container

`app-entrypoint.sh` chowns `storage/`, `bootstrap/cache/`,
`resources/src/common/css/`, `plugins/`, `themes/` and the html root itself to
`www-data` on every container start, so php-fpm and the install wizard can write
where they must. On Linux hosts this is visible on the host side of the bind
mount. This is intended behaviour, not a defect — but it does mean the
application user can write to those paths.

## Safe Harbor for Security Research

We support good-faith security research and will not pursue legal action against
researchers who:

- Make a good-faith effort to avoid privacy violations, data destruction, and
  service disruption
- Only interact with systems they own or have explicit permission to access
- Do not exploit a vulnerability beyond what is necessary to confirm it
- Do not disclose publicly before we have had a reasonable opportunity to respond
- Comply with all applicable laws

## Contact

For general security questions that are not vulnerability reports:
security@dixlase.org

---

Thank you for helping keep Dixlase and its users safe.
