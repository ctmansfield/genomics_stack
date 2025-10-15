#!/usr/bin/env python3
import os, psycopg2, html
from datetime import datetime, timezone

PGHOST = os.getenv("PGHOST","localhost")
PGPORT = int(os.getenv("PGPORT","5432"))
PGUSER = os.getenv("PGUSER","genouser")
PGDATABASE = os.getenv("PGDATABASE","genome_db")
PGPASSWORD = os.getenv("PGPASSWORD","")

OUTDIR = "reports/upload_2"
os.makedirs(OUTDIR, exist_ok=True)
HTML = os.path.join(OUTDIR, "ctd_report_v3.html")

def q(cur, sql):
    cur.execute(sql)
    cols = [d.name for d in cur.description]
    rows = cur.fetchall()
    return cols, rows

def num(x):
    try:
        return f"{int(x):,}"
    except:
        try:
            return f"{float(x):,.2f}"
        except:
            return x

def table_html(title, cols, rows, note=None, max_rows=None):
    if max_rows is not None:
        rows = rows[:max_rows]
    th = "".join(f"<th>{html.escape(c)}</th>" for c in cols)
    tb = []
    for r in rows:
        tds = []
        for v in r:
            s = "" if v is None else str(v)
            # right-align numerics
            align = ' class="num"' if isinstance(v, (int,float)) or s.replace(',','').replace('.','',1).isdigit() else ""
            tds.append(f"<td{align}>{html.escape(s)}</td>")
        tb.append("<tr>" + "".join(tds) + "</tr>")
    note_html = f'<div class="note">{html.escape(note)}</div>' if note else ""
    return f"""
<section>
  <h2>{html.escape(title)}</h2>
  {note_html}
  <div class="tblwrap">
  <table>
    <thead><tr>{th}</tr></thead>
    <tbody>
      {''.join(tb)}
    </tbody>
  </table>
  </div>
</section>
"""

def main():
    conn = psycopg2.connect(host=PGHOST, port=PGPORT, user=PGUSER, password=PGPASSWORD, dbname=PGDATABASE)
    cur = conn.cursor()

    # Executive metrics
    cols_a, rows_a = q(cur, """
      WITH fullx AS (SELECT COUNT(*) AS n FROM public.gene_to_chemical),
           strictx AS (SELECT COUNT(*) AS n FROM public.v_ctd_enriched_strict_v2 WHERE is_strict)
      SELECT (SELECT n FROM fullx) AS n_full_edges,
             (SELECT n FROM strictx) AS n_strict_edges,
             (SELECT n FROM fullx)-(SELECT n FROM strictx) AS n_pruned_edges,
             ROUND(100.0*((SELECT n FROM fullx)-(SELECT n FROM strictx)) / NULLIF((SELECT n FROM fullx),0),2) AS pruned_pct;
    """)
    m = dict(zip(cols_a, rows_a[0]))
    for k in list(m.keys()): m[k] = num(m[k])

    # Family distribution (STRICT only)
    cols_fam, rows_fam = q(cur, """
      SELECT action_family, COUNT(*) AS n_edges
      FROM public.v_ctd_enriched_strict_v2
      WHERE is_strict
      GROUP BY 1
      ORDER BY n_edges DESC;
    """)

    # Full vs STRICT by gene (actionable diff)
    cols_diff, rows_diff = q(cur, open("scripts/sql/ctd_full_vs_strict_by_gene.sql","r").read())

    # Add comment column
    idx_gene = cols_diff.index("gene_symbol")
    idx_flag = cols_diff.index("prune_flag")
    idx_note = cols_diff.index("actionability_note")
    idx_pruned = cols_diff.index("pruned")
    comments = []
    for r in rows_diff:
        flag = r[idx_flag]
        note = r[idx_note]
        pruned = r[idx_pruned]
        msg = []
        if flag == "high_prune":
            msg.append("High proportion pruned (likely expression-only); rely on STRICT.")
        if note == "mechanistic_signal":
            msg.append("STRICT has binds/modifies — consider mechanistic follow-up.")
        if not msg and pruned > 0:
            msg.append("Some evidence pruned; prioritize non-expression edges.")
        comments.append(" ".join(msg) if msg else "—")
    cols_diff2 = cols_diff + ["comment"]
    rows_diff2 = [tuple(list(r)+[comments[i]]) for i,r in enumerate(rows_diff)]

    # Top pruned chemicals
    cols_chem, rows_chem = q(cur, open("scripts/sql/ctd_top_pruned_chemicals.sql","r").read())

    cur.close(); conn.close()

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S %Z")
    head = f"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>CTD report v3</title>
<style>
body {{ font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin:24px; }}
h1 {{ margin: 0 0 2px 0; }}
h2 {{ margin-top: 28px; }}
small {{ color:#555; }}
.tblwrap {{ overflow-x:auto; max-height: 60vh; border:1px solid #ddd; }}
table {{ border-collapse: collapse; width: 100%; font-size: 13px; }}
th, td {{ padding: 6px 8px; border-bottom: 1px solid #eee; vertical-align: top; }}
thead th {{ position: sticky; top: 0; background: #fff; border-bottom:1px solid #ccc; }}
tr:nth-child(even) td {{ background: #fafafa; }}
td.num {{ text-align: right; white-space: nowrap; }}
.kpi {{ display:flex; gap:20px; margin:10px 0 6px 0; }}
.card {{ border:1px solid #ddd; border-radius:8px; padding:10px 12px; }}
.note {{ color:#444; margin: 6px 0 10px 0; }}
legend {{ font-size:12px; color:#555; }}
footer {{ margin-top: 30px; font-size: 12px; color:#555; }}
</style>
</head>
<body>
<h1>CTD Action Taxonomy Report <small>(v3)</small></h1>
<div><small>Generated: {html.escape(now)}</small></div>

<div class="kpi">
  <div class="card"><b>Total CTD edges</b><br>{m['n_full_edges']}</div>
  <div class="card"><b>STRICT edges</b><br>{m['n_strict_edges']}</div>
  <div class="card"><b>Pruned edges</b><br>{m['n_pruned_edges']}</div>
  <div class="card"><b>Pruned %</b><br>{m['pruned_pct']}%</div>
</div>
<legend>
  STRICT = edges after removing generic “affects^...” patterns. Families: activates / inhibits / binds / modifies.
  “Pruned” means removed by STRICT. Focus on binds/modifies for mechanistic leads.
</legend>
"""
    body = []
    body.append(table_html("Family distribution (STRICT only)", cols_fam, rows_fam, note="Counts after STRICT pruning."))

    body.append(table_html("Full vs STRICT by gene (only genes with changes)",
                           cols_diff2, rows_diff2,
                           note="Flags high-prune genes and highlights presence of binds/modifies in STRICT.",
                           max_rows=200))

    body.append(table_html("Top chemicals by pruned edges",
                           cols_chem, rows_chem,
                           note="High pruned counts often reflect expression-only breadth; deprioritize for causal inference.",
                           max_rows=25))

    foot = """
<footer>
<b>Methods:</b> Action normalization via public.ctd_action_family; STRICT view excludes generic affects^expression / response chains.
Data sources: CTD chemicals & chem–gene edges already ingested. This document is auto-generated.
</footer>
</body></html>
"""
    html_out = head + "\n".join(body) + foot
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(html_out)
    print(f"[ok] Wrote {HTML}")

if __name__ == "__main__":
    main()
