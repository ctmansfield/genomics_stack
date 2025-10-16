#!/usr/bin/env bash
set +e
[ -z "$PGHOST$PGPORT$PGUSER$PGDATABASE" ] && { echo "[ERR] PG* env missing"; exit 1; }
./scripts/refresh_rollups.sh || exit $?
./scripts/refresh_summary.sh || exit $?
./scripts/refresh_gene_search.sh || exit $?
echo "[OK] nightly refresh complete."
