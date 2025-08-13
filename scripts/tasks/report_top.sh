#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# Usage: genomicsctl.sh report-top <upload_id> [N]
cmd_report_top() {
  local u="${1:-}"; local n="${2:-10}"
  [[ -n "$u" ]] || { echo "usage: genomicsctl.sh report-top <upload_id> [N]"; exit 2; }

  local ROOT=${ROOT:-/root/genomics-stack}
  local COMPOSE_FILE="$ROOT/compose.yml"; [[ -f "$ROOT/docker-compose.yml" ]] && COMPOSE_FILE="$ROOT/docker-compose.yml"
  local REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}
  local DIR="$REPORTS_DIR/upload_${u}"
  local TSV="$DIR/top${n}.tsv"
  local HTML="$DIR/top${n}.html"

  mkdir -p "$DIR"

  # One-shot SQL. We embed numeric values directly (no :u) to avoid psql var issues.
  # 1) Take real risk_hits for this upload
  # 2) If fewer than N, UNION VEP rows ranked by impact/clin_sig/AF until we reach N
  read -r -d '' SQL <<SQL
WITH
risk AS (
  SELECT
    'risk' AS src,
    COALESCE(v.rsid,'-') AS rsid,
    g.symbol,
    r.short_title AS title,
    h.zygosity,
    NULL::text AS consequence,
    NULL::text AS impact,
    NULLIF(r.weight::text,'') AS weight,
    NULLIF(h.score::text,'')  AS score,
    NULLIF(r.evidence_notes,'') AS notes,
    h.score::numeric AS rank_score
  FROM public.risk_hits h
  JOIN public.risk_rules r ON r.rule_id = h.rule_id
  JOIN public.genes      g ON g.gene_id = r.gene_id
  LEFT JOIN public.variants v ON v.variant_id = r.variant_id
  WHERE h.upload_id = ${u}
),
vep_pick AS (
  SELECT DISTINCT ON (COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, j.symbol))
    'vep' AS src,
    COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, '-') AS rsid,
    NULLIF(j.symbol,'') AS symbol,
    j.consequence AS title,
    NULL::text AS zygosity,
    j.consequence,
    j.impact,
    NULL::text AS weight,
    NULL::text AS score,
    NULLIF(j.clin_sig,'') AS notes,
    (anno.vep_impact_rank(j.impact))*100
      + CASE WHEN NULLIF(j.clin_sig,'') IS NOT NULL THEN 10 ELSE 0 END
      + COALESCE( (1 - NULLIF(j.af,'-')::numeric), 0 )::numeric AS rank_score
  FROM anno.vep_joined j
  WHERE j.upload_id = ${u}
  ORDER BY COALESCE(anno.first_rsid(j.existing_variation), j.existing_variation, j.symbol),
           (anno.vep_impact_rank(j.impact)) DESC NULLS LAST,
           NULLIF(j.clin_sig,'') DESC NULLS LAST
),
unioned AS (
  SELECT * FROM risk
  UNION ALL
  SELECT * FROM vep_pick
),
ranked AS (
  SELECT u.*, ROW_NUMBER() OVER (ORDER BY rank_score DESC NULLS LAST, symbol NULLS LAST, rsid) AS rn
  FROM unioned u
)
SELECT
  src,
  COALESCE(rsid,'-')   AS rsid,
  COALESCE(symbol,'-') AS symbol,
  COALESCE(title,'-')  AS title,
  COALESCE(zygosity,'-') AS zygosity,
  COALESCE(impact,'-') AS impact,
  COALESCE(score,'-')  AS score,
  COALESCE(weight,'-') AS weight,
  COALESCE(notes,'-')  AS notes
FROM ranked
WHERE rn <= ${n};
SQL

  echo "[+] Building Top-${n} for upload_id=${u}"
  {
    echo -e "src\trsid\tsymbol\ttitle\tzygosity\timpact\tscore\tweight\tnotes"
    docker compose -f "$COMPOSE_FILE" exec -T db \
      psql -U genouser -d genomics -At -F $'\t' -v ON_ERROR_STOP=1 -c "$SQL"
  } > "$TSV"

  # Simple HTML from TSV
  awk -v title="Top ${n} (upload ${u})" 'BEGIN{
    print "<!doctype html><meta charset=utf-8><title>" title "</title>";
    print "<style>body{font:14px sans-serif;margin:20px} table{border-collapse:collapse;width:100%} th,td{border:1px solid #ccc;padding:6px;} th{background:#f6f6f6;text-align:left}</style>";
    print "<h2>" title "</h2><table><thead><tr>"
  }
  NR==1{
    for(i=1;i<=NF;i++) printf "<th>%s</th>", $i; print "</tr></thead><tbody>"; next
  }
  {
    print "<tr>";
    for(i=1;i<=NF;i++){ gsub(/&/,"&amp;",$i); gsub(/</,"&lt;",$i); gsub(/>/,"&gt;",$i); printf "<td>%s</td>", $i }
    print "</tr>";
  }
  END{ print "</tbody></table>" }' FS='\t' OFS='\t' "$TSV" > "$HTML"

  echo "[ok] TSV:  $TSV"
  echo "[ok] HTML: $HTML"
}

register_task "report-top" "Build Top-N report (default N=10, with VEP fallback)" "cmd_report_top"
