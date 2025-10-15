#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo [error] $0 failed at line $LINENO; exit 1' ERR
# No 'set -euo pipefail' per project preference.
# HTML report assembled from psql outputs (no Python driver needed).

OUTDIR="reports/upload_2"
HTML="$OUTDIR/ctd_report_v2.html"
mkdir -p "$OUTDIR"

# Helper: emit an HTML table for a SQL query
emit_table () {
  local title="$1"
  local sql_file="$2"
  local note="$3"

  echo "<section>"
  echo "  <h2>${title}</h2>"
  if [[ -n "$note" ]]; then
    printf '  <div class="note">%s</div>\n' "$note"
  fi
  echo '  <div class="tblwrap"><table><thead><tr>'

  # Header row
  psql -X -q -v ON_ERROR_STOP=1 -c "\i ${sql_file}" | sed -n '2p' | awk '{for(i=1;i<=NF;i++) printf "<th>%s</th>", $i; print ""}'
  echo '</tr></thead><tbody>'

  # Data rows (machine-readable, then HTML-escaped, numeric-aligned)
  psql -X -q -At -F $'\t' -v ON_ERROR_STOP=1 -c "\i ${sql_file}" | awk -F '\t' '
    function esc(s) {
      gsub("&","&amp;",s); gsub("<","&lt;",s); gsub(">","&gt;",s);
      return s
    }
    function isnum(s) { return (s ~ /^[0-9][0-9,.\-eE]*$/) }
    {
      printf "<tr>";
      for (i=1; i<=NF; i++) {
        v=$i; v=esc(v);
        if (isnum(v)) printf "<td class=\"num\">%s</td>", v; else printf "<td>%s</td>", v;
      }
      print "</tr>";
    }
  '
  echo '  </tbody></table></div>'
  echo '</section>'
}

# KPI widgets (totals)
emit_kpis () {
  psql -X -q -At -F '|' -c "
    WITH fullx AS (SELECT COUNT(*) AS n FROM public.gene_to_chemical),
         strictx AS (SELECT COUNT(*) AS n FROM public.v_ctd_enriched_strict_v2 WHERE is_strict)
    SELECT (SELECT n FROM fullx) AS n_full_edges,
           (SELECT n FROM strictx) AS n_strict_edges,
           (SELECT n FROM fullx)-(SELECT n FROM strictx) AS n_pruned_edges,
           ROUND(100.0*((SELECT n FROM fullx)-(SELECT n FROM strictx)) / NULLIF((SELECT n FROM fullx),0),2) AS pruned_pct;
  " | awk -F'|' '
    {
      printf "<div class=\"kpi\">\
  <div class=\"card\"><b>Total CTD edges</b><br>%s</div>\
  <div class=\"card\"><b>STRICT edges</b><br>%s</div>\
  <div class=\"card\"><b>Pruned edges</b><br>%s</div>\
  <div class=\"card\"><b>Pruned %%</b><br>%s%%</div></div>\n", $1,$2,$3,$4
    }
  '
}

# Build HTML
{
cat <<'HEAD'
<!doctype html><html><head><meta charset="utf-8">
<title>CTD Action Taxonomy Report (v2)</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:24px}
h1{margin:0 0 2px} h2{margin-top:28px} small{color:#555}
.tblwrap{overflow-x:auto;max-height:60vh;border:1px solid #ddd}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:6px 8px;border-bottom:1px solid #eee;vertical-align:top}
thead th{position:sticky;top:0;background:#fff;border-bottom:1px solid #ccc}
tr:nth-child(even) td{background:#fafafa}
td.num{text-align:right;white-space:nowrap}
.kpi{display:flex;gap:20px;margin:10px 0 6px}
.card{border:1px solid #ddd;border-radius:8px;padding:10px 12px}
.note{color:#444;margin:6px 0 10px}
legend{font-size:12px;color:#555}
footer{margin-top:30px;font-size:12px;color:#555}
.badge{display:inline-block;padding:2px 6px;border-radius:6px;background:#eef;border:1px solid #ccd;margin-left:6px;font-size:11px;color:#224}
</style></head><body>
HEAD

printf "<h1>CTD Action Taxonomy Report</h1>\n"
printf "<div><small>Generated: %s</small></div>\n" "$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
emit_kpis
echo '<legend>STRICT = edges after removing generic “affects^expression / response to substance / multi-affects chains”. Families kept: activates | inhibits | binds | modifies. Focus on <b>binds/modifies</b> for mechanistic leads.</legend>'

emit_table "Family distribution (STRICT only)" \
           "scripts/sql/ctd_family_distribution_strict.sql" \
           "Counts after STRICT pruning."

# Full vs STRICT by gene with inline actionable commentary
echo "<section><h2>Full vs STRICT by gene (only genes with changes)</h2>"
echo '<div class="note">Flags high-prune genes (>=25% pruned) and highlights presence of binds/modifies in STRICT.</div>'
echo '<div class="tblwrap"><table><thead><tr>'
psql -X -q -v ON_ERROR_STOP=1 -c "\i scripts/sql/ctd_full_vs_strict_by_gene.sql" | sed -n '2p' | awk '{for(i=1;i<=NF;i++) printf "<th>%s</th>", $i; print ""}'
echo '<th>comment</th></tr></thead><tbody>'
psql -X -q -At -F $'\t' -v ON_ERROR_STOP=1 -c "\i scripts/sql/ctd_full_vs_strict_by_gene.sql" | awk -F '\t' '
  function esc(s){gsub("&","&amp;",s);gsub("<","&lt;",s);gsub(">","&gt;",s);return s}
  function isnum(s){return (s ~ /^[0-9][0-9,.\-eE]*$/)}
  {
    gene=$1; fam=$2; n_full=$3; n_strict=$4; pruned=$5; flag=$6; note=$7;
    comment="";
    if (flag=="high_prune") comment="High prune: likely expression-only; rely on STRICT.";
    if (note=="mechanistic_signal") {
      if (length(comment)>0) comment=comment" ";
      comment=comment"STRICT has binds/modifies → good mechanistic lead.";
    }
    if (comment=="") {
      if (pruned+0>0) comment="Some pruned; prioritize non-expression edges.";
      else comment="—";
    }
    printf "<tr>";
    for (i=1;i<=NF;i++){
      v=$i; v=esc(v);
      if (isnum(v)) printf "<td class=\"num\">%s</td>", v; else printf "<td>%s</td>", v;
    }
    printf "<td>%s</td></tr>\n", esc(comment);
  }'
echo '</tbody></table></div></section>'

emit_table "Top chemicals by pruned edges" \
           "scripts/sql/ctd_top_pruned_chemicals.sql" \
           "High pruned counts often reflect expression-only breadth; deprioritize for causal inference."

emit_table "Sample of pruned edges (names + patterns)" \
           "scripts/sql/ctd_pruned_edges_sample.sql" \
           "Concrete examples of what STRICT removes, useful for QA."

cat <<'FOOT'
<footer><b>Methods:</b> public.ctd_action_family; STRICT excludes generic affects^expression/response chains. Sources: CTD chemicals & chem–gene edges already ingested.</footer>
</body></html>
FOOT
} > "$HTML"

echo "[ok] Wrote $HTML"
