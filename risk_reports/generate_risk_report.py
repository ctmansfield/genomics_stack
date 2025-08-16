#!/usr/bin/env python3
import argparse
import os
from datetime import datetime

import pandas as pd
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

try:
    import psycopg2
except Exception:
    psycopg2 = None


def load_model_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    df["rsid"] = df["rsid"].astype(str)
    df["effect_allele"] = df["effect_allele"].astype(str)
    df["weight"] = pd.to_numeric(df["weight"], errors="coerce").fillna(0.0)
    return df


def load_genotypes_csv(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    df["rsid"] = df["rsid"].astype(str)
    df["dosage"] = pd.to_numeric(df["dosage"], errors="coerce").fillna(0.0).clip(0, 2)
    return df


def fetch_genotypes_from_db(sample_id: str, sql: str | None):
    if psycopg2 is None:
        raise RuntimeError("psycopg2-binary not installed; use --genotypes-csv or install deps.")
    dsn = dict(
        host=os.getenv("PGHOST"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE"),
        user=os.getenv("PGUSER"),
        password=os.getenv("PGPASSWORD"),
    )
    missing = [k for k, v in dsn.items() if not v]
    if missing:
        raise RuntimeError(f"Missing DB env vars: {missing}")
    default_sql = "SELECT rsid, dosage FROM genotypes WHERE sample_id = %(sample_id)s"
    query = sql or default_sql
    with psycopg2.connect(**dsn) as conn, conn.cursor() as cur:
        cur.execute(query, {"sample_id": sample_id})
        rows = cur.fetchall()
    df = pd.DataFrame(rows, columns=["rsid", "dosage"]).dropna()
    df["rsid"] = df["rsid"].astype(str)
    df["dosage"] = pd.to_numeric(df["dosage"], errors="coerce").fillna(0.0).clip(0, 2)
    return df


def compute_scores(model: pd.DataFrame, genos: pd.DataFrame):
    merged = model.merge(genos, on="rsid", how="left")
    merged["dosage"] = merged["dosage"].fillna(0.0).clip(0, 2)
    merged["contrib"] = merged["weight"] * merged["dosage"]
    raw = float(merged["contrib"].sum())
    denom = float((2.0 * merged["weight"].abs()).sum())
    norm = raw / denom if denom > 0 else 0.0
    norm = max(min(norm, 1.0), -1.0)
    covered = merged["dosage"].notna().sum()
    total = len(merged)
    coverage = round(100.0 * covered / total, 2) if total > 0 else 0.0
    top = merged.copy()
    top["abs_contrib"] = top["contrib"].abs()
    top = top.sort_values("abs_contrib", ascending=False).head(10)[
        ["rsid", "weight", "dosage", "contrib"]
    ]
    return dict(
        raw_score=raw,
        normalized_score=norm,
        coverage_pct=coverage,
        top_contributors=top,
        merged=merged,
    )


def band(norm: float):
    if norm <= -0.33:
        return "Lower-than-average"
    if norm < 0.33:
        return "Average"
    return "Higher-than-average"


def draw_gauge(c, x, y, w, h, normalized: float):
    zone_w = w / 3.0

    c.setFillColor(colors.HexColor("#d9ead3"))
    c.rect(x, y, zone_w, h, stroke=0, fill=1)
    c.setFillColor(colors.HexColor("#fff2cc"))
    c.rect(x + zone_w, y, zone_w, h, stroke=0, fill=1)
    c.setFillColor(colors.HexColor("#f4cccc"))
    c.rect(x + 2 * zone_w, y, zone_w, h, stroke=0, fill=1)
    c.setStrokeColor(colors.black)
    c.rect(x, y, w, h, stroke=1, fill=0)
    px = x + (normalized + 1.0) / 2.0 * w
    c.setStrokeColor(colors.black)
    c.line(px, y, px, y + h)
    for frac in [0.0, 0.5, 1.0]:
        tx = x + frac * w
        c.line(tx, y, tx, y + 5)
    c.setFont("Helvetica", 8)
    c.drawString(x - 5, y + h + 3, "-1")
    c.drawString(x + w / 2 - 3, y + h + 3, "0")
    c.drawString(x + w - 3, y + h + 3, "1")


def render_pdf(out_path, sample_id, phenotype_name, scores):
    c = canvas.Canvas(out_path, pagesize=A4)
    W, H = A4
    m = 20 * mm
    c.setFont("Helvetica-Bold", 18)
    c.drawString(m, H - m, "Genetic Risk Report (Research Use Only)")
    c.setFont("Helvetica", 10)
    c.drawString(m, H - m - 14, f"Sample ID: {sample_id}")
    c.drawString(m, H - m - 28, f"Phenotype: {phenotype_name or 'N/A'}")
    c.drawString(m, H - m - 42, f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    c.setFont("Helvetica-Bold", 14)
    c.drawString(m, H - m - 70, "Summary")
    norm = scores["normalized_score"]
    band_lbl = band(norm)
    c.setFont("Helvetica", 11)
    c.drawString(m, H - m - 90, f"Normalized Score: {norm:.3f}  |  Band: {band_lbl}")
    c.drawString(m, H - m - 105, f"Model coverage: {scores['coverage_pct']}%")
    gx, gy = m, H - m - 135
    draw_gauge(c, gx, gy, 120 * mm, 10 * mm, norm)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(m, gy - 20, "Top Variant Contributors")
    c.setFont("Helvetica", 10)
    cols = ["RSID", "Weight", "Dosage", "Contribution"]
    col_w = [40 * mm, 30 * mm, 30 * mm, 40 * mm]
    x0 = m
    y0 = gy - 35
    for i, col in enumerate(cols):
        c.drawString(x0 + sum(col_w[:i]) + 2, y0, col)
    y = y0 - 12
    for _, row in scores["top_contributors"].iterrows():
        vals = [
            str(row["rsid"]),
            f"{row['weight']:.3f}",
            f"{row['dosage']:.2f}",
            f"{row['contrib']:.3f}",
        ]
        for i, v in enumerate(vals):
            c.drawString(x0 + sum(col_w[:i]) + 2, y, v)
        y -= 12
        if y < 60 * mm:
            break
    c.setFont("Helvetica-Oblique", 8)
    c.drawString(m, 20 * mm, "DISCLAIMER: Research use only; not for clinical decision-making.")
    c.showPage()
    c.save()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample-id", required=True)
    ap.add_argument("--phenotype-name", default="")
    ap.add_argument("--model-csv", required=True)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--genotypes-csv")
    src.add_argument("--sql")
    ap.add_argument("--out-pdf", required=True)
    args = ap.parse_args()
    model = load_model_csv(args.model_csv)
    if args.genotypes_csv:
        genos = load_genotypes_csv(args.genotypes_csv)
    else:
        genos = fetch_genotypes_from_db(args.sample_id, args.sql)
    scores = compute_scores(model, genos)
    os.makedirs(os.path.dirname(args.out_pdf) or ".", exist_ok=True)
    render_pdf(args.out_pdf, args.sample_id, args.phenotype_name, scores)
    print(f"Wrote PDF: {args.out_pdf}")


if __name__ == "__main__":
    main()
