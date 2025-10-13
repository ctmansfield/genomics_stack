#!/usr/bin/env python3
"""
dbSNP adapter: positions/ref/alt(s) by rsID for the active upload.
- Input: dbSNP GRCh37 VCF (.vcf.gz + .tbi), e.g. /mnt/nas_storage/ref/dbsnp/All_20180423.vcf.gz
- Scope: rsIDs present in staging_array_calls for --upload-id
- Output: public.dbsnp_by_rsid (UPSERT)
- Sample CSV: reports/upload_${UPLOAD_ID}/dbsnp_sample.csv

Run:
  PYTHONUNBUFFERED=1 python3 scripts/adapters/dbsnp_ingest_refs.py \
    --upload-id "$UPLOAD_ID" \
    --source /mnt/nas_storage/ref/dbsnp/All_20180423.vcf.gz \
    --version "dbSNP b151 (GRCh37p13)" \
    --chunk 5000 --progress-every 50000
"""
import os, sys, csv, argparse, itertools, subprocess, tempfile
from typing import Iterable, List, Tuple
import psycopg

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

def chunked(iterable: Iterable, n: int):
    it = iter(iterable)
    while True:
        chunk = list(itertools.islice(it, n))
        if not chunk:
            break
        yield chunk

def get_pgurl() -> str:
    pgurl = os.environ.get("PGURL")
    if pgurl:
        return pgurl
    user = os.environ["PGUSER"]
    pwd  = os.environ["PGPASSWORD"]
    host = os.environ.get("PGHOST","localhost")
    port = os.environ.get("PGPORT","5432")
    db   = os.environ["PGDATABASE"]
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"

def run_text(cmd: List[str]):
    print(f"[run] {' '.join(cmd)}", flush=True)
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return p.returncode, p.stdout, p.stderr

def write_csv_sample(path: str, rows: List[Tuple]):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["rsid","chromosome","position","ref","alts","build"])
        for r in rows[:100]:
            rsid, chrom, pos, ref, alts, build = r
            w.writerow([rsid, chrom, pos, ref, ",".join(alts) if alts else "", build])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", required=True, type=int)
    ap.add_argument("--source", required=True, help="dbSNP VCF .vcf.gz")
    ap.add_argument("--version", required=True, help="e.g. 'dbSNP b151 (GRCh37p13)'")
    ap.add_argument("--chunk", type=int, default=5000)
    ap.add_argument("--progress-every", type=int, default=50000)
    args = ap.parse_args()

    # Ensure table and get rsIDs
    print("[dbsnp] connecting to DB…", flush=True)
    with psycopg.connect(get_pgurl()) as conn:
        with conn.cursor() as cur:
            cur.execute(DDL)
        conn.commit()
        print("[dbsnp] ensured table public.dbsnp_by_rsid", flush=True)

        with conn.cursor() as cur:
            cur.execute(FETCH_RSIDS_SQL, (args.upload_id,))
            rsids = [r[0] for r in cur.fetchall()]

    if not rsids:
        print(f"[dbsnp] No rsIDs found for upload_id={args.upload_id}; nothing to do.", flush=True)
        return

    print(f"[dbsnp] Found {len(rsids)} rsIDs for upload {args.upload_id}", flush=True)

    # Prepare ids list for bcftools
    with tempfile.TemporaryDirectory() as td:
        ids_path = os.path.join(td, "ids.txt")
        with open(ids_path, "w") as f:
            for r in rsids:
                f.write(r + "\n")

        # One-shot query filtered by ID set (TEXT output)
        cmd = [
            "bcftools", "query",
            "-i", f"ID=@{ids_path}",
            "-f", "%CHROM\t%POS\t%ID\t%REF\t%ALT\n",
            args.source
        ]
        rc, out, err = run_text(cmd)
        if rc != 0:
            print("[dbsnp] ERROR: bcftools query failed", flush=True)
            print(err.strip(), flush=True)
            sys.exit(2)

    # Parse output to rows
    rows: List[Tuple] = []
    for line in out.splitlines():
        if not line.strip():
            continue
        chrom, pos, vid, ref, alt = line.split("\t")
        rsid = vid if vid.startswith("rs") else vid
        alts = [a for a in alt.split(",") if a and a != "."]
        rows.append((rsid, chrom, int(pos), ref, alts if alts else None, args.version))

    print(f"[dbsnp] Parsed {len(rows)} dbSNP records", flush=True)

    # Sample CSV
    sample_csv = os.path.join("reports", f"upload_{args.upload_id}", "dbsnp_sample.csv")
    write_csv_sample(sample_csv, rows)
    print(f"[dbsnp] Wrote sample CSV: {sample_csv}", flush=True)

    # UPSERT in chunks
    total = 0
    with psycopg.connect(get_pgurl()) as conn:
        with conn.cursor() as cur:
            for page in chunked(rows, args.chunk):
                cur.executemany(UPSERT_SQL, page)
                conn.commit()
                total += len(page)
                if total % max(args.progress_every, 1) == 0:
                    print(f"[dbsnp] upserted {total}…", flush=True)

    print(f"[dbsnp] DONE. Upserted {total} rows into public.dbsnp_by_rsid", flush=True)

if __name__ == "__main__":
    main()
