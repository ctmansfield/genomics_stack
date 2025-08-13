#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

ROOT=${ROOT:-/root/genomics-stack}
COMPOSE_FILE="$ROOT/compose.yml"; [ -f "$ROOT/docker-compose.yml" ] && COMPOSE_FILE="$ROOT/docker-compose.yml"
REPORTS_DIR=${REPORTS_DIR:-/mnt/nas_storage/genomics-stack/reports}

die(){ echo "[error] $*" >&2; exit 1; }

cmd_report_top(){
  local upload_id="${1:-}"; local limit="${2:-10}"
  [ -n "$upload_id" ] || die "usage: genomicsctl.sh report-top <upload_id> [N]"

  local OUT="$REPORTS_DIR/upload_${upload_id}"
  mkdir -p "$OUT"
  local TSV="$OUT/top${limit}.tsv"
  local HTML="$OUT/top${limit}.html"

  # Build TSV via psql
  docker compose -f "$COMPOSE_FILE" exec -T db psql -U genouser -d genomics -At -F $'\t' -v ON_ERROR_STOP=1 \
    -v u="$upload_id" -v n="$limit" -c "
WITH h AS (
  SELECT r.gene_id, g.symbol,
         v.rsid, h.zygosity, h.score,
         r.short_title, r.impact_blurb, r.nutrition_note
  FROM public.risk_hits h
  JOIN public.risk_rules r USING(rule_id)
  JOIN public.genes g ON g.gene_id = r.gene_id
  LEFT JOIN public.variants v ON v.variant_id = r.variant_id
  WHERE h.upload_id = :u
),
g AS (
  SELECT gene_id, symbol,
         ROUND(SUM(score)::numeric,2) AS total_score,
         COUNT(*) AS variants_hit,
         -- e.g. rs6025(hom), rs1799963(hom)
         string_agg(DISTINCT COALESCE(rsid,'?')||'('||COALESCE(zygosity,'?')||')', ', ' ORDER BY rsid) AS variant_details,
         -- collapse descriptive text
         NULLIF(string_agg(DISTINCT impact_blurb, ' ' ORDER BY impact_blurb), '') AS summary,
         NULLIF(string_agg(DISTINCT COALESCE(nutrition_note,''), ' ' ORDER BY nutrition_note), '') AS nutrition
  FROM h
  GROUP BY gene_id, symbol
)
SELECT 'gene','total_score','#variants','variant_details','summary','nutrition'
UNION ALL
SELECT symbol,
       total_score::text,
       variants_hit::text,
       COALESCE(variant_details,'—'),
       COALESCE(summary,'—'),
       COALESCE(nutrition,'—')
FROM g
ORDER BY total_score DESC, symbol
LIMIT :n;
" > "$TSV"

  # Render pretty HTML with score bars
  awk -v title="Top ${limit} Genes — Upload ${upload_id}" -v now="$(date -Is)" -v OFS="\t" '
    BEGIN{
      print "<!doctype html><meta charset=utf-8><title>" title "</title>";
      print "<style>body{font:14px system-ui,Segoe UI,Arial} h1{margin:.2em 0}.meta{color:#666}";
      print "table{border-collapse:collapse;width:100%;margin-top:10px}";
      print "th,td{border:1px solid #ddd;padding:8px;vertical-align:top}";
      print "th{background:#fafafa;position:sticky;top:0}";
      print "tr:nth-child(even){background:#fcfcfc}";
      print ".bar{height:10px;background:linear-gradient(90deg,#4f46e5,transparent);border-radius:4px}";
      print ".NUM{white-space:nowrap;text-align:right}";
      print ".muted{color:#777}";
      print "</style>";
      print "<h1>" title "</h1><div class=meta>Generated " now "</div>";
      print "<table><thead><tr><th>Gene</th><th>Total score</th><th># Variants</th><th>Variant details</th><th>Summary</th><th>Nutrition</th></tr></thead><tbody>";
    }
    NR==1 { next } # skip TSV header (we write our own)
    {
      gene=$1; score=$2; nv=$3; det=$4; sum=$5; nut=$6;
      barw = (score+0)*20; if (barw>400) barw=400; # 1 point ≈ 20px, cap
      if(sum=="—") sum="<span class=muted>—</span>";
      if(nut=="—") nut="<span class=muted>—</span>";
      printf "<tr><td><b>%s</b></td>", gene;
      printf "<td class=NUM>%.2f<div class=bar style=\"width:%dpx\"></div></td>", score, barw;
      printf "<td class=NUM>%s</td>", nv;
      printf "<td>%s</td><td>%s</td><td>%s</td></tr>\n", det, sum, nut;
    }
    END{ print "</tbody></table>" }
  ' "$TSV" > "$HTML"

  echo "[ok] Top-$limit TSV:   $TSV"
  echo "[ok] Top-$limit HTML:  $HTML"
}

# Register task
register_task "report-top" "Build Top-N gene report (TSV+HTML)" "cmd_report_top"
