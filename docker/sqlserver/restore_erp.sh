#!/bin/bash
# Restores the GESPRO database with sqlcmd, once. Run by the erp-restore service of docker-compose.yml.
set -euo pipefail

SQLCMD=/opt/mssql-tools18/bin/sqlcmd
[ -x "$SQLCMD" ] || SQLCMD=/opt/mssql-tools/bin/sqlcmd
HOST="${MSSQL_HOST:-localhost}"
SCRIPT=/restore/01_erp_gespro_sqlserver.sql

exists=$("$SQLCMD" -S "$HOST" -U sa -P "$MSSQL_SA_PASSWORD" -C -h -1 -W -b \
         -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = N'GESPRO'" | tr -d '[:space:]')
if [ "$exists" = "1" ] && [ "${FORCE_RESTORE:-0}" != "1" ]; then
    echo "GESPRO already exists: nothing to do (set FORCE_RESTORE=1 to restore it again)."
    exit 0
fi

echo "Restoring GESPRO from $SCRIPT (one to three minutes)..."
# -C trust the self-signed certificate, -b stop on error, -f 65001 read the script as UTF-8,
# -v pass the password of the read-only login to the script ($(AGENT_RO_PASSWORD) in the SQL)
"$SQLCMD" -S "$HOST" -U sa -P "$MSSQL_SA_PASSWORD" -C -b -f 65001 \
    -v AGENT_RO_PASSWORD="$AGENT_RO_PASSWORD" -i "$SCRIPT"
echo "GESPRO restored."
