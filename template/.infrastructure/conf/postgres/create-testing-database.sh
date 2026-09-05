#!/usr/bin/env bash
# Runs once on first PostgreSQL start (mounted into /docker-entrypoint-initdb.d/).
# Creates <database>_test for the test suite. POSTGRES_USER is a superuser,
# so `php artisan test --parallel` can create <database>_test_1, _2, ... itself.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "${POSTGRES_DB}_test";
EOSQL
