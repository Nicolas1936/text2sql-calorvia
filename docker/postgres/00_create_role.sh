#!/bin/bash
# Creates the read-only login of the agent before the SQL script runs (docker-entrypoint-initdb.d, first start only).
# The SQL script then grants it SELECT on the tables and sets default_transaction_read_only and statement_timeout.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v ro_password="$AGENT_RO_PASSWORD" <<'EOSQL'
SELECT format('CREATE ROLE agent_ro LOGIN PASSWORD %L', :'ro_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agent_ro') \gexec
EOSQL
