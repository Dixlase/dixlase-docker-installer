#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.
#
# Entrypoint for the dixlase.test (php-fpm) container.
#
# storage/, bootstrap/cache/ and resources/src/common/css/ are bind-mounted
# from the host and inherit host UIDs. php-fpm workers run as www-data and need
# write access to them:
#   - storage, bootstrap/cache: compiled views, cache, sessions
#   - resources/src/common/css: dls:tailwind:regenerate-plugin-sources rewrites
#     dixlase-tailwind-plugin-sources.css here (atomic .tmp + rename) on install
#     (the wizard calls it after migrate) and whenever plugins change. setup.sh
#     seeds that file as the host user, so without this chown the wizard's write
#     fails with "Permission denied" and the install finalize 500s.
# Chown them on every start so the container works regardless of which user
# created the files on the host.
set -e

cd /var/www/html

for d in storage bootstrap/cache resources/src/common/css; do
  if [ -d "$d" ]; then
    chown -R www-data:www-data "$d" 2>/dev/null || true
  fi
done

exec "$@"
