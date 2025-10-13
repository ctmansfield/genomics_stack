#!/usr/bin/env python3
"""
Ingest CTD chemical↔gene interactions (open, drug-like coverage).

Source: CTD_chem_gene_ixns.tsv.gz
Docs:   http://ctdbase.org/downloads/

Creates:
  public.chemicals(chem_id TEXT PK, name TEXT, mesh_id TEXT, cas_rn TEXT)
  public.gene_to_chemical(
      id BIGSERIAL PK,
      gene_symbol TEXT NOT NULL REFERENCES public.gene_catalog(gene_symbol),
      chem_id     TEXT NOT NULL REFERENCES public.chemicals(chem_id) ON DELETE CASCADE,
      action      TEXT,           -- e.g., "increases expression"
      direct     BOOLEAN,         -- CTD "DirectEvidence" == 'marker/mechanism' → false; 'therapeutic' → true-ish? we keep boolean as present/absent
      refs_count  INT,
      source      TEXT DEFAULT 'CTD',
      updated_at  TIMESTAMPTZ DEFAULT now(),
      UNIQUE (gene_symbol, chem_id, action)  -- dedupe per action
  )

Outputs sample:
  reports/upload_<UPLOAD_ID>/ctd_chem_gene_sample.csv
"""

import os, sys, csv, argparse, gzip, io, time
import psycopg

from adapters._ingest_utils import ensure_dir, write_csv_sample, chunked

DDL = """
CREATE TABLE IF NOT EXISTS public.chemicals(
  chem_id  text PRIMARY KEY,          -- CTD ChemicalID (e.g., MESH:D003634)
  name     text,
  mesh_id  text,
  cas_rn   text
);

CREATE TABLE IF NOT EXISTS public.gene_to_chemical(
  id           bigserial PRIMARY KEY,
  gene_symbol  text NOT NULL REFERENCES public.gene_catalog(gene_symbol),
  chem_id      text NOT NULL REFERENCES public.chemicals(chem_id) ON DELETE CASCADE,
  action       text,
  direct       boolean,
  refs_count   integer,
  source       text DEFAULT 'CTD',
  updated_at   timestamptz DEFAULT now(),
  UNIQUE (gene_symbol, chem_id, action)
);

CREATE INDEX IF NOT EXISTS ix_gene_to_chem_gene ON public.gene_to_chemical(gene_symbol);
CREATE INDEX IF NOT EXISTS ix_gene_to_chem_chem ON public.gene_to_chemical(chem_id);
"""

def parse_ctd_rows(path):
    """
    Yields dicts from CTD_chem_gene_ixns.tsv(.gz).
    Header columns (abbrev):
      ChemicalName, ChemicalID, CasRN,
      GeneSymbol, GeneID, GeneForms,
      Organism, OrganismID,
      Interaction, InteractionActions, InteractionID,
      PubMedIDs, DirectEvidence, InferenceNetwork
    """
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as f:
        r = csv.DictReader((row for row in f if not row.startswith("#")), delimiter="\t")
        for row in r:
            yield row

def canonical(cur, sym: str) -> str:
    cur.execute("SELECT public.canonical_gene_symbol(%s)", (sym,))
    return cur.fetchone()[0]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", type=int, required=True)
    ap.add_argument("--source", required=True, help="Path to CTD_chem_gene_ixns.tsv[.gz]")
    ap.add_argument("--version", required=True)
    ap.add_argument("--chunk", type=int, default=5000)
    ap.add_argument("--progress-every", type=int, default=50000)
    args = ap.parse_args()

    # connect using PG* envs
    conn = psycopg.connect("")

    from pathlib import Path
    outdir = Path(f"reports/upload_{args.upload_id}"); outdir.mkdir(parents=True, exist_ok=True)
    t0 = time.time()

    with conn:
        # best-effort DDL
        try:
            with conn.cursor() as cur:
                cur.execute(DDL)
        except Exception as e:
            print(f"[ctd] DDL skipped ({e})", flush=True)

        with conn.cursor() as cur:
            rows_chem = []
            rows_edge = []
            sample = []

            n = 0
            for row in parse_ctd_rows(args.source):
                n += 1
                chem_id = (row.get("ChemicalID") or "").strip()
                chem_name = (row.get("ChemicalName") or "").strip()
                cas = (row.get("CasRN") or "").strip()

                gene_sym_raw = (row.get("GeneSymbol") or "").strip()
                if not chem_id or not gene_sym_raw:
                    continue

                # normalize symbol once
                sym = canonical(cur, gene_sym_raw)

                action = (row.get("InteractionActions") or row.get("Interaction") or "").strip()
                direct = True if (row.get("DirectEvidence") or "").strip() else False
                pmids = (row.get("PubMedIDs") or "").strip()
                refs_count = 0
                if pmids:
                    # pmids are '12345|67890'
                    refs_count = len([x for x in pmids.replace(",", "|").split("|") if x.strip().isdigit()])

                # upsert chemical
                rows_chem.append((chem_id, chem_name, chem_id.split(":")[1] if ":" in chem_id else None, cas))
                # upsert edge
                rows_edge.append((sym, chem_id, action if action else None, direct, refs_count))

                if len(sample) < 20:
                    sample.append((sym, chem_id, chem_name, action, refs_count))

                if n % args.chunk == 0:
                    # flush
                    cur.executemany("""
                        INSERT INTO public.chemicals(chem_id, name, mesh_id, cas_rn)
                        VALUES (%s,%s,%s,%s)
                        ON CONFLICT (chem_id) DO UPDATE
                        SET name=EXCLUDED.name, mesh_id=EXCLUDED.mesh_id, cas_rn=EXCLUDED.cas_rn
                    """, rows_chem)
                    rows_chem.clear()

                    cur.executemany("""
                        INSERT INTO public.gene_to_chemical(gene_symbol, chem_id, action, direct, refs_count, source, updated_at)
                        VALUES (%s,%s,%s,%s,%s,'CTD', now())
                        ON CONFLICT (gene_symbol, chem_id, action) DO UPDATE
                        SET direct=EXCLUDED.direct,
                            refs_count=GREATEST(public.gene_to_chemical.refs_count, EXCLUDED.refs_count),
                            updated_at=now()
                    """, rows_edge)
                    rows_edge.clear()

                    if n % args.progress_every == 0:
                        print(f"[ctd] processed {n:,} rows…", flush=True)

            # final flush
            if rows_chem:
                cur.executemany("""
                    INSERT INTO public.chemicals(chem_id, name, mesh_id, cas_rn)
                    VALUES (%s,%s,%s,%s)
                    ON CONFLICT (chem_id) DO UPDATE
                    SET name=EXCLUDED.name, mesh_id=EXCLUDED.mesh_id, cas_rn=EXCLUDED.cas_rn
                """, rows_chem)

            if rows_edge:
                cur.executemany("""
                    INSERT INTO public.gene_to_chemical(gene_symbol, chem_id, action, direct, refs_count, source, updated_at)
                    VALUES (%s,%s,%s,%s,%s,'CTD', now())
                    ON CONFLICT (gene_symbol, chem_id, action) DO UPDATE
                    SET direct=EXCLUDED.direct,
                        refs_count=GREATEST(public.gene_to_chemical.refs_count, EXCLUDED.refs_count),
                        updated_at=now()
                """, rows_edge)

            # sample file
            write_csv_sample(
                outdir / "ctd_chem_gene_sample.csv",
                header=["gene_symbol","chem_id","chemical_name","action","refs_count"],
                rows=sample
            )

    dt = time.time() - t0
    print(f"[ctd] DONE: processed≈{n:,} rows in {dt:.1f}s", flush=True)

if __name__ == "__main__":
    main()
