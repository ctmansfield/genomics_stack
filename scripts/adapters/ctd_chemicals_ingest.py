#!/usr/bin/env python3
"""
CTD chemicals → public.chemicals

Reads CTD_chemicals.tsv[.gz] and upserts:
  chem_id (CTD ChemicalID, e.g., "MESH:D003634")
  name
  mesh_id (parsed from ChemicalID if present)
  cas_rn
Writes a small sample CSV to reports/upload_<id>/ctd_chemicals_sample.csv
"""

import os, sys, csv, gzip, argparse
from pathlib import Path
from typing import Iterable, Tuple
import psycopg

# Best-effort utilities (fall back if adapters._ingest_utils isn’t available)
def _ensure_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)

def _write_csv_sample(path: Path, header, rows: Iterable[Tuple], limit: int = 50):
    _ensure_dir(path.parent)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        for i, r in enumerate(rows):
            if i >= limit: break
            w.writerow(r)

try:
    from adapters._ingest_utils import ensure_dir as _ensure_dir
    from adapters._ingest_utils import write_csv_sample as _write_csv_sample
except Exception:
    pass

DDL = """
CREATE TABLE IF NOT EXISTS public.chemicals(
  chem_id  text PRIMARY KEY,
  name     text,
  mesh_id  text,
  cas_rn   text
);
CREATE INDEX IF NOT EXISTS ix_chem_mesh ON public.chemicals(mesh_id);
CREATE INDEX IF NOT EXISTS ix_chem_cas  ON public.chemicals(cas_rn);
"""

def mesh_from_chemical_id(cid: str) -> str | None:
    # CTD uses prefixes, e.g., MESH:D003634 or CHEBI:xxxx; we only fill mesh_id if MESH:
    if not cid: return None
    if cid.startswith("MESH:"):
        return cid.split(":", 1)[1]
    return None

def open_any(path: str):
    return gzip.open(path, "rt", encoding="utf-8", errors="replace") if path.endswith(".gz") \
           else open(path, "r", encoding="utf-8", errors="replace")

def iter_nocomment(f):
    for ln in f:
        if not ln.startswith('#') and ln.strip():
            yield ln

def parse_ctd_chemicals(path: str):
    with open_any(path) as f:
        r = csv.DictReader(iter_nocomment(f), delimiter='\t')
        for row in r:
            # Skip comment header lines if present
            if not row or row.get('ChemicalID','').startswith('#'):
                continue
            name = (row.get("ChemicalName") or "").strip()
            cid  = (row.get("ChemicalID")  or "").strip()
            cas  = (row.get("CasRN") or row.get("CAS RN") or row.get("CASRN") or row.get("CasRN ") or row.get("CasRN ")       or "").strip()
            if not cid or not name:
                continue
            yield (cid, name, mesh_from_chemical_id(cid), cas or None)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, help="CTD_chemicals.tsv[.gz]")
    ap.add_argument("--upload-id", type=int, required=False, default=0)
    ap.add_argument("--version", required=True)
    ap.add_argument("--chunk", type=int, default=5000)
    args = ap.parse_args()

    # Connect via PG* env or PGURL
    pgurl = os.environ.get("PGURL", "")
    conn = psycopg.connect(pgurl) if pgurl else psycopg.connect("")

    items = list(parse_ctd_chemicals(args.source))
    print(f"[chem] parsed {len(items):,} chemicals", flush=True)

    sample_path = Path(f"reports/upload_{args.upload_id}/ctd_chemicals_sample.csv") if args.upload_id is not None else None

    with conn:
        # Try to create table/indexes; proceed if not owner
        try:
            with conn.cursor() as cur:
                cur.execute(DDL)
        except Exception as e:
            print(f"[chem] DDL skipped ({e.__class__.__name__}: {e})", flush=True)

        # Upsert
        sql = """
        INSERT INTO public.chemicals (chem_id, name, mesh_id, cas_rn)
        VALUES (%s,%s,%s,%s)
        ON CONFLICT (chem_id) DO UPDATE
          SET name   = EXCLUDED.name,
              mesh_id= COALESCE(EXCLUDED.mesh_id, public.chemicals.mesh_id),
              cas_rn = COALESCE(EXCLUDED.cas_rn,  public.chemicals.cas_rn)
        """
        # chunked executemany
        with conn.cursor() as cur:
            for i in range(0, len(items), args.chunk):
                cur.executemany(sql, items[i:i+args.chunk])

    # Write sample
    if sample_path:
        _write_csv_sample(sample_path,
                          header=["chem_id","name","mesh_id","cas_rn"],
                          rows=items)

    print(f"[chem] DONE: upserted≈{len(items):,} rows", flush=True)

if __name__ == "__main__":
    main()
