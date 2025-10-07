#!/usr/bin/env python3
"""
ClinVar VCF → clinvar_by_rsid loader (+ optional evidence linkage).

Usage:
  python scripts/adapters/clinvar_vcf_adapter.py \
    --vcf /path/clinvar_GRCh37.vcf.gz \
    --build GRCh37 \
    --upsert \
    --limit 0

Requires: pysam, psycopg[binary], tqdm
"""

import os, sys, argparse, datetime
from typing import Optional, Tuple, Dict
import pysam
import psycopg
from tqdm import tqdm

# ---- DB helpers -------------------------------------------------------------

def env_dsn() -> str:
    host = os.getenv("PGHOST", "localhost")
    port = os.getenv("PGPORT", "5432")
    db   = os.getenv("PGDATABASE", "genome_db")
    user = os.getenv("PGUSER", "genouser")
    pw   = os.getenv("PGPASSWORD", "")
    return f"postgresql://{user}:{pw}@{host}:{port}/{db}"

def ensure_tables(conn) -> None:
    with conn.cursor() as cur:
        cur.execute("""
        CREATE TABLE IF NOT EXISTS public.clinvar_by_rsid(
          rsid           text PRIMARY KEY,
          clnsig_raw     text,
          review_stars   int,
          conditions     text,
          last_eval_date date
        );
        """)
        # Sources/biblio/evidence tables were created earlier; we’ll reference them if present
        conn.commit()

# ---- ClinVar parsing --------------------------------------------------------

def parse_review_stars(clnrevstat: Optional[str]) -> int:
    """
    Map CLNREVSTAT → 0..4 (simple heuristic).
    """
    if not clnrevstat:
        return 0
    s = clnrevstat.lower()
    if "practice_guideline" in s:
        return 4
    if "reviewed_by_expert_panel" in s:
        return 3
    if "criteria_provided" in s and "multiple_submitters" in s and "no_conflicts" in s:
        return 2
    if "criteria_provided" in s and "single_submitter" in s:
        return 1
    return 0

def parse_clndate(clndate: Optional[str]) -> Optional[datetime.date]:
    """
    ClinVar CLNDATE is usually YYYYMMDD or YYYYMM. Be permissive.
    """
    if not clndate:
        return None
    s = clndate.strip()
    for fmt in ("%Y%m%d", "%Y%m", "%Y"):
        try:
            dt = datetime.datetime.strptime(s, fmt)
            return dt.date()
        except ValueError:
            continue
    return None

def row_from_record(rec) -> Optional[Tuple[str,str,int,str,Optional[datetime.date]]]:
    """
    Build (rsid, clnsig_raw, stars, conditions, last_eval_date) from a VCF record.
    - Rec.ID is ClinVar Variation ID; rsID is in INFO['RS'] (int).
    - CLNSIG: raw significance string(s)
    - CLNREVSTAT: review status → stars
    - CLNDN: disease names (pipe-delimited)
    - CLNDATE: last eval date (optional; sometimes missing)
    """
    info = rec.info

    # Some ClinVar VCFs have RS as an array; normalize to a single rs id if present
    rs = info.get("RS", None)
    if rs is None:
        return None
    if isinstance(rs, (list, tuple)) and rs:
        rsnum = rs[0]
    else:
        rsnum = rs
    rsid = f"rs{rsnum}"

    clnsig = info.get("CLNSIG", None)
    if isinstance(clnsig, (list, tuple)):
        clnsig = ",".join(map(str, clnsig))
    clnrev = info.get("CLNREVSTAT", None)
    if isinstance(clnrev, (list, tuple)):
        clnrev = ",".join(map(str, clnrev))
    cond = info.get("CLNDN", None)
    if isinstance(cond, (list, tuple)):
        cond = "|".join(map(str, cond))
    clndate = info.get("CLNDATE", None)
    last_eval = parse_clndate(str(clndate)) if clndate is not None else None

    stars = parse_review_stars(clnrev)
    return (rsid, clnsig or None, stars, cond or None, last_eval)

# ---- Upsert & optional evidence --------------------------------------------

def upsert_batch(conn, rows):
    if not rows:
        return 0
    with conn.cursor() as cur:
        cur.execute("""
        INSERT INTO public.clinvar_by_rsid (rsid, clnsig_raw, review_stars, conditions, last_eval_date)
        SELECT x.rsid, x.clnsig_raw, x.review_stars, x.conditions, x.last_eval_date
        FROM unnest(%s::text[], %s::text[], %s::int[], %s::text[], %s::date[]) 
             AS x(rsid, clnsig_raw, review_stars, conditions, last_eval_date)
        ON CONFLICT (rsid) DO UPDATE
           SET clnsig_raw = EXCLUDED.clnsig_raw,
               review_stars = GREATEST(public.clinvar_by_rsid.review_stars, EXCLUDED.review_stars),
               conditions = COALESCE(EXCLUDED.conditions, public.clinvar_by_rsid.conditions),
               last_eval_date = COALESCE(EXCLUDED.last_eval_date, public.clinvar_by_rsid.last_eval_date);
        """,
        (
          [r[0] for r in rows],
          [r[1] for r in rows],
          [r[2] for r in rows],
          [r[3] for r in rows],
          [r[4] for r in rows],
        ))
    conn.commit()
    return len(rows)

def maybe_seed_source(conn):
    with conn.cursor() as cur:
        cur.execute("""
        INSERT INTO public.knowledge_sources(name, kind, uri)
        VALUES ('ClinVar','database','https://www.ncbi.nlm.nih.gov/clinvar/')
        ON CONFLICT (name) DO NOTHING;
        """)
    conn.commit()

# (Optional) add a tiny evidence record per rsid, linked to ClinVar page.
# Keeps it simple: one evidence row per rsid with a generic URL.
def add_basic_evidence(conn, rsids):
    if not rsids:
        return
    with conn.cursor() as cur:
        # source
        cur.execute("SELECT source_id FROM public.knowledge_sources WHERE name='ClinVar'")
        row = cur.fetchone()
        if not row:
            return
        source_id = row[0]

        # Insert biblio records (one per rsid, url is unique) and evidence_items; link if we have variant_effects row_id
        for rs in rsids:
            # ClinVar landing for rs (redirects to appropriate record)
            url = f"https://www.ncbi.nlm.nih.gov/snp/{rs}"
            cur.execute("""
                INSERT INTO public.biblio_refs(source_id, url, title)
                VALUES (%s, %s, %s)
                ON CONFLICT (url) DO NOTHING
                RETURNING citation_id
            """, (source_id, url, f"ClinVar/dbSNP page for {rs}"))
            r = cur.fetchone()
            if r is None:
                # Already existed; fetch id
                cur.execute("SELECT citation_id FROM public.biblio_refs WHERE url=%s", (url,))
                r = cur.fetchone()
            citation_id = r[0]

            cur.execute("""
                INSERT INTO public.evidence_items(citation_id, supports, strength, level, excerpt)
                VALUES (%s, true, 'summary', 'expert_panel', 'Auto-seeded ClinVar/dbSNP link')
                RETURNING evidence_id
            """, (citation_id,))
            evidence_id = cur.fetchone()[0]

            # Link to variant_effects if present for this rs
            cur.execute("""
                INSERT INTO public.evidence_variant_effects(row_id, evidence_id)
                SELECT ve.row_id, %s
                FROM public.variant_effects ve
                WHERE ve.rsid = %s
                ON CONFLICT DO NOTHING
            """, (evidence_id, rs))
    conn.commit()

# ---- CLI --------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vcf", required=True, help="Path to ClinVar VCF.gz (GRCh37 or GRCh38)")
    ap.add_argument("--build", choices=["GRCh37","GRCh38"], required=True)
    ap.add_argument("--upsert", action="store_true", help="Upsert into clinvar_by_rsid")
    ap.add_argument("--with-evidence", action="store_true", help="Create basic evidence links per rsid")
    ap.add_argument("--limit", type=int, default=0, help="Process first N records (0 = all)")
    ap.add_argument("--batch-size", type=int, default=5000)
    args = ap.parse_args()

    dsn = env_dsn()
    with psycopg.connect(dsn) as conn:
        ensure_tables(conn)
        maybe_seed_source(conn)

        vf = pysam.VariantFile(args.vcf)
        rows, seen_rs, n_upserted = [], set(), 0
        it = enumerate(vf.fetch())
        pbar = tqdm(total=args.limit or None, desc="ClinVar VCF records", unit="rec")
        for i, rec in it:
            if args.limit and i >= args.limit:
                break
            tup = row_from_record(rec)
            if tup is None:
                pbar.update(1); continue
            rsid = tup[0]
            if rsid in seen_rs:
                pbar.update(1); continue
            seen_rs.add(rsid)
            rows.append(tup)
            if len(rows) >= args.batch_size:
                if args.upsert:
                    n_upserted += upsert_batch(conn, rows)
                rows.clear()
            pbar.update(1)

        if rows and args.upsert:
            n_upserted += upsert_batch(conn, rows)

        if args.with_evidence and seen_rs:
            add_basic_evidence(conn, list(seen_rs))

        print(f"Done. unique_rsids_seen={len(seen_rs)} upserted_rows≈{n_upserted}")

if __name__ == "__main__":
    main()
