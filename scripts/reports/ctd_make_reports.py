#!/usr/bin/env python3
"""
Generate CTD PDF reports from Postgres using the new strict/pruned views.

Usage:
  python3 ctd_make_reports.py --out ctd_report.pdf --sentinels TP53 APOE PCSK9

Relies on environment variables: PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD
Requires: psycopg2-binary, pandas, matplotlib
"""

import os
import argparse
from datetime import datetime

import pandas as pd
import psycopg2
import psycopg2.extras as p2extras
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

def pg_connect():
    dsn = dict(
        host=os.environ.get("PGHOST", "localhost"),
        port=int(os.environ.get("PGPORT", "5432")),
        user=os.environ.get("PGUSER", "genouser"),
        password=os.environ.get("PGPASSWORD", ""),
        dbname=os.environ.get("PGDATABASE", "genome_db"),
    )
    return psycopg2.connect(**dsn)

def df_query(conn, sql, params=None):
    with conn.cursor(cursor_factory=p2extras.RealDictCursor) as cur:
        cur.execute(sql, params or ())
        rows = cur.fetchall()
    if not rows:
        return pd.DataFrame()
    return pd.DataFrame(rows)

def fig_title(ax, title):
    ax.set_title(title, pad=16, fontsize=14, fontweight="bold")

def render_table_pdf(pdf, df, title, note=None, max_rows=40):
    if df.empty:
        return
    df_to_show = df.head(max_rows).copy()
    fig, ax = plt.subplots(figsize=(11, 8.5))
    ax.axis("off")
    ax.set_title(title, pad=16, fontsize=14, fontweight="bold")
    tbl = ax.table(cellText=df_to_show.values,
                   colLabels=list(df_to_show.columns),
                   loc="center")
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(8)
    tbl.scale(1, 1.3)
    if note:
        ax.text(0.01, 0.02, note, transform=ax.transAxes, fontsize=8)
    pdf.savefig(fig, bbox_inches="tight")
    plt.close(fig)

def render_bar_pdf(pdf, df, xcol, ycol, title, xlabel=None, ylabel=None, rotation=0):
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(11, 8.5))
    ax.bar(df[xcol].astype(str), df[ycol].values)
    ax.set_xlabel(xlabel or xcol)
    ax.set_ylabel(ylabel or ycol)
    ax.tick_params(axis="x", labelrotation=rotation)
    ax.set_title(title, pad=16, fontsize=14, fontweight="bold")
    pdf.savefig(fig, bbox_inches="tight")
    plt.close(fig)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=f"ctd_report_{datetime.now().strftime('%Y%m%d_%H%M')}.pdf",
                    help="Output PDF path")
    ap.add_argument("--sentinels", nargs="*", default=["TP53", "APOE", "PCSK9"],
                    help="Gene symbols for deep-dive")
    args = ap.parse_args()

    with pg_connect() as conn, PdfPages(args.out) as pdf:
        meta = {
            "Generated at": datetime.now().isoformat(timespec="seconds"),
            "DB": os.environ.get("PGDATABASE", "genome_db"),
            "Host": os.environ.get("PGHOST", "localhost"),
            "Strict view": "public.v_ctd_enriched_strict_v2 (WHERE is_strict)",
            "Pruned edges view": "public.v_ctd_edges_pruned_v2 / _with_names",
            "Pruned rollups": "public.v_ctd_pruned_by_gene, public.v_ctd_pruned_by_chemical",
        }
        df_meta = pd.DataFrame([meta])
        render_table_pdf(pdf, df_meta, "CTD Report — Metadata")

        q1 = """
        SELECT action_family, COUNT(*) AS n_edges
        FROM public.v_ctd_enriched_strict_v2
        WHERE is_strict
        GROUP BY 1
        ORDER BY n_edges DESC
        """
        df1 = df_query(conn, q1)
        render_bar_pdf(pdf, df1, "action_family", "n_edges",
                       "CTD (STRICT): Edge counts by action_family")

        q2 = """
        SELECT gene_symbol, n_pruned
        FROM public.v_ctd_pruned_by_gene
        ORDER BY n_pruned DESC, gene_symbol
        LIMIT 50
        """
        df2 = df_query(conn, q2)
        render_table_pdf(pdf, df2, "Top 50 Genes by Pruned Edge Count (expression/response filtered)")

        q3 = """
        SELECT
          p.chem_id,
          COALESCE(c.name, c.mesh_id) AS chem_name,
          p.n_pruned
        FROM public.v_ctd_pruned_by_chemical p
        LEFT JOIN public.chemicals c ON c.chem_id = p.chem_id
        ORDER BY p.n_pruned DESC, p.chem_id
        LIMIT 50
        """
        df3 = df_query(conn, q3)
        render_table_pdf(pdf, df3, "Top 50 Chemicals by Pruned Edge Count")

        q4 = """
        SELECT gene_symbol, chem_id,
               (SELECT COALESCE(c.name, c.mesh_id) FROM public.chemicals c WHERE c.chem_id = e.chem_id) AS chem_name,
               action_norm, action_family
        FROM public.v_ctd_edges_pruned_v2 e
        ORDER BY gene_symbol, chem_id
        LIMIT 200
        """
        df4 = df_query(conn, q4)
        render_table_pdf(pdf, df4, "Sample of Pruned Edges (first 200)")

        q5 = """
        WITH cte_full AS (
          SELECT gene_symbol, action_family, COUNT(*) AS n
          FROM public.v_gene_to_chemical_enriched
          GROUP BY 1,2
        ),
        cte_strict AS (
          SELECT gene_symbol, action_family, COUNT(*) AS n
          FROM public.v_ctd_enriched_strict_v2
          WHERE is_strict
          GROUP BY 1,2
        )
        SELECT
          COALESCE(f.gene_symbol, s.gene_symbol) AS gene_symbol,
          COALESCE(f.action_family, s.action_family) AS action_family,
          f.n AS n_full,
          s.n AS n_strict,
          COALESCE(f.n,0) - COALESCE(s.n,0) AS pruned
        FROM cte_full f
        FULL OUTER JOIN cte_strict s
          ON f.gene_symbol = s.gene_symbol AND f.action_family = s.action_family
        ORDER BY gene_symbol, action_family
        LIMIT 300
        """
        df5 = df_query(conn, q5)
        render_table_pdf(pdf, df5, "Full vs STRICT by Gene (first 300 rows)")

        q6a = """
        SELECT gene_symbol, action_family, COUNT(*) AS n_edges
        FROM public.v_ctd_enriched_strict_v2
        WHERE is_strict AND gene_symbol = ANY(%s)
        GROUP BY 1,2
        ORDER BY gene_symbol, action_family
        """
        df6a = df_query(conn, q6a, (args.sentinels,))
        if not df6a.empty:
            for gene in df6a["gene_symbol"].unique():
                dfg = df6a[df6a["gene_symbol"] == gene][["action_family", "n_edges"]]
                render_bar_pdf(pdf, dfg, "action_family", "n_edges",
                               f"STRICT families for {gene}", xlabel="action_family",
                               ylabel="edges", rotation=0)

        q6b = """
        WITH strict AS (
          SELECT gene_symbol, chem_id, action_norm,
                 public.ctd_action_family(action_norm) AS action_family
          FROM public.v_ctd_enriched_strict_v2
          WHERE is_strict AND gene_symbol = ANY(%s)
        ),
        roll AS (
          SELECT gene_symbol, action_family, COUNT(*) AS n_edges
          FROM strict GROUP BY 1,2
        )
        SELECT r.gene_symbol, r.action_family, r.n_edges,
               s.chem_id,
               (SELECT COALESCE(c.name, c.mesh_id) FROM public.chemicals c WHERE c.chem_id = s.chem_id) AS chem_name,
               s.action_norm
        FROM roll r
        LEFT JOIN strict s ON s.gene_symbol = r.gene_symbol AND s.action_family = r.action_family
        ORDER BY r.gene_symbol, r.action_family, chem_name NULLS LAST
        LIMIT 300
        """
        df6b = df_query(conn, q6b, (args.sentinels,))
        render_table_pdf(pdf, df6b, f"STRICT detail for sentinels ({', '.join(args.sentinels)})", max_rows=300)

        fig, ax = plt.subplots(figsize=(11, 8.5))
        ax.axis("off")
        ax.text(0.02, 0.5, "CTD PDF generated successfully.", fontsize=14)
        pdf.savefig(fig, bbox_inches="tight")
        plt.close(fig)

if __name__ == "__main__":
    main()
