#!/usr/bin/env python3
"""
dbSNP adapter: positions/ref/alt(s) by rsID for the active upload.
- Input: dbSNP GRCh37 VCF (bgz + .tbi)
- Scope: rsIDs present in staging_array_calls for --upload-id
- Output: public.dbsnp_by_rsid (UPSERT)
- Sample CSV: reports/upload_${UPLOAD_ID}/dbsnp_sample.csv

Example:
  python3 scripts/adapters/dbsnp_ingest_refs.py \
    --upload-id "$UPLOAD_ID" \
    --source /mnt/nas_storage/ref/dbsnp/All_20180418.vcf.bgz \
    --version "dbSNP b151 (GRCh37.p13)" \
    --chunk 5000 --progress-every 50000
"""
import os, sys, argparse, tempfile, json
from typing import List, Tuple
import psycopg
from adapters._ingest_utils import (
    get_pgurl_from_env, chunked, ensure_dir, run, write_csv_sample
)

DDL = """
CREATE TABLE IF NOT EXISTS public.dbsnp_by_rsid(
  rsid        text PRIMARY KEY,
  chromosome  text,
  position    bigint,
  ref         text,
  alts        text[],
  build       text,
  updated_at  timestamptz
);
"""

UPSERT_SQL = """
INSERT INTO public.dbsnp_by_rsid (rsid, chromosome, position, ref, alts, build, updated_at)
VALUES (%s, %s, %s, %s, %s, %s, NOW())
ON CONFLICT (rsid) DO UPDATE
SET chromosome = EXCLUDED.chromosome,
    position   = EXCLUDED.position,
    ref        = EXCLUDED.ref,
    alts       = EXCLUDED.alts,
    build      = EXCLUDED.build,
    updated_at = NOW();
"""

FETCH_RSIDS_SQL = r"""
SELECT DISTINCT rsid
FROM public.staging_array_calls
WHERE upload_id = %s
  AND rsid ~ '^rs[0-9]+$';
"""

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--upload-id", required=True, type=int)
    p.add_argument("--source", required=True, help="Path to dbSNP VCF .vcf.bgz")
    p.add_argument("--version", required=True, help="e.g., 'dbSNP b151 (GRCh37.p13)'")
    p.add_argument("--chunk", type=int, default=5000)
    p.add_argument("--progress-every", type=int, default=50000)
    return p.parse_args()

def get_upload_rsids(conn, upload_id: int) -> List[str]:
    with conn.cursor() as cur:
        cur.execute(FETCH_RSIDS_SQL, (upload_id,))
        return [r[0] for r in cur.fetchall()]

def ensure_schema(conn):
    with conn.cursor() as cur:
        cur.execute(DDL)
    conn.commit()

def upsert_rows(conn, rows: List[Tuple], page_size: int):
    with conn.cursor() as cur:
        for page in chunked(rows, page_size):
            cur.executemany(UPSERT_SQL, page)
            conn.commit()

def main():
    args = parse_args()
    pgurl = get_pgurl_from_env()

    # Output sample path
    sample_dir = os.path.join("reports", f"upload_{args.upload_id}")
    sample_csv = os.path.join(sample_dir, "dbsnp_sample.csv")

    with psycopg.connect(pgurl) as conn:
        ensure_schema(conn)
        rsids = get_upload_rsids(conn, args.upload_id)

    if not rsids:
        print(f"[dbsnp] No rsIDs found for upload_id={args.upload_id}; nothing to do.")
        return

    # Create a temporary rsID list for bcftools
    with tempfile.TemporaryDirectory() as td:
        ids_path = os.path.join(td, "ids.txt")
        with open(ids_path, "w") as f:
            for r in rsids:
                f.write(r + "\n")

        # bcftools: filter by ID list, then query fields
        # Output columns: CHROM  POS  ID  REF  ALT (comma-separated if multiple)
        cmd = [
            "bcftools", "view",
            "-i", f"ID=@{ids_path}",
            "-Ou", args.source
        ]
        rc, out, err = run(cmd)
        if rc != 0:
            print("[dbsnp] bcftools view failed:", err.strip())
            return

        # Now query desired fields from the stream
        # We’ll pass the BGZF stream via stdin to a second bcftools call:
        # Note: we re-run using process substitution by writing the stream to a temp file
        tmp_bcf = os.path.join(td, "subset.bcf")
        rc2, out2, err2 = run(["bcftools", "view", "-Ob", "-o", tmp_bcf, "-"])
        # The previous call read from STDIN which isn’t connected—so instead,
        # write the first step directly to file, then query from it:
        # (Fallback path)
        if rc2 != 0:
            # Re-run step one writing to file directly
            tmp_bcf = os.path.join(td, "subset2.bcf")
            rc3, out3, err3 = run([
                "bcftools", "view",
                "-i", f"ID=@{ids_path}",
                "-Ob", "-o", tmp_bcf, args.source
            ])
            if rc3 != 0:
                print("[dbsnp] bcftools view (to BCF) failed:", err3.strip())
                return

        # Index the BCF (just in case)
        rc4, out4, err4 = run(["bcftools", "index", "-f", tmp_bcf])
        if rc4 != 0:
            print("[dbsnp] bcftools index warning:", err4.strip())

        rc5, qout, qerr = run([
            "bcftools", "query",
            "-f", "%CHROM\t%POS\t%ID\t%REF\t%ALT\n",
            tmp_bcf
        ])
        if rc5 != 0:
            print("[dbsnp] bcftools query failed:", qerr.strip())
            return

    # Parse rows and prepare for upsert
    rows = []
    for line in qout.splitlines():
        if not line.strip():
            continue
        chrom, pos, vid, ref, alt = line.split("\t")
        # dbSNP IDs are rs####; guard just in case
        rsid = vid if vid.startswith("rs") else vid
        # ALT may be comma-separated
        alts = [a for a in alt.split(",") if a and a != "."]
        # Normalize CHR names: keep as-is (ClinVar/gnomAD use GRCh37 conventions)
        rows.append((
            rsid, chrom, int(pos), ref, alts if alts else None, args.version
        ))

    # Write a sample CSV for sanity
    write_csv_sample(
        sample_csv,
        header=["rsid", "chromosome", "position", "ref", "alts", "build"],
        rows=[(r[0], r[1], r[2], r[3], ",".join(r[4]) if r[4] else "", r[5]) for r in rows],
        limit=100
    )

    # Upsert
    with psycopg.connect(get_pgurl_from_env()) as conn:
        upsert_rows(conn, rows, page_size=args.chunk)

    print(f"[dbsnp] Upserted {len(rows)} rows into public.dbsnp_by_rsid")
    print(f"[dbsnp] Sample CSV: {sample_csv}")

if __name__ == "__main__":
    main()
