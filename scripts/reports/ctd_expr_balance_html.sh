#!/usr/bin/env bash
set -Eeuo pipefail

OUTDIR="${OUTDIR:-reports/upload_2}"
KPIS_CSV="${KPIS_CSV:-$OUTDIR/ctd_expr_balance_kpis.csv}"
GENE_CSV="${GENE_CSV:-$OUTDIR/ctd_expr_balance_genes.csv}"
CHEM_CSV="${CHEM_CSV:-$OUTDIR/ctd_expr_balance_chemicals.csv}"

BODY_HTML="$OUTDIR/ctd_expr_balance_body.html"
FULL_HTML="$OUTDIR/ctd_expr_balance.html"

need() { for p in "$@"; do [[ -f "$p" ]] || { echo "[missing] $p"; exit 1; }; done; }
need "$KPIS_CSV" "$GENE_CSV" "$CHEM_CSV"

# Read header & (optional) totals row safely
IFS=, read -r _h1 _h2 _h3 _h4 < <(head -n1 "$KPIS_CSV")
if read -r INC DEC BAL NONE < <(sed -n '2p' "$KPIS_CSV"); then
  : # values filled
else
  INC=0; DEC=0; BAL=0; NONE=0
fi

style='
<style>
  .kpi{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0 16px}
  .badge{border:1px solid #ddd;border-radius:999px;padding:4px 10px;font:500 12px/1.4 system-ui,Segoe UI,Roboto,Helvetica,Arial}
  .badge.inc{background:#fff4f4;border-color:#ffd8d8}
  .badge.dec{background:#f4f8ff;border-color:#d8e6ff}
  .badge.bal{background:#e8f7e8;border-color:#c5ebc5}
  .badge.none{background:#f2f2f2;border-color:#e0e0e0}
  .tblwrap{overflow:auto;margin:6px 0 18px}
  table{border-collapse:collapse;width:100%}
  th,td{border:1px solid #eee;padding:6px 8px;font:12px/1.35 system-ui,Segoe UI,Roboto,Helvetica,Arial;white-space:nowrap}
  th{background:#fafafa;text-align:left}
  td.num{text-align:right}
  .subtle{color:#666;font-size:11px;margin-top:2px}
</style>
'

render_top() {
  # Safe param handling under `set -u`
  local path="${1:?csv path}"; shift || true
  local title="${1:-}"; shift || true
  local note="${1:-}"; shift || true
  local max="${1:-15}"

  local hdr rows
  hdr="$(head -n1 "$path" || true)"
  rows="$(tail -n +2 "$path" | head -n "$max" || true)"

  # Header
  local th=""
  if [[ -n "${hdr:-}" ]]; then
    IFS=, read -r -a H <<<"$hdr"
    for c in "${H[@]}"; do th+="<th>${c}</th>"; done
  fi

  # Rows
  local tb=""
  if [[ -n "${rows:-}" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      IFS=, read -r -a C <<<"$line"
      local tds=""
      for v in "${C[@]}"; do
        if [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
          tds+="<td class=\"num\">${v}</td>"
        else
          tds+="<td>${v}</td>"
        fi
      done
      tb+="<tr>${tds}</tr>"
    done <<<"$rows"
  fi

  printf '%s\n' "
  <section>
    <h3>${title}</h3>
    ${note:+<div class=\"subtle\">$note</div>}
    <div class=\"tblwrap\">
      <table>
        <thead><tr>${th}</tr></thead>
        <tbody>${tb}</tbody>
      </table>
    </div>
  </section>
  "
}

BODY=$(cat <<HTML
${style}
<h2>Expression Balance (CTD)</h2>
<div class="kpi">
  <span class="badge inc">↑ majority: ${INC}</span>
  <span class="badge dec">↓ majority: ${DEC}</span>
  <span class="badge bal">balanced: ${BAL}</span>
  <span class="badge none">no expr edges: ${NONE}</span>
</div>

$(render_top "$GENE_CSV" "Top genes by expression-edge volume" \
  "Flag legend: inc_majority ≥70% ↑; dec_majority ≥70% ↓; balanced otherwise. Sorted by total_expr." 15)

$(render_top "$CHEM_CSV" "Top chemicals by expression-edge volume" \
  "Includes chemical name when available. Sorted by total_expr." 15)
HTML
)

printf '%s\n' "$BODY" > "$BODY_HTML"
echo "[ok] Wrote $BODY_HTML"

printf '<!doctype html><meta charset="utf-8"><title>CTD — Expression Balance</title>\n<body>\n%s\n</body>\n' "$BODY" > "$FULL_HTML"
echo "[ok] Wrote $FULL_HTML"
