#!/usr/bin/env python3
"""
Ingest HGNC Gene Families ("gene groups") from the HGNC complete set TSV.

Creates/uses:
  - public.gene_groups(group_id text PRIMARY KEY, name text)
  - public.gene_to_group(gene_symbol text NOT NULL, group_id text NOT NULL,
                         PRIMARY KEY(gene_symbol, group_id),
                         FK -> gene_groups(group_id), FK -> gene_catalog(gene_symbol) if present)
Input:
  --hgnc   Path to hgnc_complete_set.tsv
  --version  Source version string to stamp rows
  --upload-id Optional; used only for sample report path
"""

import os, csv, argparse, psycopg
from pathlib import Path
from adapters._ingest_utils import ensure_dir, write_csv_sample, chunked

DDL = """
CREATE TABLE IF NOT EXISTS public.gene_groups(
  group_id text PRIMARY KEY,
  name     text
);
CREATE TABLE IF NOT EXISTS public.gene_to_group(
  gene_symbol text NOT NULL,
  group_id    text NOT NULL REFERENCES public.gene_groups(group_id) ON DELETE CASCADE,
  PRIMARY KEY (gene_symbol, group_id)
);

-- helpful indexes
CREATE INDEX IF NOT EXISTS ix_gene_to_group_gene  ON public.gene_to_group(gene_symbol);
CREATE INDEX IF NOT EXISTS ix_gene_to_group_group ON public.gene_to_group(group_id);
"""

def parse_hgnc_groups(hgnc_path: str):
    """
    Yields (group_id, group_name, gene_symbol) triples.
    HGNC columns of interest:
      - gene_group        (pipe-separated names)
      - gene_group_id     (pipe-separated IDs, aligned with names)
      - symbol            (canonical HGNC gene symbol)
    """
    with open(hgnc_path, newline="", encoding="utf-8") as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            sym = (row.get("symbol") or "").strip()
            if not sym:
                continue
            ids = (row.get("gene_group_id") or "").strip()
            names = (row.get("gene_group") or "").strip()
            if not ids or not names:
                continue
            id_list = [x.strip() for x in ids.split("|") if x.strip()]
            name_list = [x.strip() for x in names.split("|") if x.strip()]
            # align pairs; HGNC guarantees same arity
            for gid, gname in zip(id_list, name_list):
                yield (gid, gname, sym)

def upsert_groups(cur, pairs):
    """Upsert unique group_id/name pairs."""
    # collect unique groups
    seen = {}
    for gid, gname, _ in pairs:
        if gid and gname and gid not in seen:
            seen[gid] = gname
    groups = [(gid, seen[gid]) for gid in seen.keys()]
    if not groups:
        return 0
    cur.executemany(
        """INSERT INTO public.gene_groups(group_id, name)
           VALUES (%s, %s)
           ON CONFLICT (group_id) DO UPDATE SET name = EXCLUDED.name""",
        groups
    )
    return len(groups)

def upsert_edges(cur, pairs, chunk=5000):
    """Insert (gene_symbol, group_id) edges."""
    # We’ll canonicalize by trusting your gene_catalog / identifiers already loaded.
    batch = []
    n = 0
    for gid, _gname, sym in pairs:
        if not gid or not sym:
            continue
        batch.append((sym, gid))
        if len(batch) >= chunk:
            cur.executemany(
                """INSERT INTO public.gene_to_group(gene_symbol, group_id)
                   VALUES (%s, %s)
                   ON CONFLICT DO NOTHING""",
                batch
            )
            n += len(batch)
            batch.clear()
    if batch:
        cur.executemany(
            """INSERT INTO public.gene_to_group(gene_symbol, group_id)
               VALUES (%s, %s)
               ON CONFLICT DO NOTHING""",
            batch
        )
        n += len(batch)
    return n

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hgnc", required=True, help="Path to hgnc_complete_set.tsv")
    ap.add_argument("--version", required=True, help="Source version string")
    ap.add_argument("--upload-id", type=int, default=0)
    ap.add_argument("--chunk", type=int, default=5000)
    args = ap.parse_args()

    # Build DSN from environment (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE)
    with psycopg.connect("") as conn:
        with conn.cursor() as cur:
            # best-effort DDL
            try:
                cur.execute(DDL)
            except Exception as e:
                print(f"[hgnc-groups] DDL skipped: {e}", flush=True)

        # parse once, then reuse results twice (groups, edges)
        triples = list(parse_hgnc_groups(args.hgnc))
        print(f"[hgnc-groups] parsed {len(triples)} (group_id, name, symbol) triples")

        with conn:
            with conn.cursor() as cur:
                n_groups = upsert_groups(cur, triples)
                n_edges  = upsert_edges(cur, triples, chunk=args.chunk)

        # sample CSV
        outdir = Path(f"reports/upload_{args.upload_id or 0}")
        ensure_dir(outdir)
        sample = [ {"group_id": gid, "name": name, "gene_symbol": sym}
                   for gid, name, sym in triples[:50] ]
        write_csv_sample(outdir / "hgnc_groups_sample.csv", header=["group_id","name","gene_symbol"], rows=sample)

        print(f"[hgnc-groups] DONE: groups={n_groups}, edges={n_edges}")
        print(f"[hgnc-groups] Sample CSV: reports/upload_{args.upload_id or 0}/hgnc_groups_sample.csv")

if __name__ == "__main__":
    main()
