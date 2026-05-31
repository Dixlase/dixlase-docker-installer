#!/bin/bash
# DB privilege separation — fires only on a fresh MariaDB data directory.
#
# The image auto-creates `${MYSQL_USER}` with ALL PRIVILEGES on
# `${MYSQL_DATABASE}`. This script:
#
#   1. Strips DDL grants from `${MYSQL_USER}`, leaving SELECT / INSERT /
#      UPDATE / DELETE / EXECUTE / SHOW VIEW. The runtime user can read
#      and write rows but can no longer create, alter, drop, or
#      truncate tables. A misrouted destructive DDL query — e.g. a
#      stray `RefreshDatabase` pointed at production by a path-direct
#      `artisan test` — is then rejected at the wire-protocol layer.
#
#   2. Creates a separate `${DB_MIGRATE_USERNAME}` with ALL PRIVILEGES,
#      to be used only by `php artisan migrate --database=mysql_migrate`
#      and by deploy scripts.
#
# Behaviour rules:
#
#   - When DB_MIGRATE_USERNAME or DB_MIGRATE_PASSWORD is unset, this
#     script logs and exits 0 without touching grants. The MariaDB
#     image's default single-user setup is left as-is. This is the
#     opt-in path documented in the operations guide.
#
#   - When both are set, the privilege split is applied unconditionally.
#     The data directory is fresh (init scripts only fire then), so we
#     can issue REVOKE without disrupting a live application.
#
# Background:
#   docs/incidents/2026-05-29-mysql-tables-dropped.md  (in dixlase-core)
#   docs/operations/db-privilege-separation.md         (in dixlase-core)

set -eu

if [ -z "${DB_MIGRATE_USERNAME:-}" ] || [ -z "${DB_MIGRATE_PASSWORD:-}" ]; then
  echo "[initdb 01-permissions] DB_MIGRATE_USERNAME / DB_MIGRATE_PASSWORD not set — staying in single-user mode."
  echo "[initdb 01-permissions] To opt in to privilege separation, set both vars in .env and re-init the MySQL data directory."
  exit 0
fi

echo "[initdb 01-permissions] Splitting privileges: ${MYSQL_USER} (DML only) + ${DB_MIGRATE_USERNAME} (DDL)."

# The MariaDB image already started the server on the local socket as
# part of the bootstrap; the official init scripts run before the
# server is exposed externally. Use the root socket session.
mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
-- Lock the application user down to DML grants only.
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${MYSQL_USER}'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE, SHOW VIEW
  ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

-- Create the migrator user with full grants.
CREATE USER IF NOT EXISTS '${DB_MIGRATE_USERNAME}'@'%' IDENTIFIED BY '${DB_MIGRATE_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${DB_MIGRATE_USERNAME}'@'%';

FLUSH PRIVILEGES;
SQL

echo "[initdb 01-permissions] Done. Run migrations via: php artisan migrate --database=mysql_migrate"
