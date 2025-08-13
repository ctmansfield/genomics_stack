#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$ROOT_DIR/lib/common.sh"

task_db_counts() {
  say "[+] row counts"
  dc exec -T db psql -U "${PGUSER}" -d "${PGDB}" -c "
  WITH c AS (
    SELECT 'uploads' AS t, count(*)::bigint AS n FROM uploads
    UNION ALL
    SELECT 'staging_array_calls', count(*)::bigint FROM staging_array_calls
  )
  SELECT * FROM c ORDER BY t;"
}

register_task "db-counts" "Quick counts in key tables" task_db_counts
