#!/usr/bin/env bash
# Minimal, readable CTD report (STRICT-aware, with notes). Writes to reports/upload_2/ctd_report_v3.html
# Tunables (env): TOPN=100 MIN_FULL=40 MIN_PRUNED=10 INCLUDE_OTHER=false TOPN_EDGES=2000 MIN_MECH=3
TOPN="${TOPN:-100}"
MIN_FULL="${MIN_FULL:-40}"
MIN_PRUNED="${MIN_PRUNED:-10}"
INCLUDE_OTHER="${INCLUDE_OTHER:-false}"
TOPN_EDGES="${TOPN_EDGES:-2000}"
MIN_MECH="${MIN_MECH:-3}"

OUT=reports/upload_2
HTML="${OUT}/ctd_report_v3.html"
mkdir -p "$OUT"

# Helper: run SQL with simple param substitution (psql \set doesn't work with heredoc vars easily)
run_sql () {
  local sql_file="$1"
  local tmp="$(mktemp)"
  sed -e "s/:topn::int/${TOPN}/g" \
      -e "s/:min_full::int/${MIN_FULL}/g" \
      -e "s/:min_pruned::int/${MIN_PRUNED}/g" \
      -e "s/:include_other::bool/${INCLUDE_OTHER}/g" \
      -e "s/:topn::int/${TOPN}/g" \
      -e "s/:topn_edges::int/${TOPN_EDGES}/g" \
      -e "s/:min_mech::int/${MIN_MECH}/g" \
    "$sql_file" > "$tmp"
  psql -F $'\t' -A -P footer=off -f "$tmp"
  rm -f "$tmp"
}

# Emit HTML header
{
  echo '<!doctype html><html><head><meta charset="utf-8"><title>CTD report v3</title>'
  cat <<'CSS'
<style>
body{font-family:Inter,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;margin:24px;color:#111}
h1{font-size:28px;margin-bottom:4px} .muted{color:#666}
h2{margin-top:28px;border-bottom:1px solid #eee;padding-bottom:4px}
.note{font-size:13px;color:#444;background:#f7f7fa;border-left:4px solid #6b6; padding:8px 12px;margin:8px 0 16px;border-radius:6px}
.tblwrap{overflow:auto; max-height:60vh; border:1px solid #eee; border-radius:8px}
table{border-collapse:collapse; min-width:800px; width:100%}
th,td{padding:6px 10px; border-bottom:1px solid #eee; font-size:13px}
th{position:sticky; top:0; background:#fafafa; z-index:1}
td.num{text-align:right}
.badge{display:inline-block; padding:2px 6px; font-size:12px; border-radius:6px; background:#eef; color:#224; margin-left:6px}
</style>
CSS
  echo '</head><body>'
  echo '<h1>CTD action taxonomy — strict filters</h1>'
  echo '<div class="muted">Auto-generated from database views you already created.</div>'
} > "$HTML"

# Section helper
emit_section () {
  local title="$1"; local note="$2"
  local data
  data="$(cat)" || data=""
  # convert TSV to HTML table
  local header="$(echo "$data" | head -n1)"
  local rows="$(echo "$data" | tail -n +2)"
  {
    echo "<h2>${title}</h2>"
    echo "<div class='note'>${note}</div>"
    echo '<div class="tblwrap"><table>'
    echo '<thead><tr>'
    IFS=$'\t' read -r -a cols <<< "$header"
    for c in "${cols[@]}"; do printf '<th>%s</th>' "$c"; done
    echo '</tr></thead><tbody>'
    while IFS= read -r line; do
      echo -n '<tr>'
      IFS=$'\t' read -r -a fields <<< "$line"
      for f in "${fields[@]}"; do
        # numeric align heuristic
        if [[ "$f" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
          printf '<td class="num">%s</td>' "$f"
        else
          printf '<td>%s</td>' "$f"
        fi
      done
      echo '</tr>'
    done <<< "$rows"
    echo '</tbody></table></div>'
  } >> "$HTML"
}

# 1) Distribution under STRICT
run_sql scripts/sql/ctd_family_distribution_strict.sql \
| emit_section "Action family distribution (STRICT only)" \
  "Counts limited to edges passing <em>is_strict</em>. Expression/umbrella 'affects^' chains are excluded."

# 2) Top pruned genes (compact, thresholded)
run_sql scripts/sql/ctd_top_pruned_genes_enhanced.sql \
| emit_section "Top genes trimmed by strict mapping" \
  "Shows genes where a large fraction of CTD edges were pruned by strict rules. Tunables: MIN_FULL=${MIN_FULL}, MIN_PRUNED=${MIN_PRUNED}, INCLUDE_OTHER=${INCLUDE_OTHER}, TOPN=${TOPN}."

# 3) Top pruned chemicals (names)
run_sql scripts/sql/ctd_top_pruned_chemicals_enhanced.sql \
| emit_section "Top chemicals trimmed by strict mapping" \
  "Chemicals with many pruned edges (often blanket exposures or assay confounders). Tunables: MIN_PRUNED=${MIN_PRUNED}, TOPN=${TOPN}."

# 4) Sample of pruned edges (filtered)
run_sql scripts/sql/ctd_pruned_edges_sample_filtered.sql \
| emit_section "Sample of pruned edges (filtered)" \
  "Example pruned edges after removing common blanket exposures. Tunables: TOPN_EDGES=${TOPN_EDGES}. Use this to spot any residual patterns worth mapping."

# 5) Full vs STRICT by gene (enhanced)
run_sql scripts/sql/ctd_full_vs_strict_by_gene_enhanced.sql \
| emit_section "Full vs STRICT by gene (detail)" \
  "Per-family counts per gene with % pruned. High values suggest bulk expression-only evidence now excluded by strict mapping."

# 6) Actionability shortlist (strict mechanistic signals)
run_sql scripts/sql/ctd_actionability_shortlist.sql \
| emit_section "Actionability shortlist (STRICT mechanistic)" \
  "Genes retaining STRICT <code>binds/modifies</code> edges — potential mechanistic leads. Tunables: MIN_MECH=${MIN_MECH}, TOPN=${TOPN}."

# Close HTML
echo '</body></html>' >> "$HTML"
echo "[ok] Wrote ${HTML}"
