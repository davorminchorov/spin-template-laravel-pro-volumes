#!/usr/bin/env bash
# Runs once on first MariaDB start (mounted into /docker-entrypoint-initdb.d/).
# Creates <database>_test and grants the app user access to every database
# whose name starts with <database>, so `php artisan test --parallel`
# (which creates <database>_test_1, _2, ...) works without manual grants.

database="${MARIADB_DATABASE:-$MYSQL_DATABASE}"
user="${MARIADB_USER:-$MYSQL_USER}"
root_password="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}"

mariadb --user=root --password="$root_password" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS \`${database}_test\`;
    GRANT ALL PRIVILEGES ON \`${database}%\`.* TO '$user'@'%';
EOSQL
