#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.
#
# Entrypoint for the dixlase.test (php-fpm) container.
#
# Two self-healing steps run on every container start:
#
# 1. storage/ and bootstrap/cache/ are bind-mounted from the host and
#    inherit host UIDs. php-fpm workers run as www-data and need write
#    access to those directories (compiled views, cache, sessions).
#    Chown them so the container works regardless of which user created
#    the files on the host.
#
# 2. public/storage must be a symlink to storage/app/public/ so the
#    media manager's /storage/<path> URLs can serve uploaded files.
#    Without the symlink, uploads succeed and rows land in dls_media,
#    but every thumbnail and preview returns 404. The symlink is
#    equivalent to `php artisan storage:link`; we use a plain ln(1) so
#    it runs before PHP-FPM is ready and matches the existing chown
#    step.
set -e

cd /var/www/html

for d in storage bootstrap/cache; do
  if [ -d "$d" ]; then
    chown -R www-data:www-data "$d" 2>/dev/null || true
  fi
done

if [ ! -e public/storage ] && [ -d storage/app/public ]; then
  ln -s ../storage/app/public public/storage
fi

exec "$@"
