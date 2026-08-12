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
#    the files on the host.
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

if [ ! -e public/storage ] && [ -d storage/app/public ]; then
  ln -s ../storage/app/public public/storage
fi

exec "$@"
