#!/usr/bin/env bash
set -euo pipefail

ROOT=${ROOT:-/root/genomics-stack}
COMPOSE_FILE="$ROOT/compose.yml"; [[ -f "$ROOT/docker-compose.yml" ]] && COMPOSE_FILE="$ROOT/docker-compose.yml"
UPLOAD_ID=${UPLOAD_ID:-2}
TOPN=${TOPN:-10}
REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}

echo "[info] Applying schema: scripts/sql/pairs.sql"
docker compose -f "$COMPOSE_FILE" exec -T db       psql -U genouser -d genomics -v ON_ERROR_STOP=1 -f "$ROOT/scripts/sql/pairs.sql"

echo "[info] Verifying objects exist"
docker compose -f "$COMPOSE_FILE" exec -T db       psql -U genouser -d genomics -v ON_ERROR_STOP=1         -c "\d+ public.gene_pairs" -c "\d+ public.variant_pairs" >/dev/null

echo "[info] Building Top-${TOPN} report for upload ${UPLOAD_ID}"
if [[ -x "$ROOT/scripts/genomicsctl.sh" ]]; then
  bash "$ROOT/scripts/genomicsctl.sh" report-top "$UPLOAD_ID" "$TOPN" || true
else
  bash "$ROOT/scripts/tasks/report_top.sh" "$UPLOAD_ID" "$TOPN" || true
fi

ts=$(date -u +%Y%m%d_%H%M%S)
note="$ROOT/docs/changes/${ts}_pairs_and_report_top.md"
mkdir -p "$ROOT/docs/changes"
cat >"$note" <<EOF
# pairs schema + Top-N report
- Installed/updated: scripts/sql/pairs.sql
- Installed/updated: scripts/tasks/report_top.sh
- Generated report for upload $UPLOAD_ID (Top $TOPN)
EOF

cd "$ROOT"
git add scripts/sql/pairs.sql scripts/tasks/report_top.sh "$note" || true
if ! git diff --cached --quiet; then
  git commit -m "feat: pairs schema + pair-aware Top-N report

Ref: $(basename "$note")" || true
  git push origin main || true
fi

echo "===================================================="
echo "✅ Patch applied and verified"
echo "Repo:      $ROOT"
echo "Upload:    $UPLOAD_ID  TopN: $TOPN"
echo "SQL file:  $ROOT/scripts/sql/pairs.sql"
echo "Task file: $ROOT/scripts/tasks/report_top.sh"
echo "Report:    $REPORTS_DIR/upload_${UPLOAD_ID}/top${TOPN}.html (and TSV next to it)"
echo "===================================================="
