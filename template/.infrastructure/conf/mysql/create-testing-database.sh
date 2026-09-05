#!/usr/bin/env bash
# Runs once on first MySQL start (mounted into /docker-entrypoint-initdb.d/).
# Creates <database>_test and grants the app user access to every database
# whose name starts with <database>, so `php artisan test --parallel`
# (which creates <database>_test_1, _2, ...) works without manual grants.

mysql --user=root --password="$MYSQL_ROOT_PASSWORD" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}_test\`;
    GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}%\`.* TO '$MYSQL_USER'@'%';
EOSQL
