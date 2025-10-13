#!/usr/bin/env python3
"""
HGNC/Ensembl/UniProt adapter → public.gene_identifiers
- Prefer HGNC approved_symbol as canonical gene_symbol
- Store aliases (synonyms, previous symbols, Ensembl/UniProt crossrefs when needed)
- Join strategy:
    * Seed from HGNC complete set (TSV)
    * Left-join Ensembl and UniProt maps on symbol or HGNC ID where available
- Upsert per symbol
- Sample CSV: reports/upload_${UPLOAD_ID}/gene_identifiers_sample.csv
"""
import os, csv, argparse
from typing import Dict, Set, List, Tuple
import psycopg
from adapters._ingest_utils import get_pgurl_from_env, ensure_dir, write_csv_sample, chunked

DDL = """
CREATE TABLE IF NOT EXISTS public.gene_identifiers(
  gene_symbol      text PRIMARY KEY,
  hgnc_id          text,
  ensembl_gene_id  text,
  uniprot_id       text,
  aliases          text[],
  updated_at       timestamptz
);
"""

UPSERT = """
INSERT INTO public.gene_identifiers
(gene_symbol, hgnc_id, ensembl_gene_id, uniprot_id, aliases, updated_at)
VALUES (%s, %s, %s, %s, %s, NOW())
ON CONFLICT (gene_symbol) DO UPDATE SET
  hgnc_id = EXCLUDED.hgnc_id,
  ensembl_gene_id = EXCLUDED.ensembl_gene_id,
  uniprot_id = EXCLUDED.uniprot_id,
  aliases = EXCLUDED.aliases,
  updated_at = NOW();
"""

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--upload-id", required=True, type=int)
    p.add_argument("--hgnc", required=True, help="HGNC complete set TSV")
    p.add_argument("--ensembl", required=False, help="Ensembl genes TSV", default=None)
    p.add_argument("--uniprot", required=False, help="UniProt mapping TSV/CSV", default=None)
    p.add_argument("--version", required=True, help='e.g. "HGNC 2025-08; Ensembl GRCh37 rel105; UniProt 2025_02"')
    p.add_argument("--chunk", type=int, default=5000)
    return p.parse_args()

def load_hgnc(path: str):
    # Expected columns (robust): hgnc_id, symbol, alias_symbol, prev_symbol, ensembl_gene_id, uniprot_ids
    # Many HGNC tsvs are tab-delimited with pipe-separated lists for aliases
    genes: Dict[str, dict] = {}
    with open(path, newline="") as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            sym = row.get("symbol") or row.get("approved_symbol")
            if not sym: 
                continue
            hgnc_id = row.get("hgnc_id")
            ens = row.get("ensembl_gene_id") or ""
            uni = row.get("uniprot_ids") or ""
            aliases: Set[str] = set()
            for k in ("alias_symbol", "prev_symbol", "alias", "synonyms"):
                v = row.get(k)
                if v:
                    for a in v.replace(" ", "").split("|"):
                        if a:
                            aliases.add(a)
            if ens:
                aliases.add(ens)
            if uni:
                for u in uni.split("|"):
                    if u:
                        aliases.add(u)
            genes[sym] = {
                "symbol": sym,
                "hgnc_id": hgnc_id,
                "ensembl_gene_id": ens or None,
                "uniprot_id": (uni.split("|")[0] if uni else None),
                "aliases": sorted(list(aliases)) if aliases else None
            }
    return genes

def load_ensembl(path: str) -> Dict[str, str]:
    if not path:
        return {}
    # Expect columns: gene_symbol, ensembl_gene_id (Biomart export)
    out = {}
    with open(path, newline="") as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            sym = row.get("gene_symbol") or row.get("external_gene_name")
            ens = row.get("ensembl_gene_id")
            if sym and ens:
                out[sym] = ens
    return out

def load_uniprot(path: str) -> Dict[str, str]:
    if not path:
        return {}
    # Expect columns: Gene Names (primary) or Gene Names; Entry (UniProt ID)
    out = {}
    # Try to auto-detect delimiter
    with open(path, "r") as f:
        sample = f.read(1024)
    delim = "," if sample.count(",") > sample.count("\t") else "\t"
    with open(path, newline="") as f:
        r = csv.DictReader(f, delimiter=delim)
        for row in r:
            sym = (row.get("Gene Names (primary)") or row.get("Gene Names") or "").split(" ")[0]
            uid = row.get("Entry") or row.get("From") or row.get("UniProtKB")
            if sym and uid:
                out[sym] = uid
    return out

def main():
    args = parse_args()
    hgnc = load_hgnc(args.hgnc)
    ensm = load_ensembl(args.ensembl)
    unip = load_uniprot(args.uniprot)

    # Merge external IDs if HGNC missing them
    for sym, eid in ensm.items():
        if sym in hgnc and not hgnc[sym].get("ensembl_gene_id"):
            hgnc[sym]["ensembl_gene_id"] = eid
            if hgnc[sym].get("aliases") is None:
                hgnc[sym]["aliases"] = [eid]
            else:
                if eid not in hgnc[sym]["aliases"]:
                    hgnc[sym]["aliases"].append(eid)

    for sym, uid in unip.items():
        if sym in hgnc and not hgnc[sym].get("uniprot_id"):
            hgnc[sym]["uniprot_id"] = uid
            if hgnc[sym].get("aliases") is None:
                hgnc[sym]["aliases"] = [uid]
            else:
                if uid not in hgnc[sym]["aliases"]:
                    hgnc[sym]["aliases"].append(uid)

    rows: List[Tuple] = []
    for g in hgnc.values():
        rows.append((
            g["symbol"],
            g.get("hgnc_id"),
            g.get("ensembl_gene_id"),
            g.get("uniprot_id"),
            g.get("aliases")
        ))

    sample_dir = os.path.join("reports", f"upload_{args.upload_id}")
    sample_csv = os.path.join(sample_dir, "gene_identifiers_sample.csv")
    write_csv_sample(sample_csv,
        header=["gene_symbol", "hgnc_id", "ensembl_gene_id", "uniprot_id", "aliases"],
        rows=[(r[0], r[1], r[2], r[3], ",".join(r[4]) if r[4] else "") for r in rows],
        limit=100
    )

    with psycopg.connect(get_pgurl_from_env()) as conn:
        with conn.cursor() as cur:
            cur.execute(DDL)
        conn.commit()
        for page in chunked(rows, args.chunk):
            with conn.cursor() as cur:
                cur.executemany(UPSERT, page)
            conn.commit()

    print(f"[gene_identifiers] Upserted {len(rows)} rows into public.gene_identifiers")
    print(f"[gene_identifiers] Sample CSV: {sample_csv}")

if __name__ == "__main__":
    main()
