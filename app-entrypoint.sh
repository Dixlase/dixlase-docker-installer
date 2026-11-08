#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.
#
# Entrypoint for the dixlase.test (php-fpm) container.
#
# Three self-healing steps run on every container start:
#
# 1. storage/, bootstrap/cache/ and resources/src/common/css/ are
#    bind-mounted from the host and inherit host UIDs. php-fpm workers
#    run as www-data and need write access to them:
#      - storage, bootstrap/cache: compiled views, cache, sessions
#      - resources/src/common/css: dls:tailwind:regenerate-plugin-sources
#        rewrites dixlase-tailwind-plugin-sources.css here (atomic .tmp +
#        rename) on install (the wizard calls it after migrate) and
#        whenever plugins change. setup.sh seeds that file as the host
#        user, so without this chown the wizard's write fails with
#        "Permission denied" and the install finalize 500s.
#    Chown them so the container works regardless of which user created
#    the files on the host. The html root itself is chowned too (non-
#    recursively): the install wizard creates .env there by copying
#    .env.example, so www-data must own the root dir to write it, or the
#    install finalize 500s with "copy(/var/www/html/.env): Permission
#    denied" when the clone was made by a non-www-data host user.
#
# 2. plugins/ and themes/ are the extension roots. The plugin/theme
#    install / update / rollback commands rename plugin and theme
#    directories in and out of these two dirs (a rename only needs write
#    on the PARENT dir), so www-data must own plugins/ and themes/
#    themselves. Without this an extension update fails with
#    `rename(.../staging/X, plugins/X): Permission denied` and rolls back
#    (seen when the roots were created by a non-www-data host user, e.g.
#    the release-ZIP seeding path). Chowned non-recursively on purpose:
#    only the container dir must be writable for the rename, and recursing
#    would chown a theme's node_modules/ on every start. mkdir -p first so
#    the roots exist before the first install; both the mkdir and the
#    chown are best-effort (like every other step here) so a malformed
#    html/ tree can never stop php-fpm from starting.
#
# 3. public/storage must be a symlink to storage/app/public/ so the
#    media manager's /storage/<path> URLs can serve uploaded files.
#    Without the symlink, uploads succeed and rows land in dls_media,
#    but every thumbnail and preview returns 404. The symlink is
#    equivalent to `php artisan storage:link`; we use a plain ln(1) so
#    it runs before PHP-FPM is ready and matches the existing chown
#    step.
set -e

cd /var/www/html

for d in storage bootstrap/cache resources/src/common/css; do
  if [ -d "$d" ]; then
    chown -R www-data:www-data "$d" 2>/dev/null || true
  fi
done

for d in plugins themes; do
  mkdir -p "$d" 2>/dev/null || true
  if [ -d "$d" ]; then
    chown www-data:www-data "$d" 2>/dev/null || true
  fi
done

# The install wizard creates .env in the html root by copying .env.example
# (CheckInstallationReady middleware). www-data must own the root dir
# itself to create that file, else install finalize 500s with
# "copy(/var/www/html/.env): Permission denied" when the clone was made by
# a non-www-data host user (e.g. Linux servers, where bind-mount UIDs are
# not virtualized). Non-recursive on purpose (cwd is /var/www/html): only
# the dir entry must be writable to create .env; recursing would chown
# vendor/ and node_modules/ on every start.
chown www-data:www-data . 2>/dev/null || true

# dixlase.test and cron build from the same image, mount the same html/ and
# run this entrypoint with nothing ordering one after the other, so both can
# reach this point while public/storage does not exist yet. Remove the nested
# link an earlier start may have left (see below) before the guard runs: -e
# follows a link, so a dangling one is invisible to it either way.
if [ -L storage/app/public/public ] && [ ! -e storage/app/public/public ]; then
  rm -f storage/app/public/public
fi

# -n keeps ln(1) from following public/storage when it is already a symlink to
# a directory: plain `ln -s` would then create the link *inside* it, as
# storage/app/public/public -> ../storage/app/public, which resolves from
# storage/app/public/ and points at nothing. That dangling path is what a chown
# without -h stops on, leaving part of html/ owned by the host user. With -f the
# container that loses the race writes the same link again instead, and a
# public/storage left dangling by an earlier start is repaired rather than kept.
if [ ! -e public/storage ] && [ -d storage/app/public ]; then
  ln -sfn ../storage/app/public public/storage 2>/dev/null || true
fi

# 4. The profiler extension is loaded here and nowhere else. Building it
#    into the image (PROFILER=true) does not enable it; this step writes
#    the ini that php-fpm reads at startup, and only when PROFILER=true
#    and PROFILER_KEY is a non-empty value. The ini is removed first, so
#    turning PROFILER off and restarting the container is enough to turn
#    the profiler off -- no rebuild, and no stale ini left behind by an
#    earlier start.
#
#    The whitelist has to be permissive because php never sees the real
#    client: every request arrives from the web container, so the address
#    PHP checks is nginx's. The key is what actually guards the profiler,
#    which is why an empty one leaves it off rather than open.
SPX_INI=/usr/local/etc/php/conf.d/zz-spx.ini
rm -f "$SPX_INI"
if [ "${PROFILER:-false}" = "true" ]; then
  spx_so=$(find /usr/local/lib/php/extensions -name spx.so -print 2>/dev/null | head -1)
  if [ -z "$spx_so" ]; then
    echo "PROFILER=true, but this image has no profiler extension. Rebuild it: docker compose build dixlase.test." >&2
  elif [ -z "${PROFILER_KEY:-}" ]; then
    echo "PROFILER=true, but PROFILER_KEY is empty. Leaving the profiler off." >&2
  else
    {
      echo 'extension=spx.so'
      echo 'spx.http_enabled=1'
      echo 'spx.http_ip_whitelist="*"'
      echo "spx.http_key=\"${PROFILER_KEY}\""
    } > "$SPX_INI"
    echo "Profiler enabled (php-spx). Requests need the key; see README."
  fi
fi

exec "$@"
