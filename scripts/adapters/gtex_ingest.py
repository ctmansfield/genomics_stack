#!/usr/bin/env python3
"""
Ingest GTEx v8 median TPM per tissue.

TARGET TABLE:
  CREATE TABLE IF NOT EXISTS public.gtex_expression(
    gene_symbol   text,
    tissue        text,
    median_tpm    double precision,
    source_version text,
    updated_at    timestamptz,
    PRIMARY KEY (gene_symbol, tissue)
  );

INPUT:
  GTEx v8 file like: Median_TPM.gct (2 header lines, then columns per tissue).
  Official GTEx v8: rows = Ensembl gene IDs (with version), first column "Name", second "Description".
  We'll map Ensembl→canonical gene_symbol via public.gene_identifiers.

CLI:
  python3 scripts/adapters/gtex_ingest.py \
    --upload-id 2 \
    --source /mnt/nas_storage/ref/gtex/GTEx_Analysis_2017-06-05_v8_RNASeQCv1.1.9_gene_median_tpm.gct \
    --version "GTEx v8" \
    --chunk 5000 --progress-every 50000
"""
import os, sys, csv, argparse, time
import psycopg
from adapters._ingest_utils import ensure_dir, write_csv_sample, chunked

def get_pgurl_from_env():
    # Empty DSN => use PG* envs (psycopg supports that)
    return os.environ.get("PGURL","")

DDL = """
CREATE TABLE IF NOT EXISTS public.gtex_expression(
  gene_symbol   text,
  tissue        text,
  median_tpm    double precision,
  source_version text,
  updated_at    timestamptz,
  PRIMARY KEY (gene_symbol, tissue)
);
"""

def load_gct(path):
    with open(path, newline='') as f:
        # GCT v1.2: first two header lines, then tab header with "Name", "Description", tissue cols
        first = f.readline()
        second = f.readline()
        header = f.readline().rstrip("\n").split("\t")
        assert header[0].lower() == "name" and header[1].lower() == "description", "Unexpected GCT header."
        tissues = header[2:]
        for line in f:
            parts = line.rstrip("\n").split("\t")
            ensg = parts[0]  # e.g., ENSG00000121410.12
            desc = parts[1]
            vals = parts[2:]
            yield ensg, tissues, vals

def ensg_strip_version(ensg):
    return ensg.split(".")[0]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", required=True, type=int)
    ap.add_argument("--source", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--chunk", type=int, default=5000)
    ap.add_argument("--progress-every", type=int, default=50000)
    args = ap.parse_args()

    outdir = f"reports/upload_{args.upload_id}"
    ensure_dir(outdir)

    pgurl = get_pgurl_from_env()
    with psycopg.connect(pgurl) as conn:
        conn.execute("SET application_name TO 'gtex_ingest'")
        with conn.cursor() as cur:
            # best-effort DDL
            try:
                cur.execute(DDL)
            except Exception as e:
                print(f"[gtex] DDL skipped: {e}", flush=True)

        # Build Ensembl→symbol map
        print("[gtex] building Ensembl→symbol map…", flush=True)
        ensg2sym = {}
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT ensembl_gene_id, gene_symbol FROM public.gene_identifiers WHERE ensembl_gene_id IS NOT NULL")
            for ensg, sym in cur:
                ensg2sym[ensg] = sym

        # Parse source and emit rows
        rows = []
        sample = []
        t0 = time.time()
        n_rows = n_emitted = 0
        for ensg, tissues, vals in load_gct(args.source):
            base = ensg_strip_version(ensg)
            sym = ensg2sym.get(base)
            if not sym:
                continue
            for tissue, v in zip(tissues, vals):
                try:
                    tpm = float(v)
                except Exception:
                    continue
                rows.append((sym, tissue, tpm, args.version))
                n_emitted += 1
                if len(sample) < 10:
                    sample.append((sym, tissue, tpm))
            n_rows += 1
            if n_rows % args.progress_every == 0:
                print(f"[gtex] parsed {n_rows} genes…", flush=True)

        # Upsert in chunks
        def upsert(chunk):
            with conn.cursor() as cur:
                cur.executemany(
                    """
                    INSERT INTO public.gtex_expression(gene_symbol, tissue, median_tpm, source_version, updated_at)
                    VALUES (%s,%s,%s,%s, now())
                    ON CONFLICT (gene_symbol, tissue) DO UPDATE
                      SET median_tpm=EXCLUDED.median_tpm,
                          source_version=EXCLUDED.source_version,
                          updated_at=now()
                    """,
                    chunk
                )

        print(f"[gtex] upserting {len(rows)} rows…", flush=True)
        for page in chunked(rows, args.chunk):
            upsert(page)
            conn.commit()

        write_csv_sample(outdir + "/gtex_expression_sample.csv",
                         ["gene_symbol","tissue","median_tpm"], sample)
        dt = time.time() - t0
        print(f"[gtex] DONE: genes={n_rows}, values={n_emitted}, elapsed={dt:.1f}s", flush=True)

if __name__ == "__main__":
    main()
