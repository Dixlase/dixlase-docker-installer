#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# Dixlase source update
# Pulls the latest code from GitHub and refreshes the container.
#
# This advances a git checkout of the core in html/, which is the
# developer path. A site running a released core should update with
# `php artisan dls:core:update` instead: that takes a backup, holds a
# maintenance window and can roll back. This script does none of that.
#
# Usage:
#   ./update.sh              # update the current branch (default: main)
#   ./update.sh <branch>     # switch html/ to <branch>, then update
#   ./update.sh --dev        # skip the asset build (Vite serves them)
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

print_usage() {
    cat <<'EOF'
Usage: ./update.sh [branch] [--dev]

  [branch]   Branch to update html/ to (default: main)
  --dev      Skip the production asset build (the Vite dev server serves them)
EOF
}

BRANCH="main"
DEV_MODE=false
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        -h|--help) print_usage; exit 0 ;;
        --*) echo "  Unknown option: $arg" >&2; exit 1 ;;
        *) BRANCH="$arg" ;;
    esac
done

# Mirror setup.sh: VITE=true in .env means the Vite dev server is the one
# serving the assets, so there is nothing to build here.
if [ -f ".env" ]; then
    VITE_VAL=$(grep '^VITE=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
    if [ "$VITE_VAL" = "true" ] || [ "$VITE_VAL" = "1" ]; then
        DEV_MODE=true
    fi
fi

echo "========================================"
echo "  Dixlase - Source update"
echo "  Branch: $BRANCH"
echo "========================================"
echo ""

if [ ! -d "html" ]; then
    echo "  html/ not found. Run setup.sh first."
    exit 1
fi

# Every step after the git pull runs inside the app container, so say so
# once here instead of letting `docker compose exec` fail six times.
if [ -z "$(docker compose ps -q dixlase.test 2>/dev/null)" ]; then
    echo "  The dixlase.test container is not running."
    echo "  Start the stack first, then run ./update.sh again:"
    echo "    docker compose up -d"
    exit 1
fi

# True when the running core provides the named artisan command. Lets this
# script use core's newer maintenance commands without breaking against an
# older checkout that does not have them yet.
artisan_has() {
    docker compose exec -T dixlase.test php artisan help "$1" >/dev/null 2>&1
}

# -------------------------------------------------
# 1. Update the source
# -------------------------------------------------
echo "[1/6] Updating html/ from GitHub..."
# A release ZIP carries no .git, so there is nothing here to fast-forward.
# Without this the git commands below just print "fatal: not a git
# repository" twice and the script dies at exit 128. That install updates
# through core, which knows how to replace a downloaded tree.
if [ ! -e "html/.git" ]; then
    echo "  html/ is not a git checkout, so there is nothing to pull."
    echo "  An install expanded from a release ZIP looks like this. Update it through core:"
    echo "    docker compose exec dixlase.test php artisan dls:core:update"
    exit 1
fi
cd html
# setup.sh hands html/ to www-data so the install wizard can write there,
# so git sees a worktree owned by another user and refuses it with
# "detected dubious ownership in repository". Allow this one path for
# these commands instead of touching the operator's global git config.
# setup.sh leaves .git itself host-owned, so these writes still work.
HTML_DIR="$(pwd)"
GIT_SAFE=(-c "safe.directory=$HTML_DIR")

# A pull cannot do anything useful with local edits to tracked files: git
# aborts with "Your local changes would be overwritten". Untracked files
# are not a problem (installed plugins and themes are gitignored), so only
# tracked changes stop the update.
#
# One tracked file is core's own bookkeeping: installing the bundled theme
# makes core add `!themes/DixlaseOnePage/` to html/.gitignore (its
# dls:sync:gitignore / GitIgnoreHelper), so every fresh install starts out
# dirty in git's eyes. Restore that one file instead of asking the operator
# to deal with it — core rewrites it whenever it needs to, and leaving it
# would make the fast-forward below refuse the update.
DIRTY=$(git "${GIT_SAFE[@]}" status --porcelain --untracked-files=no | cut -c4-)
if [ -n "$DIRTY" ]; then
    UNEXPECTED=$(printf '%s\n' "$DIRTY" | grep -v '^\.gitignore$' || true)
    if [ -n "$UNEXPECTED" ]; then
        echo "  html/ has local changes to tracked files:"
        printf '%s\n' "$UNEXPECTED" | sed 's/^/    /'
        echo ""
        echo "  Keep or discard them, then run ./update.sh again:"
        echo "    git -C html -c safe.directory=$HTML_DIR stash          # keep for later"
        echo "    git -C html -c safe.directory=$HTML_DIR checkout -- .  # discard"
        exit 1
    fi
    echo "  Restoring html/.gitignore, which core rewrites for the bundled theme."
    git "${GIT_SAFE[@]}" checkout -- .gitignore
fi

CURRENT_BRANCH=$(git "${GIT_SAFE[@]}" rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "HEAD" ]; then
    echo "  html/ is on a detached HEAD, so there is no branch to update."
    echo "  Check out a branch first:"
    echo "    git -C html -c safe.directory=$HTML_DIR checkout $BRANCH"
    exit 1
fi

git "${GIT_SAFE[@]}" fetch origin
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo "  Switching html/ from $CURRENT_BRANCH to $BRANCH..."
    git "${GIT_SAFE[@]}" checkout "$BRANCH" 2>/dev/null \
        || git "${GIT_SAFE[@]}" checkout -b "$BRANCH" --track "origin/$BRANCH"
fi

# Fast-forward only. A merge commit in html/ would make every later update
# diverge further, and `git pull`'s own failure modes ("refusing to merge
# unrelated histories", "divergent branches") arrive as a bare fatal: with
# no hint of what to do next. Decide the case here and name the remedy.
LOCAL_HEAD=$(git "${GIT_SAFE[@]}" rev-parse HEAD)
REMOTE_HEAD=$(git "${GIT_SAFE[@]}" rev-parse "origin/$BRANCH")
if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
    echo "  html/ is already at origin/$BRANCH."
elif git "${GIT_SAFE[@]}" merge-base --is-ancestor "$LOCAL_HEAD" "$REMOTE_HEAD"; then
    git "${GIT_SAFE[@]}" merge --ff-only "origin/$BRANCH"
else
    if git "${GIT_SAFE[@]}" merge-base "$LOCAL_HEAD" "$REMOTE_HEAD" >/dev/null 2>&1; then
        echo "  html/ has diverged from origin/$BRANCH: it carries commits the remote does not have."
    else
        echo "  html/ shares no history with origin/$BRANCH, so the remote branch was rewritten."
    fi
    echo ""
    echo "  To take the remote as it is, discarding local commits in html/:"
    echo "    git -C html -c safe.directory=$HTML_DIR reset --hard origin/$BRANCH"
    echo ""
    echo "  Nothing outside html/ is affected: .env, mysql/ and storage/ are not in git."
    exit 1
fi
cd ..

# -------------------------------------------------
# 2. Update PHP dependencies
# -------------------------------------------------
echo ""
echo "[2/6] Updating dependencies..."
# composer runs inside the container, where the build-time BuildKit secret
# (docker-compose.yml: secrets.composer_auth) no longer exists, so private
# packages such as the bundled theme would 404. Hand the host's auth.json
# to this one command through the environment: it stays out of the image
# and off the container filesystem.
COMPOSER_AUTH_FILE="${COMPOSER_HOME:-$HOME/.composer}/auth.json"
COMPOSER_ENV=()
if [ -f "$COMPOSER_AUTH_FILE" ]; then
    # Export the token and pass it by name. Spelling the value out in the
    # `docker compose exec` arguments would put it in the host's process
    # list for as long as composer runs, where any local user can read it.
    COMPOSER_AUTH="$(cat "$COMPOSER_AUTH_FILE")"
    export COMPOSER_AUTH
    COMPOSER_ENV=(-e COMPOSER_AUTH)
    echo "  Using composer credentials from $COMPOSER_AUTH_FILE."
fi
if ! docker compose exec -T "${COMPOSER_ENV[@]}" dixlase.test composer install --no-interaction; then
    echo ""
    echo "  composer install failed."
    echo '  On a 404 or "Could not authenticate" for a dixlase/* package, the'
    echo "  package is private and composer needs a token. Write one to"
    echo "  $COMPOSER_AUTH_FILE on the host, then run ./update.sh again:"
    echo '    {"github-oauth":{"github.com":"<personal access token>"}}'
    exit 1
fi
echo "  composer install complete."

# Same reason as in setup.sh: core writes composer.local.json (the PSR-4 roots of
# the installed extensions) from a post-autoload-dump hook, so a run that changes
# it leaves the dumped maps one step behind — and core's own repair cannot run
# under php-fpm, where PHP_BINARY is php-fpm rather than the CLI interpreter.
docker compose exec -T dixlase.test composer dump-autoload --optimize --no-interaction

# -------------------------------------------------
# 3. Realign the migration bookkeeping
# -------------------------------------------------
echo ""
echo "[3/6] Realigning migration bookkeeping..."
# Until core's GA its baseline migrations are renumbered in place (core:
# docs/operations/upgrading.md, "Beta series only: reconcile renamed
# migrations"). A renumbered file looks new to `migrate`, which then tries
# to create a table that already exists, so point the ledger at the
# current filenames first. This only rewrites the migration column of the
# bookkeeping tables, never a data table, and is a no-op when nothing was
# renamed. Rows whose file is gone are left alone on purpose; `--prune`
# would delete them.
if artisan_has dls:migration:resync; then
    docker compose exec -T dixlase.test php artisan dls:migration:resync --confirm
else
    echo "  This core has no dls:migration:resync (skipped)."
fi

# -------------------------------------------------
# 4. Run migrations
# -------------------------------------------------
echo ""
echo "[4/6] Running migrations..."
docker compose exec -T dixlase.test php artisan migrate --force
echo "  Migrations complete."

# -------------------------------------------------
# 5. Rebuild the frontend assets
# -------------------------------------------------
echo ""
if [ "$DEV_MODE" = true ]; then
    echo "[5/6] Development mode: Vite dev server serves the assets, build skipped."
else
    echo "[5/6] Rebuilding frontend assets..."
    # public/assets/build is gitignored, so the pull above brought new
    # sources but left the previous build in place. Rebuild it the same way
    # setup.sh does, or the pages keep asking for asset URLs that the new
    # manifest no longer lists.
    docker compose exec -T dixlase.test npm install
    docker compose exec -T dixlase.test rm -f public/hot
    docker compose exec -T dixlase.test npm run build

    # The bundled theme has its own build. On a cold npm cache this step
    # can take several minutes.
    if [ -f html/themes/DixlaseOnePage/package.json ]; then
        echo "  Building theme assets (themes/DixlaseOnePage)..."
        docker compose exec -T dixlase.test php artisan dls:theme:build DixlaseOnePage
    fi

    # Restart web so nginx sees freshly built assets. Docker Desktop bind
    # mounts on macOS sometimes hide files that appeared after the container
    # started; restarting forces nginx to re-read the mounted directory.
    echo "  Restarting web to refresh asset mount..."
    docker compose restart web
fi

# -------------------------------------------------
# 6. Clear caches and reconcile the bookkeeping
# -------------------------------------------------
echo ""
echo "[6/6] Clearing caches..."
docker compose exec -T dixlase.test php artisan config:clear
docker compose exec -T dixlase.test php artisan cache:clear
docker compose exec -T dixlase.test php artisan view:clear
echo "  Caches cleared."

# Advancing html/ with git writes no core_version_history row, so the
# ledger still names the version installed before this run and a later
# `dls:core:update` would compare releases against the wrong one. This
# writes the missing row and is a no-op when the ledger already matches.
if artisan_has dls:core:reconcile; then
    docker compose exec -T dixlase.test php artisan dls:core:reconcile --confirm
fi

# Step 1 restored html/.gitignore so the fast-forward could apply, which
# dropped the "!themes/<Name>/" lines core keeps there for every installed
# extension (GitIgnoreHelper, called from InstallRunner and the admin
# extension pages). Ask core to write them again, one call per extension, so
# the file ends up the way core keeps it instead of the way git ships it.
# Best-effort and quiet: this is bookkeeping, not part of the update.
if artisan_has dls:sync-gitignore; then
    for extension_dir in html/themes/*/; do
        [ -d "$extension_dir" ] || continue
        docker compose exec -T dixlase.test php artisan dls:sync-gitignore \
            --add-theme="$(basename "$extension_dir")" >/dev/null 2>&1 || true
    done
    for extension_dir in html/plugins/*/; do
        [ -d "$extension_dir" ] || continue
        docker compose exec -T dixlase.test php artisan dls:sync-gitignore \
            --add-plugin="$(basename "$extension_dir")" >/dev/null 2>&1 || true
    done
fi

# The steps above ran as root inside the container, so anything they
# created (vendor/, public/assets/build, node_modules) is root-owned. On
# Linux the www-data php-fpm workers then cannot rewrite the built assets
# the admin panel regenerates, so hand the tree back the way setup.sh
# does. .git stays out of it: the git commands above run as the host user.
echo "  Setting html/ ownership to www-data (container app user)..."
docker compose exec -T dixlase.test \
    sh -c 'find /var/www/html -name .git -prune -o -exec chown www-data:www-data {} +' || true

echo ""
echo "========================================"
echo "  Update complete!"
echo "========================================"
echo ""
CORE_VERSION=$(docker compose exec -T dixlase.test cat VERSION 2>/dev/null | tr -d '\r')
echo "  Core version: $CORE_VERSION"
# This script updates core (html/), not the installer itself. Show which
# installer version ran it, so a report can name both.
INSTALLER_VERSION=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION" 2>/dev/null || true)
echo "  Installer version: ${INSTALLER_VERSION:-unknown}"
echo ""
