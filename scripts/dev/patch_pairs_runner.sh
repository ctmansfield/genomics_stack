#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/root/genomics-stack}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/compose.yml}"
[[ -f "$ROOT/docker-compose.yml" ]] && COMPOSE_FILE="$ROOT/docker-compose.yml"

UPLOAD_ID="${UPLOAD_ID:-2}"
TOPN="${TOPN:-10}"
REPORTS_DIR="${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}"

PAIRS_SQL="$ROOT/scripts/sql/pairs.sql"
REPORT_TASK="$ROOT/scripts/tasks/report_top.sh"

[[ -f "$PAIRS_SQL" ]]  || { echo "[error] missing $PAIRS_SQL"; exit 1; }
[[ -f "$REPORT_TASK" ]]|| { echo "[error] missing $REPORT_TASK"; exit 1; }
chmod +x "$REPORT_TASK" || true

echo "[*] Applying pairs.sql -> Postgres"
docker compose -f "$COMPOSE_FILE" exec -T db \
  psql -U genouser -d genomics -v ON_ERROR_STOP=1 -f - < "$PAIRS_SQL"

echo "[*] Verifying objects"
docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -At -c \
"SELECT 'gene_pairs:'||to_regclass('public.gene_pairs');
 SELECT 'variant_pairs:'||to_regclass('public.variant_pairs');
 SELECT 'uq_gene_pairs_pair:'||(SELECT COUNT(*) FROM pg_constraint WHERE conname='uq_gene_pairs_pair' AND conrelid='public.gene_pairs'::regclass);
 SELECT 'uq_variant_pairs_pair:'||(SELECT COUNT(*) FROM pg_constraint WHERE conname='uq_variant_pairs_pair' AND conrelid='public.variant_pairs'::regclass);
 SELECT 'gene_pairs_named:'||to_regclass('public.gene_pairs_named');
 SELECT 'variant_pairs_named:'||to_regclass('public.variant_pairs_named');" | sed 's/^/  /'

echo "[*] Building Top-${TOPN} for upload ${UPLOAD_ID}"
bash "$ROOT/scripts/genomicsctl.sh" report-top "$UPLOAD_ID" "$TOPN" || true

# changes note + commit (if anything changed)
ts="$(date +%Y%m%d_%H%M%S)"
note="docs/changes/${ts}_rerun_pairs_report.md"
cat >"$ROOT/$note" <<EOF
# Re-run: pair schema apply + Top-${TOPN} report
- Applied \`scripts/sql/pairs.sql\`
- Ensured \`scripts/tasks/report_top.sh\` executable
- Built Top-${TOPN} for upload ${UPLOAD_ID}
Date: $(date -Is)
EOF

pushd "$ROOT" >/dev/null
git add -A
if git diff --cached --quiet; then
  commit_sha="$(git rev-parse --short HEAD)"
  echo "[info] nothing to commit; current HEAD is ${commit_sha}"
else
  git commit -m "chore: re-apply pair schema & build Top-${TOPN} (upload ${UPLOAD_ID})
Ref: ${note}"
  git push origin main || true
  commit_sha="$(git rev-parse --short HEAD)"
fi
popd >/dev/null

html="${REPORTS_DIR}/upload_${UPLOAD_ID}/top${TOPN}.html"
tsv="${REPORTS_DIR}/upload_${UPLOAD_ID}/top${TOPN}.tsv"

echo
echo "===================================================="
echo "✅ Runner completed"
echo "Repo:      $ROOT"
echo "Commit:    ${commit_sha}"
echo "SQL:       $PAIRS_SQL"
echo "Task:      $REPORT_TASK"
if [[ -f "$html" || -f "$tsv" ]]; then
  echo "Report:    ${html} (and TSV next to it)"
else
  echo "Report:    top${TOPN}.{html,tsv} not found — check data for upload ${UPLOAD_ID}"
fi
echo "===================================================="
