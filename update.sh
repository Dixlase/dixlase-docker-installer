#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# Dixlase source update
# Pulls the latest code from GitHub and refreshes the container.
#
# This advances the git checkout of the core in html/. With no argument
# it moves an install made from a release tag to the newest release, and
# an install that tracks a branch along that branch. It takes no backup,
# holds no maintenance window and cannot roll back, so a site with data
# worth keeping is better served by `php artisan dls:core:update`.
#
# Usage:
#   ./update.sh              # newest release, or main for a branch checkout
#   ./update.sh <ref>        # switch html/ to <ref> (a branch or a tag), then update
#   ./update.sh --dev        # skip the asset build (Vite serves them)
#   ./update.sh --rebuild    # rebuild the images first, taking the newest PHP
# ====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

print_usage() {
    cat <<'EOF'
Usage: ./update.sh [ref] [--dev] [--rebuild [--no-cache]]

  [ref]      Branch or tag to update html/ to. The default is the newest
             release for an install made from a tag, and main for one that
             tracks a branch.
  --dev      Skip the production asset build (the Vite dev server serves them)
  --rebuild  Build the images again from the current php:8.3-fpm and replace
             the containers with them. This is what moves an install to a
             newer PHP, a security release included.
  --no-cache Build every layer again rather than reusing the cache. Only has
             an effect together with --rebuild.
EOF
}

# Left empty here on purpose: what the default is depends on whether html/
# tracks a branch or sits on a release tag, which the git section below works
# out from the checkout itself.
REF=""
DEV_MODE=false
REBUILD=false
NO_CACHE=false
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        --rebuild) REBUILD=true ;;
        --no-cache) NO_CACHE=true ;;
        -h|--help) print_usage; exit 0 ;;
        --*) echo "  Unknown option: $arg" >&2; exit 1 ;;
        *) REF="$arg" ;;
    esac
done

# --no-cache decides how the rebuild builds, so on its own it would look
# accepted and do nothing at all.
if [ "$NO_CACHE" = true ] && [ "$REBUILD" = false ]; then
    echo "  --no-cache only has an effect together with --rebuild." >&2
    exit 1
fi

# Mirror setup.sh: VITE=true in .env means the Vite dev server is the one
# serving the assets, so there is nothing to build here.
if [ -f ".env" ]; then
    VITE_VAL=$(grep '^VITE=' .env | cut -d'=' -f2 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
    if [ "$VITE_VAL" = "true" ] || [ "$VITE_VAL" = "1" ]; then
        DEV_MODE=true
    fi
fi

# The image rebuild is a step of its own, and only when it is asked for, so
# the steps number themselves as they run instead of carrying the count in
# every string.
STEP=0
STEP_TOTAL=6
if [ "$REBUILD" = true ]; then
    STEP_TOTAL=7
fi
step() {
    STEP=$((STEP + 1))
    echo "[$STEP/$STEP_TOTAL] $1"
}

# The database image is pinned in docker-compose.yml, overridable with DB_IMAGE
# in .env. MariaDB upgrades mysql/ in place when it starts and no older server
# will open that directory afterwards, so starting a line other than the one the
# data directory records cannot be undone. Read both and compare.
db_image_line() {
    # mariadb:12.3.3 -> 12.3, and 12.3.3-MariaDB -> 12.3. Everything the tag
    # cannot be read as a version (latest, a digest, no tag at all, a registry
    # that carries a port) comes back empty, so the caller skips a comparison
    # it has no business making.
    printf '%s\n' "$1" | sed 's|.*:||' | sed -n 's|^\([0-9][0-9]*\.[0-9][0-9]*\).*|\1|p'
}

db_image_setting() {
    _img=$(grep '^DB_IMAGE=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '[:space:]"')
    if [ -z "$_img" ]; then
        _img=$(sed -n 's|^[[:space:]]*image: *[$]{DB_IMAGE:-\([^}]*\)}.*|\1|p' docker-compose.yml | head -1)
    fi
    printf '%s\n' "$_img"
}

# True once the git section has advanced html/. html/ is bind-mounted into the
# app and web containers, so from that moment the site serves the new core
# while its dependencies, its migrations and its built assets are still the
# ones from before. A run that stops after that point says nothing about it
# otherwise: the last thing printed is whatever failed (#80).
CORE_MOVED=false

on_exit() {
    _status=$?
    if [ "$_status" -ne 0 ] && [ "$CORE_MOVED" = true ]; then
        _core=$(tr -d '\r\n' < html/VERSION 2>/dev/null || true)
        [ -n "$_core" ] || _core="a newer release"
        echo ""
        echo "  This run stopped with html/ already updated to $_core."
        echo "  The site is serving that core now, while its dependencies, its"
        echo "  migrations and its built assets are still the ones from before."
        echo "  Running this script again picks the update up from the beginning,"
        echo "  and is safe to repeat."
    fi
}
trap on_exit EXIT

echo "========================================"
echo "  Dixlase - Source update"
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
# 1. Rebuild the images (--rebuild only)
# -------------------------------------------------
# First, and before html/ is touched. The build needs nothing from the new
# checkout, and it is the step most likely to fail for a reason outside this
# install: a registry or pecl.php.net that does not answer (#74). Failing
# here costs a run that changed nothing, rather than leaving the site serving
# a core release whose dependencies and migrations have not caught up with it
# (#80). composer, the migrations and the asset build all stay after the
# checkout, so everything that has to run against the PHP that will serve the
# site still does.
if [ "$REBUILD" = true ]; then
    step "Rebuilding the images..."
    # The Dockerfile builds on php:8.3-fpm, a tag that moves with every PHP
    # release — but it moves for an install only when the image is built
    # again, and nothing else in this script builds anything. Without this
    # step a site keeps the PHP it was installed with, so a PHP security
    # release never reaches it however often update.sh runs.
    #
    # --pull is what fetches the base image again. Every layer below it is
    # rebuilt on its own once its digest changes, the apt packages and the
    # PHP extensions included, so --no-cache is for the operator who wants
    # the layers rebuilt even when the base image did not move.
    BUILD_ARGS=(--pull)
    if [ "$NO_CACHE" = true ]; then
        BUILD_ARGS+=(--no-cache)
    fi
    # The cron service runs PHP from an image of its own, built from this same
    # Dockerfile, so it needs the same rebuild. It sits in a profile, which has
    # to be named for compose to address the service at all — and only while it
    # is running, because naming it is enough to start one that the operator
    # turned off in .env or stopped by hand.
    REBUILD_SERVICES=(dixlase.test)
    REBUILD_PROFILES=""
    if [ -n "$(COMPOSE_PROFILES=cron docker compose ps -q cron 2>/dev/null)" ]; then
        REBUILD_SERVICES+=(cron)
        REBUILD_PROFILES="cron"
    fi
    echo "  Building: ${REBUILD_SERVICES[*]}"
    COMPOSE_PROFILES="$REBUILD_PROFILES" \
        docker compose build "${BUILD_ARGS[@]}" "${REBUILD_SERVICES[@]}"
    # Only a new container runs the new image. --no-deps keeps mysql out of
    # it: the app container is the one being replaced, and taking the database
    # down under the update would be a far longer outage than this is.
    # Compose leaves a container alone when its image did not change, so a run
    # that found nothing new costs nothing here.
    COMPOSE_PROFILES="$REBUILD_PROFILES" \
        docker compose up -d --no-deps "${REBUILD_SERVICES[@]}"
    # nginx holds the app container's address for as long as its resolver says
    # (valid=30s, see nginx/nginx.*.conf), so a replaced container means 502s
    # until that expires. Restarting web ends the window at once.
    echo "  Restarting web so nginx reaches the new app container..."
    docker compose restart web
    # The steps below exec into the container that was just replaced. Give it
    # the same few seconds setup.sh waits for after `up -d`.
    sleep 5
    echo ""
fi

# -------------------------------------------------
# 2. Update the source
# -------------------------------------------------
step "Updating html/ from GitHub..."
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

# Reading the repository from the host side is fine, but writing the worktree
# is not: Linux does not virtualize bind-mount ownership, so once setup.sh has
# handed html/ to www-data the host user can no longer unlink or create files
# in it, and `git checkout` fails with "unable to unlink old '.gitignore':
# Permission denied". macOS never shows this, which is why it went unnoticed.
#
# Do those writes where root already is. The app container runs as root, its
# image installs git and already marks /var/www/html a safe directory for it
# (see the Dockerfile), and the ownership step at the end of this script hands
# whatever git wrote back to www-data.
git_write() {
    docker compose exec -T -w /var/www/html dixlase.test \
        git -c safe.directory=/var/www/html "$@"
}

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
        echo "    docker compose exec dixlase.test git stash          # keep for later"
        echo "    docker compose exec dixlase.test git checkout -- .  # discard"
        exit 1
    fi
    echo "  Restoring html/.gitignore, which core rewrites for the bundled theme."
    git_write checkout -- .gitignore
fi

CURRENT_BRANCH=$(git "${GIT_SAFE[@]}" rev-parse --abbrev-ref HEAD)

# --tags, because a plain fetch does not always bring new tags along, and a
# release install is identified by one.
git "${GIT_SAFE[@]}" fetch origin --tags

# The newest release tag, read from the tags just fetched so this costs no
# second network call. sort -t. -k1,1n rather than sort -V, which BSD and GNU
# do not agree on, and never a plain sort, which orders v0.1.9 after v0.1.12.
resolve_newest_release_tag() {
    git "${GIT_SAFE[@]}" tag --list \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 | sed 's/^/v/'
}

# setup.sh installs a release tag, which leaves html/ on a detached HEAD, so
# that is what an install with no argument means here: move it to the newest
# release. A checkout that tracks a branch keeps the behaviour it has always
# had, which is main unless an argument names something else.
if [ -z "$REF" ]; then
    if [ "$CURRENT_BRANCH" = "HEAD" ]; then
        REF=$(resolve_newest_release_tag || true)
        if [ -z "$REF" ]; then
            echo "  html/ is on a detached HEAD and origin has no release tag."
            echo "  Name the branch or tag to update to:"
            echo "    ./update.sh main"
            exit 1
        fi
    else
        REF="main"
    fi
fi

# A tag names one commit, so there is nothing to fast-forward: check it out,
# which leaves html/ detached at that release. Everything in the else branch
# is the branch case, unchanged.
if git "${GIT_SAFE[@]}" rev-parse -q --verify "refs/tags/$REF" >/dev/null; then
    TAG_HEAD=$(git "${GIT_SAFE[@]}" rev-parse "refs/tags/$REF^{commit}")
    if [ "$(git "${GIT_SAFE[@]}" rev-parse HEAD)" = "$TAG_HEAD" ]; then
        echo "  html/ is already at $REF."
    else
        echo "  Moving html/ to $REF..."
        git_write -c advice.detachedHead=false checkout --detach "refs/tags/$REF"
        CORE_MOVED=true
    fi
else
    BRANCH="$REF"
    if [ "$CURRENT_BRANCH" = "HEAD" ]; then
        echo "  Switching html/ from a detached HEAD to $BRANCH..."
        git_write checkout "$BRANCH" 2>/dev/null \
            || git_write checkout -b "$BRANCH" --track "origin/$BRANCH"
        CORE_MOVED=true
    elif [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        echo "  Switching html/ from $CURRENT_BRANCH to $BRANCH..."
        git_write checkout "$BRANCH" 2>/dev/null \
            || git_write checkout -b "$BRANCH" --track "origin/$BRANCH"
        CORE_MOVED=true
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
        git_write merge --ff-only "origin/$BRANCH"
        CORE_MOVED=true
    else
        if git "${GIT_SAFE[@]}" merge-base "$LOCAL_HEAD" "$REMOTE_HEAD" >/dev/null 2>&1; then
            echo "  html/ has diverged from origin/$BRANCH: it carries commits the remote does not have."
        else
            echo "  html/ shares no history with origin/$BRANCH, so the remote branch was rewritten."
        fi
        echo ""
        echo "  To take the remote as it is, discarding local commits in html/:"
        echo "    docker compose exec dixlase.test git reset --hard origin/$BRANCH"
        echo ""
        echo "  Nothing outside html/ is affected: .env, mysql/ and storage/ are not in git."
        exit 1
    fi
fi

# The commands above ran as root, so the files git touched inside .git are
# root-owned now. setup.sh promises .git stays host-owned — that is what lets
# the operator run git in html/ themselves, and what the commands this script
# prints rely on — so give it back. -h and find rather than chown -R: an asset
# link with no target must not be followed (#47).
docker compose exec -T dixlase.test \
    find /var/www/html/.git -exec chown -h "$(id -u):$(id -g)" {} + || true
cd ..

# -------------------------------------------------
# 3. Update PHP dependencies
# -------------------------------------------------
echo ""
step "Updating dependencies..."
# Every package core requires is public, so composer needs no credential
# here. Anything it cannot fetch is a network or a packaging problem.
if ! docker compose exec -T dixlase.test composer install --no-interaction; then
    echo ""
    echo "  composer install failed."
    echo "  Every Dixlase package is public, so this is not a credential problem."
    echo "  Check that the container can reach the network, then that github.com"
    echo "  is reachable and healthy, then the repositories entries in"
    echo "  html/composer.json. Run ./update.sh again once the cause is cleared."
    exit 1
fi
echo "  composer install complete."

# Same reason as in setup.sh: core writes composer.local.json (the PSR-4 roots of
# the installed extensions) from a post-autoload-dump hook, so a run that changes
# it leaves the dumped maps one step behind — and core's own repair cannot run
# under php-fpm, where PHP_BINARY is php-fpm rather than the CLI interpreter.
docker compose exec -T dixlase.test composer dump-autoload --optimize --no-interaction

# -------------------------------------------------
# 4. Realign the migration bookkeeping
# -------------------------------------------------
echo ""
step "Realigning migration bookkeeping..."
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
# 5. Run migrations
# -------------------------------------------------
echo ""
step "Running migrations..."
docker compose exec -T dixlase.test php artisan migrate --force
echo "  Migrations complete."

# -------------------------------------------------
# 6. Rebuild the frontend assets
# -------------------------------------------------
echo ""
if [ "$DEV_MODE" = true ]; then
    step "Development mode: Vite dev server serves the assets, build skipped."
else
    step "Rebuilding frontend assets..."
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
# 7. Clear caches and reconcile the bookkeeping
# -------------------------------------------------
echo ""
step "Clearing caches..."
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
    sh -c 'find /var/www/html -name .git -prune -o -exec chown -h www-data:www-data {} +' || true

echo ""
echo "========================================"
echo "  Update complete!"
echo "========================================"
echo ""
CORE_VERSION=$(docker compose exec -T dixlase.test cat VERSION 2>/dev/null | tr -d '\r')
echo "  Core version:      ${CORE_VERSION:-unknown}"
# PHP comes from the image, not from html/, so an install keeps the version it
# was built with until --rebuild replaces it. Print it: an operator asking
# whether a PHP security release has reached the site reads the answer here.
PHP_VERSION=$(docker compose exec -T dixlase.test php -r 'echo PHP_VERSION;' 2>/dev/null | tr -d '\r')
echo "  PHP version:       ${PHP_VERSION:-unknown}"
# This script updates core (html/), not the installer itself. Show which
# installer version ran it, so a report can name both.
INSTALLER_VERSION=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION" 2>/dev/null || true)
echo "  Installer version: ${INSTALLER_VERSION:-unknown}"
echo ""
# Say it where the version is in sight, because nothing else does: a run
# without --rebuild has not touched PHP, and that is not visible in its output.
if [ "$REBUILD" = false ]; then
    echo "  PHP comes from the image built when this install was made. To move it"
    echo "  to the newest php:8.3-fpm (after a PHP security release, say):"
    echo "    ./update.sh --rebuild"
    echo ""
fi

# This script never starts the database container, so a mismatch here changes
# nothing today. Say it anyway: the next plain docker compose up -d would make
# the move, and the operator is the only one who can decide it.
if [ -f mysql/mariadb_upgrade_info ]; then
    DB_IMAGE_VAL=$(db_image_setting)
    DATA_LINE=$(db_image_line "$(tr -d '\r\n' < mysql/mariadb_upgrade_info)")
    IMAGE_LINE=$(db_image_line "$DB_IMAGE_VAL")
    if [ -n "$DATA_LINE" ] && [ -n "$IMAGE_LINE" ] && [ "$DATA_LINE" != "$IMAGE_LINE" ]; then
        echo "  mysql/ was last upgraded by MariaDB $DATA_LINE, while this install is set"
        echo "  to $DB_IMAGE_VAL. Starting the database container would upgrade the data"
        echo "  directory in place, and no older server would open it afterwards. To keep"
        echo "  it where it is, set this in .env:"
        echo "    DB_IMAGE=mariadb:$DATA_LINE"
        echo ""
    fi
fi
