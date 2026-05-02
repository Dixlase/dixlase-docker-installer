#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.
#
# Entrypoint for the dixlase.test (php-fpm) container.
#
# storage/ and bootstrap/cache/ are bind-mounted from the host and
# inherit host UIDs. php-fpm workers run as www-data and need write
# access to those directories (compiled views, cache, sessions). Chown
# them on every start so the container works regardless of which user
# created the files on the host.
set -e

cd /var/www/html

for d in storage bootstrap/cache; do
  if [ -d "$d" ]; then
    chown -R www-data:www-data "$d" 2>/dev/null || true
  fi
done

exec "$@"
