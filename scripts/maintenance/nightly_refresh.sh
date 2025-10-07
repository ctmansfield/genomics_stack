#!/usr/bin/env bash
set -euo pipefail

# -------- config --------
REPO_DIR="/mnt/nas_storage/repos/genomics-stack"
VENV_DIR="$REPO_DIR/.venv_gs2"
LOG_DIR="/var/log/genomics-stack"
UPLOAD_ID="${UPLOAD_ID:-2}"

PGURL="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}"
CLINVAR_VCF="${CLINVAR_VCF:-/mnt/nas_storage/ref/clinvar/clinvar.vcf.gz}"

mkdir -p "$LOG_DIR" "$REPO_DIR/reports/upload_${UPLOAD_ID}"

# -------- lock to avoid overlap --------
exec 9>"/tmp/genomics-stack-nightly.lock"
if ! flock -n 9; then
  echo "$(date -Is) another instance is running; exiting" | tee -a "$LOG_DIR/nightly.log"
  exit 0
fi

# -------- env / venv --------
source "${VENV_DIR}/bin/activate"
python - <<'PY' >/dev/null
import sys, pkgutil
need = {"pysam","psycopg"}
missing = [m for m in need if not pkgutil.find_loader(m)]
sys.exit(0 if not missing else 1)
PY
if [[ $? -ne 0 ]]; then
  pip install -q pysam "psycopg[binary]"
fi

# -------- ingest ClinVar subset + genes --------
echo "$(date -Is) [nightly] ClinVar subset ingest" | tee -a "$LOG_DIR/nightly.log"
CLINVAR_VCF="$CLINVAR_VCF" UPLOAD_ID="$UPLOAD_ID" \
  python3 "$REPO_DIR/scripts/adapters/clinvar_ingest_subset.py" \
  >> "$LOG_DIR/nightly.log" 2>&1

echo "$(date -Is) [nightly] ClinVar genes ingest" | tee -a "$LOG_DIR/nightly.log"
CLINVAR_VCF="$CLINVAR_VCF" UPLOAD_ID="$UPLOAD_ID" \
  python3 "$REPO_DIR/scripts/adapters/clinvar_genes_ingest.py" \
  >> "$LOG_DIR/nightly.log" 2>&1

# -------- recompute scores (views do it live; optional snapshot) --------
psql "$PGURL" -v ON_ERROR_STOP=1 <<SQL >> "$LOG_DIR/nightly.log" 2>&1
-- optional snapshot table (idempotent)
CREATE TABLE IF NOT EXISTS public.report_variant_scores_snapshot(
  upload_id     int,
  rsid          text,
  gene_symbol   text,
  system_tag    text,
  variant_score double precision,
  captured_at   timestamptz DEFAULT now(),
  PRIMARY KEY (upload_id, rsid, gene_symbol, system_tag)
);

-- refresh snapshot for this upload
DELETE FROM public.report_variant_scores_snapshot WHERE upload_id = ${UPLOAD_ID};
INSERT INTO public.report_variant_scores_snapshot(upload_id, rsid, gene_symbol, system_tag, variant_score)
SELECT ${UPLOAD_ID}, rsid, gene_symbol, system_tag, variant_score
FROM public.v_prioritized_variant_system_scores_v2;
SQL

# -------- exports --------
OUTDIR="$REPO_DIR/reports/upload_${UPLOAD_ID}"
echo "$(date -Is) [nightly] exporting CSV/HTML to $OUTDIR" | tee -a "$LOG_DIR/nightly.log"

psql "$PGURL" -c "\copy (
  SELECT * FROM public.v_prioritized_variant_system_scores_v2
  ORDER BY variant_score DESC NULLS LAST
  LIMIT 200
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/variant_system_scores_top200.csv"

psql "$PGURL" -c "\copy (
  SELECT * FROM (
    SELECT v.*,
           DENSE_RANK() OVER (PARTITION BY system_tag ORDER BY variant_score DESC NULLS LAST) AS rnk
    FROM public.v_prioritized_variant_system_scores_v2 v
  ) q
  WHERE rnk <= 50
  ORDER BY system_tag, rnk
) TO STDOUT WITH CSV HEADER" > "$OUTDIR/variant_system_scores_top50_per_system.csv"

python3 "$REPO_DIR/scripts/reports/make_html_preview.py" \
  "$OUTDIR/variant_system_scores_top200.csv" \
  "$OUTDIR/variant_system_scores_top200.html" \
  >> "$LOG_DIR/nightly.log" 2>&1 || true

python3 "$REPO_DIR/scripts/reports/make_html_preview.py" \
  "$OUTDIR/variant_system_scores_top50_per_system.csv" \
  "$OUTDIR/variant_system_scores_top50_per_system.html" \
  >> "$LOG_DIR/nightly.log" 2>&1 || true

echo "$(date -Is) [nightly] done" | tee -a "$LOG_DIR/nightly.log"
