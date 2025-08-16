#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import sys

import psycopg2


def env(key: str, default: str | None = None) -> str | None:
    value = os.environ.get(key, default)
    if value is None:
        print(f"Missing env {key}", file=sys.stderr)
    return value


def resolve_file_id(cur, candidate: str) -> str:
    cur.execute("SELECT to_regclass('public.ingest_registry') IS NOT NULL")
    has_registry = cur.fetchone()[0]
    if not has_registry:
        return candidate
    cur.execute(
        """
        WITH x AS (
          SELECT file_id::text, filename, uploaded_at
          FROM ingest_registry
          WHERE file_id::text = %s OR filename = %s
          ORDER BY uploaded_at DESC
          LIMIT 1
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
    score_col = env("SCORE_COLUMN", "priority_score")
    out_dir = env("REPORT_OUT", "/root/genomics-stack/risk_reports/out") or "."
    os.makedirs(out_dir, exist_ok=True)

    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        file_id = resolve_file_id(cur, args.file_id)
        sql = f"""
            SELECT i.{join_key} AS variant_id, i.*, v.*
            FROM {import_table} AS i
            LEFT JOIN {vep_table} AS v
              ON v.{join_key} = i.{join_key}
             AND v.{vep_id_col} = i.{import_id_col}
            WHERE i.{import_id_col} = %s
            ORDER BY COALESCE(i.{score_col}, v.{score_col}) DESC NULLS LAST
            LIMIT 10
        """
        cur.execute(sql, (file_id,))
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()

    out_path = os.path.join(out_dir, f"top10_{file_id}.csv")
    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(cols)
        writer.writerows(rows)
    print(f"Wrote {out_path} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
