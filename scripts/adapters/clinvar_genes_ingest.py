#!/usr/bin/env python3
import os, sys, re
import psycopg
import pysam

UPLOAD_ID = int(os.environ.get("UPLOAD_ID", "0"))
VCF_PATH  = os.environ.get("CLINVAR_VCF", "")
DSN = f"postgresql://{os.environ['PGUSER']}:{os.environ['PGPASSWORD']}@" \
      f"{os.environ['PGHOST']}:{os.environ['PGPORT']}/{os.environ['PGDATABASE']}"

if not UPLOAD_ID or not VCF_PATH:
    print("[clinvar-genes] set UPLOAD_ID and CLINVAR_VCF", file=sys.stderr); sys.exit(2)

print(f"[clinvar-genes] upload={UPLOAD_ID} vcf={VCF_PATH}")

# 1) rsIDs in this upload
with psycopg.connect(DSN) as con:
    rsids = set(r for (r,) in con.execute("""
        SELECT DISTINCT rsid
        FROM public.staging_array_calls
        WHERE upload_id=%s AND rsid ~ '^rs[0-9]+$'
    """, (UPLOAD_ID,)))
print(f"[clinvar-genes] target rsids: {len(rsids):,}")

rs_nums = set(r[2:] for r in rsids)  # "123"
rs_full = rsids                      # "rs123"

# 2) Scan ClinVar; collect rsid→gene_symbol (first symbol if multiple)
vf = pysam.VariantFile(VCF_PATH)

has_geneinfo     = ("GENEINFO"     in vf.header.info)  # canonical in ClinVar
has_clngeneinfo  = ("CLNGENEINFO"  in vf.header.info)  # older/alt; not always present

def pick_first_symbol(rec):
    # Prefer GENEINFO (format: SYMBOL:ID[|SYMBOL:ID...])
    if has_geneinfo:
        gi = rec.info.get("GENEINFO")
        if gi:
            first = str(gi).split("|", 1)[0]
            sym = first.split(":", 1)[0].strip()
            if sym: return sym
    # Fallback: CLNGENEINFO if defined in header
    if has_clngeneinfo:
        try:
            cgi = rec.info.get("CLNGENEINFO")
        except Exception:
            cgi = None
        if cgi:
            s = str(cgi)
            m = re.search(r"\(([A-Za-z0-9._-]+)\)", s)
            if m:
                return m.group(1)
    return None

rows = {}  # rsid -> gene_symbol

for rec in vf.fetch():
    hit_rs = set()

    rid = (rec.id or "")
    if rid.startswith("rs") and rid in rs_full:
        hit_rs.add(rid)

    rs_info = rec.info.get("RS") if ("RS" in vf.header.info) else None
    if rs_info is not None:
        vals = [str(x) for x in (rs_info if isinstance(rs_info, (tuple, list)) else [rs_info])]
        for v in vals:
            if v in rs_nums:
                hit_rs.add("rs"+v)

    if not hit_rs:
        continue

    sym = pick_first_symbol(rec)
    if not sym:
        continue

    for rs in hit_rs:
        rows[rs] = sym  # last write wins

print(f"[clinvar-genes] matched rsIDs with gene: {len(rows):,}")
if not rows:
    print("[clinvar-genes] nothing to upsert; exiting"); sys.exit(0)

# 3) Upsert into clinvar_gene_by_rsid, then sync gene/variant catalogs
with psycopg.connect(DSN) as con, con.cursor() as cur:
    cur.execute("""
      CREATE TABLE IF NOT EXISTS public.clinvar_gene_by_rsid(
        rsid text PRIMARY KEY,
        gene_symbol text
      )
    """)
    cur.execute("""
      CREATE TABLE IF NOT EXISTS public.gene_catalog(
        gene_symbol  text PRIMARY KEY,
        ensembl_id   text,
        created_at   timestamptz DEFAULT now(),
        updated_at   timestamptz
      )
    """)
    cur.execute("""
      CREATE TABLE IF NOT EXISTS public.variant_catalog(
        rsid         text PRIMARY KEY,
        gene_symbol  text REFERENCES public.gene_catalog(gene_symbol),
        clinvar_id   text,
        created_at   timestamptz DEFAULT now(),
        updated_at   timestamptz
      )
    """)

    data = [(rs, gene) for rs, gene in rows.items()]
    CHUNK = 5000
    for i in range(0, len(data), CHUNK):
        chunk = data[i:i+CHUNK]
        cur.executemany("""
          INSERT INTO public.clinvar_gene_by_rsid(rsid, gene_symbol)
          VALUES (%s, %s)
          ON CONFLICT (rsid) DO UPDATE SET gene_symbol = EXCLUDED.gene_symbol
        """, chunk)
        print(f"[clinvar-genes] upserted {min(i+CHUNK,len(data))}/{len(data)}")

    # Sync catalogs
    cur.execute("""
      INSERT INTO public.gene_catalog(gene_symbol)
      SELECT DISTINCT gene_symbol
      FROM public.clinvar_gene_by_rsid
      ON CONFLICT DO NOTHING
    """)
    cur.execute("""
      INSERT INTO public.variant_catalog(rsid, gene_symbol)
      SELECT rsid, gene_symbol
      FROM public.clinvar_gene_by_rsid
      ON CONFLICT (rsid) DO UPDATE SET gene_symbol = EXCLUDED.gene_symbol
    """)

    con.commit()

print("[clinvar-genes] complete")
