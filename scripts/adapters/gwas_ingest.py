#!/usr/bin/env python3
"""
Ingest GWAS Catalog associations TSV → public.gwas_by_rsid

- Restricts to rsIDs present in current upload (staging_array_calls.upload_id)
- Supports both GWAS TSVs:
    * gwas-catalog-associations.tsv
    * gwas-catalog-associations_ontology-annotated.tsv
- Extracts: rsid, trait, EFO id (when available), p-value, study accession
- Upsert with ON CONFLICT (rsid, efo_id, study_accession)
- Writes sample CSV: reports/upload_<id>/gwas_sample.csv

CLI:
  PYTHONUNBUFFERED=1 python3 scripts/adapters/gwas_ingest.py \
    --upload-id 2 \
    --source /mnt/nas_storage/ref/gwas/gwas_catalog_associations.tsv \
    --version "GWAS Catalog 2025-09-30" \
    --chunk 5000 --progress-every 50000
"""
import os, re, csv, argparse, psycopg, time
from typing import Optional, Iterable, Tuple, List, Dict

def get_pgurl() -> str:
    # empty string tells psycopg to use PG* env vars
    return os.environ.get("PGURL") or ""

def parse_efo_id(uri_field: str) -> Optional[str]:
    # pick first EFO_######## from any URI list
    if not uri_field:
        return None
    m = re.search(r'(EFO[_:]\d+)', uri_field)
    return m.group(1).replace(':','_') if m else None

def parse_pvalue(pv: Optional[str]) -> Optional[float]:
    if pv is None:
        return None
    s = pv.strip()
    if not s:
        return None
    # Normalize common variants: ×, "x10^", "e", parentheses text, semicolon-separated
    s = s.replace('×','x').replace('X','x')
    s = re.sub(r'\s*e\s*([+-]?\d+)$', r'E\1', s, flags=re.I)
    s = s.replace('x10^', 'E')
    s = re.sub(r'\((.*?)\)', '', s)  # drop "(...)" extras
    parts = s.split(';')
    s = parts[0].strip()
    try:
        return float(s)
    except Exception:
        return None

def chunked(it: Iterable, n: int):
    buf = []
    for x in it:
        buf.append(x)
        if len(buf) >= n:
            yield buf
            buf = []
    if buf:
        yield buf

def header_key_map(fieldnames: List[str]) -> Dict[str,str]:
    # Create a case/space-insensitive map: canonical_key -> actual header as in file
    kmap: Dict[str,str] = {}
    def canon(s: str) -> str:
        return re.sub(r'[^a-z0-9]+', '', s.lower())
    for h in fieldnames or []:
        kmap[canon(h)] = h
    return kmap

def pick(row: Dict[str,str], kmap: Dict[str,str], *candidates: str) -> str:
    # candidates are canonical-ish names, like 'snps', 'pvalue', 'pvaluetext'
    for c in candidates:
        key = re.sub(r'[^a-z0-9]+','', c.lower())
        if key in kmap:
            return row.get(kmap[key], "") or ""
    return ""

def build_rs_set(conn, upload_id: int) -> set[str]:
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT rsid
            FROM public.staging_array_calls
            WHERE upload_id = %s AND rsid ~ '^rs[0-9]+$'
        """, (upload_id,))
        return {r[0] for r in cur.fetchall()}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload-id", type=int, required=True)
    ap.add_argument("--source", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--chunk", type=int, default=5000)
    ap.add_argument("--progress-every", type=int, default=50000)
    args = ap.parse_args()

    t0 = time.time()
    with psycopg.connect(get_pgurl()): pass  # fail fast if env/DSN is bad
    with psycopg.connect(get_pgurl()) as conn:
        rs_in_upload = build_rs_set(conn, args.upload_id)
        print(f"[gwas] upload {args.upload_id}: {len(rs_in_upload)} rsIDs in scope", flush=True)

        kept = 0
        seen = 0
        to_upsert: List[Tuple[str,str,str,Optional[float],str,str,str]] = []

        with open(args.source, newline='', encoding="utf-8") as f:
            rdr = csv.DictReader(f, delimiter='\t')
            kmap = header_key_map(rdr.fieldnames or [])
            for row in rdr:
                seen += 1
                snps = pick(row, kmap, 'snps', 'snp', 'snps(snp)', 'strongest snp-risk allele')
                m = re.search(r'(rs\d+)', snps or "")
                if not m:
                    continue
                rsid = m.group(1)
                if rsid not in rs_in_upload:
                    continue

                # Trait and EFO fields
                trait = pick(row, kmap, 'mapped_trait', 'disease/trait', 'trait').strip()
                efo_uri = pick(row, kmap, 'mapped_trait_uri', 'efo_uri', 'uri')
                efo_id = parse_efo_id(efo_uri) or ""

                # Prefer numeric P-VALUE; fall back to P-VALUE (TEXT)
                pv_raw = pick(row, kmap, 'p-value', 'pvalue', 'pvalue(text)', 'p-value(text)')
                if not pv_raw:
                    pv_raw = pick(row, kmap, 'pvalue(text)', 'pvaluetext')  # more variants
                pval = parse_pvalue(pv_raw)

                # Study accession
                study = pick(row, kmap, 'study accession', 'studyaccession', 'gcst', 'gcst id').strip()
                if not study:
                    pmid = pick(row, kmap, 'pubmedid').strip()
                    study = f"PMID:{pmid}" if pmid else "NA"

                to_upsert.append((
                    rsid, efo_id, trait, pval, study,
                    "GWAS Catalog", args.version
                ))

                kept += 1
                if kept % args.progress_every == 0:
                    print(f"[gwas] kept {kept} / seen {seen}", flush=True)

        print(f"[gwas] parsed {seen}, kept {kept}", flush=True)

        with conn.cursor() as cur:
            for chunk in chunked(to_upsert, args.chunk):
                cur.executemany("""
                    INSERT INTO public.gwas_by_rsid
                      (rsid, efo_id, trait, pvalue, study_accession, source, source_version, updated_at)
                    VALUES (%s,%s,%s,%s,%s,%s,%s, now())
                    ON CONFLICT (rsid, efo_id, study_accession)
                    DO UPDATE SET
                      trait = EXCLUDED.trait,
                      pvalue = EXCLUDED.pvalue,
                      source = EXCLUDED.source,
                      source_version = EXCLUDED.source_version,
                      updated_at = now()
                """, chunk)

        outdir = f"reports/upload_{args.upload_id}"
        os.makedirs(outdir, exist_ok=True)
        sample = os.path.join(outdir, "gwas_sample.csv")
        with open(sample, "w", newline='') as f:
            w = csv.writer(f)
            w.writerow(["rsid","efo_id","trait","pvalue","study_accession","source","source_version"])
            for row in to_upsert[:200]:
                w.writerow(row)

    dt = time.time() - t0
    print(f"[gwas] DONE: kept={kept}, wrote sample={sample}, elapsed={dt:.1f}s", flush=True)

if __name__ == "__main__":
    main()
