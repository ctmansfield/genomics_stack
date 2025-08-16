#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import sys

import psycopg2


def env(k: str, default: str | None = None) -> str | None:
    v = os.environ.get(k, default)
    if v is None:
        print(f"Missing env {k}", file=sys.stderr)
    return v


def resolve_file_id(cur, candidate: str) -> str:
    cur.execute("SELECT to_regclass('public.ingest_registry') IS NOT NULL")
    if not bool(cur.fetchone()[0]):
        return candidate
    cur.execute(
        """
        WITH x AS (
          SELECT file_id::text, filename, uploaded_at
          FROM ingest_registry
          WHERE file_id::text=%s OR filename=%s
          ORDER BY uploaded_at DESC LIMIT 1
        )
        SELECT COALESCE((SELECT file_id FROM x), %s)
        """,
        (candidate, candidate, candidate),
    )
    return cur.fetchone()[0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file-id", required=True)
    args = ap.parse_args()

    dsn = env("PG_DSN")
    if not dsn:
        print("PG_DSN not set", file=sys.stderr)
        sys.exit(2)
    import_table = env("IMPORT_TABLE", "variants")
    import_id_col = env("IMPORT_ID_COL", "file_id")
    vep_table = env("VEP_TABLE", "vep_annotations")
    vep_id_col = env("VEP_ID_COL", "file_id")
    join_key = env("JOIN_KEY", "variant_id")
    out_dir = env("REPORT_OUT", "./risk_reports/out") or "./risk_reports/out"
    os.makedirs(out_dir, exist_ok=True)

    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        file_id = resolve_file_id(cur, args.file_id)
        sql = f"""
        SELECT i.{import_id_col} AS file_id, i.{join_key} AS variant_id, i.*,
               v.gene, v.consequence, v.priority_score
        FROM {import_table} i
        LEFT JOIN {vep_table} v
          ON v.{vep_id_col} = i.{import_id_col} AND v.variant_id = i.{join_key}
        WHERE i.{import_id_col} = %s
        ORDER BY v.priority_score DESC NULLS LAST, i.{join_key}
        """
        cur.execute(sql, (file_id,))
        cols = [d.name for d in cur.description]
        rows = cur.fetchall()

    out_path = os.path.join(out_dir, f"full_report_{file_id}.csv")
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(rows)
    print(f"Wrote {out_path} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
