#!/usr/bin/env python3
import os, sys, pandas as pd
from datetime import datetime

# inputs (produced by scripts/reports/ctd_samples.sh)
DIR = "reports/upload_2"
FILES = {
  "family":        f"{DIR}/ctd_family_distribution_strict.csv",
  "top_genes":     f"{DIR}/ctd_top_pruned_genes.csv",
  "top_chems":     f"{DIR}/ctd_top_pruned_chemicals.csv",
  "pruned_sample": f"{DIR}/ctd_pruned_edges_sample.csv",
  "full_vs_strict":f"{DIR}/ctd_full_vs_strict_by_gene.csv",
  "sentinels":     f"{DIR}/ctd_strict_detail_sentinels.csv",
}

def fmt_int(x):
    try:
        return f"{int(x):,}"
    except Exception:
        return x

def prettify_action(s: str) -> str:
    if not isinstance(s, str): return s
    # turn "affects^expression|increases^abundance" into "affects·expression • increases·abundance"
    s = s.replace('^', '·')
    return " • ".join(part.strip() for part in s.split('|'))

def load_csv(path):
    if not os.path.exists(path): return None
    df = pd.read_csv(path)
    # generic niceties
    for c in df.columns:
        if c.startswith('n_') or c in ('n','n_edges','n_pruned'):
            df[c] = df[c].map(fmt_int)
        if c == 'action_norm':
            df[c] = df[c].map(prettify_action)
    return df

dfs = {k: load_csv(v) for k,v in FILES.items()}

# build HTML
now = datetime.utcnow().isoformat(timespec="seconds")
html_path = f"{DIR}/ctd_report_v2.html"
with open(html_path, "w", encoding="utf-8") as f:
    f.write(f"""<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<title>CTD Report (STRICT + pruned) — {now}Z</title>
<style>
  body {{ font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif; margin: 24px; color:#111; }}
  h1 {{ font-size: 26px; margin: 0 0 8px; }}
  h2 {{ font-size: 20px; margin: 28px 0 8px; border-bottom:1px solid #ddd; padding-bottom:4px; }}
  .meta {{ color:#555; font-size: 12px; margin-bottom: 16px; }}
  .kpis {{ display:flex; gap:16px; flex-wrap:wrap; margin: 12px 0 18px; }}
  .kpi {{ background:#f7f7f8; padding:10px 12px; border-radius:10px; min-width: 160px; }}
  .kpi .h {{ font-size:12px; color:#666; }}
  .kpi .v {{ font-size:18px; font-weight:600; }}
  table {{ width:100%; border-collapse:collapse; font-size: 12.5px; table-layout: fixed; }}
  th, td {{ border-bottom:1px solid #eee; padding:6px 8px; vertical-align: top; }}
  th {{ text-align:left; color:#333; }}
  td.num {{ text-align:right; white-space:nowrap; }}
  td.wrap {{ word-wrap:break-word; white-space: normal; }}
  .note {{ color:#666; font-size: 12px; margin: 6px 0 0; }}
  .break {{ page-break-before: always; }}
</style>
</head>
<body>
<h1>CTD Report (STRICT + pruned)</h1>
<div class="meta">Generated: {now}Z • DB: genome_db • Host: localhost</div>
""")

    # KPIs from family distribution
    fam = dfs["family"]
    if fam is not None and {"action_family","n"}.issubset(fam.columns):
        fam_kpis = []
        for _, r in fam.iterrows():
            fam_kpis.append(f"""<div class="kpi"><div class="h">{r['action_family']}</div><div class="v">{fmt_int(r['n'])}</div></div>""")
        f.write('<div class="kpis">' + "".join(fam_kpis) + '</div>')

    def section(title, df, keep=None, limit=50, wrap_cols=None, num_cols=None, csv_hint=None, break_before=False):
        if df is None or df.empty: return
        if break_before: f.write('<div class="break"></div>')
        f.write(f"<h2>{title}</h2>\n")
        df2 = df.copy()
        if keep: df2 = df2[[c for c in keep if c in df2.columns]]
        if limit: df2 = df2.head(limit)
        # classes per column
        classes = []
        for c in df2.columns:
            if wrap_cols and c in wrap_cols: classes.append("wrap")
            elif num_cols and c in num_cols: classes.append("num")
            else: classes.append("")
        f.write(df2.to_html(index=False, border=0, classes=["tbl"], table_id=None, escape=False,
                            formatters=None,
                            justify="left",
                            col_space=None))
        if csv_hint:
            f.write(f'<div class="note">Showing top {len(df2):,}. Full data: <code>{csv_hint}</code></div>')

    section("Top Genes by Pruned Edge Count",
            dfs["top_genes"], keep=["gene_symbol","n_pruned"],
            num_cols={"n_pruned"}, csv_hint=FILES["top_genes"])

    section("Top Chemicals by Pruned Edge Count",
            dfs["top_chems"], keep=["chem_id","chem_name","n_pruned"],
            wrap_cols={"chem_name"}, num_cols={"n_pruned"}, csv_hint=FILES["top_chems"])

    section("Sample of Pruned Edges",
            dfs["pruned_sample"],
            keep=["gene_symbol","chem_id","chem_name","action_family","action_norm"],
            wrap_cols={"chem_name","action_norm"},
            csv_hint=FILES["pruned_sample"],
            break_before=True)

    section("Full vs STRICT by Gene (diff)",
            dfs["full_vs_strict"],
            keep=["gene_symbol","action_family","n_full","n_strict","pruned"],
            num_cols={"n_full","n_strict","pruned"},
            csv_hint=FILES["full_vs_strict"],
            break_before=True)

    section("STRICT Detail for Sentinels (TP53, APOE, PCSK9)",
            dfs["sentinels"],
            keep=["gene_symbol","action_family","n_edges","chem_id","chem_name","action_norm"],
            wrap_cols={"chem_name","action_norm"},
            num_cols={"n_edges"},
            csv_hint=FILES["sentinels"],
            break_before=True)

    f.write("</body></html>")

print(f"[ok] Wrote {html_path}")
