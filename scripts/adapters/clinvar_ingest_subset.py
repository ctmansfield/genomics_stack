#!/usr/bin/env python3
"""
Ingest a ClinVar VCF subset (by rsID) into public.clinvar_by_rsid.

Env:
  UPLOAD_ID     (int)   -- required
  CLINVAR_VCF   (path)  -- required, bgzipped + indexed .tbi
  PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD -- required
"""
import os, sys, re, argparse, datetime as dt
import psycopg
import pysam


def need(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        print(f"[clinvar] missing env: {name}", file=sys.stderr)
        sys.exit(2)
    return v


# --- env / DSN helpers --------------------------------------------------------
def build_dsn() -> str:
    host = need("PGHOST")
    port = need("PGPORT")
    db   = need("PGDATABASE")
    user = need("PGUSER")
    pwd  = need("PGPASSWORD")
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"


# --- helpers ------------------------------------------------------------------
def review_stars(clnrev: str | None) -> int | None:
    if not clnrev:
        return None
    # Normalize whitespace/case; also keep full string for composite checks
    s_full = re.sub(r"\s+", " ", str(clnrev).lower()).strip()
    # Split into parts for simple contains checks
    parts = [p.strip() for p in re.split(r"[;,|]+", s_full) if p and p.strip()]
    if not parts:
        return None
    # Priority mapping based on ClinVar definitions
    if "practice guideline" in s_full:
        return 4
    if "reviewed by expert panel" in s_full:
        return 3
    if ("criteria provided" in s_full and "multiple submitters" in s_full and "no conflicts" in s_full):
        return 2
    if "criteria provided" in s_full:
        return 1
    if any("conflicting" in p for p in parts):
        return 1
    if "no assertion" in s_full:
        return 0
    return 0


def normalize_clnsig(clnsig) -> str | None:
    if clnsig is None:
        return None
    if isinstance(clnsig, (tuple, list)):
        s = ",".join(map(str, clnsig))
    else:
        s = str(clnsig)
    # Normalize delimiters but keep multi-word tokens intact
    s = s.replace("|", ",").replace(";", ",")
    toks = [re.sub(r"\s+", " ", t).strip().lower() for t in s.split(",")]
    toks = [t for t in toks if t]
    return ", ".join(toks) or None


def normalize_conditions(conds) -> str | None:
    if conds is None:
        return None
    if isinstance(conds, (tuple, list)):
        s = "|".join(map(str, conds))
    else:
        s = str(conds)
    s = s.replace("|", "; ")
    s = re.sub(r"_+", " ", s).strip(" ;")
    return s or None


def parse_clndate(val) -> dt.date | None:
    if not val:
        return None
    if isinstance(val, (tuple, list)):
        val = val[0]
    s = str(val)
    for fmt in ("%Y%m%d", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(s, fmt).date()
        except ValueError:
            pass
    return None


def run_ingest(upload_id: int, vcf_path: str, dsn: str, rsid_file: str | None = None, dry_run: bool = False) -> dict:
    if not os.path.exists(vcf_path):
        print(f"[clinvar] VCF not found: {vcf_path}", file=sys.stderr)
        sys.exit(2)

    # --- 1) Gather target rsIDs ----------------------------------------------
    if rsid_file:
        with open(rsid_file, "r", encoding="utf-8") as fh:
            rsids = {line.strip() for line in fh if line.strip()}
        # Normalize forms like '123' to 'rs123'
        rsids = {("rs" + r) if r.isdigit() else r for r in rsids}
        print(f"[clinvar] rsid-only mode: {len(rsids):,} targets from {rsid_file}")
    else:
        with psycopg.connect(dsn) as con:
            rsids = {r for (r,) in con.execute(
                """
                SELECT DISTINCT rsid
                FROM public.staging_array_calls
                WHERE upload_id = %s AND rsid ~ '^rs[0-9]+$'
                """,
                (upload_id,),
            )}
        print(f"[clinvar] target rsids: {len(rsids):,}")

    rs_full = rsids
    rs_nums = {r[2:] for r in rsids if r.startswith("rs")}

    # --- 2) Stream ClinVar VCF; collect rows ---------------------------------
    vf = pysam.VariantFile(vcf_path)
    try:
        HAS_INFO = {k: (k in vf.header.info) for k in ("CLNSIG", "CLNREVSTAT", "CLNDN", "CLNDATE", "RS")}

        rows: dict[str, tuple] = {}
        seen = matched = 0
        missing_rs = malformed_info = 0

        for rec in vf.fetch():
            seen += 1
            hit_rs: set[str] = set()

            # ID match (e.g., "rs1801133")
            rid = rec.id or ""
            if rid.startswith("rs") and rid in rs_full:
                hit_rs.add(rid)

            # INFO/RS match (int/str/list)
            try:
                rs_info = rec.info.get("RS") if HAS_INFO.get("RS", False) else None
                if rs_info is not None:
                    vals = rs_info if isinstance(rs_info, (tuple, list)) else (rs_info,)
                    for v in vals:
                        if str(v) in rs_nums:
                            hit_rs.add("rs" + str(v))
                else:
                    if not rid.startswith("rs"):
                        missing_rs += 1
            except Exception:
                malformed_info += 1

            if not hit_rs:
                continue
            matched += 1

            # Safely read INFO fields only if present in header
            try:
                clnsig_raw = rec.info.get("CLNSIG") if HAS_INFO["CLNSIG"] else None
                clnsig_norm = normalize_clnsig(clnsig_raw)

                clnrev = rec.info.get("CLNREVSTAT") if HAS_INFO["CLNREVSTAT"] else None
                stars = review_stars(clnrev)

                conds_raw = rec.info.get("CLNDN") if HAS_INFO["CLNDN"] else None
                conds = normalize_conditions(conds_raw)

                last_eval = parse_clndate(rec.info.get("CLNDATE")) if HAS_INFO["CLNDATE"] else None
            except Exception:
                malformed_info += 1
                continue

            tpl = (
                clnsig_norm,
                stars,
                conds,
                last_eval,
            )

            for rs in hit_rs:
                rows[rs] = (rs, tpl[0], tpl[1], tpl[2], tpl[3])  # last-write wins

        print(f"[clinvar] seen={seen:,} matched={matched:,} upserting={len(rows):,} missing_rs={missing_rs:,} malformed_info={malformed_info:,}")

        if dry_run:
            print("[clinvar] --dry-run: first 20 tuples:")
            for i, v in enumerate(list(rows.values())[:20], 1):
                print(f"  {i:02d}: {v}")
            return {"rows": len(rows), "matched": matched, "seen": seen}

        if not rows:
            print("[clinvar] nothing to upsert; exiting")
            return {"rows": 0, "matched": matched, "seen": seen}

        # --- 3) Upsert ------------------------------------------------------------
        insert_sql = """
        INSERT INTO public.clinvar_by_rsid
          (rsid, clnsig_raw, review_stars, conditions, last_eval_date)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (rsid) DO UPDATE
          SET clnsig_raw   = EXCLUDED.clnsig_raw,
              review_stars = EXCLUDED.review_stars,
              conditions   = EXCLUDED.conditions,
              last_eval_date =
                  COALESCE(EXCLUDED.last_eval_date, public.clinvar_by_rsid.last_eval_date)
        """

        with psycopg.connect(dsn) as con, con.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS public.clinvar_by_rsid(
                  rsid           text PRIMARY KEY,
                  clnsig_raw     text,
                  review_stars   int,
                  conditions     text,
                  last_eval_date date
                )
                """
            )

            vals = list(rows.values())
            BATCH = 5000
            for i in range(0, len(vals), BATCH):
                chunk = vals[i:i+BATCH]
                cur.executemany(insert_sql, chunk)
                print(f"[clinvar] upserted {min(i+BATCH, len(vals))}/{len(vals)}")
            con.commit()

        print("[clinvar] upsert complete")
        return {"rows": len(rows), "matched": matched, "seen": seen}
    finally:
        try:
            vf.close()
        except Exception:
            pass


if __name__ == "__main__":
    # Small inline tests for helpers
    tests = [
        ("practice guideline", 4),
        ("Reviewed by expert panel", 3),
        ("Criteria provided, multiple submitters, no conflicts", 2),
        ("criteria provided, single submitter", 1),
        ("conflicting interpretations", 1),
        ("no assertion provided", 0),
    ]
    print("[clinvar:test] review_stars")
    for s, want in tests:
        got = review_stars(s)
        print(f"  {s!r} -> {got}")

    sig_tests = [
        ("Pathogenic, Likely pathogenic", "pathogenic, likely pathogenic"),
        (("Benign", "Likely benign"), "benign, likely benign"),
        ("uncertain significance|Conflicting interpretations", "uncertain significance, conflicting interpretations"),
    ]
    print("[clinvar:test] normalize_clnsig")
    for s, want in sig_tests:
        got = normalize_clnsig(s)
        print(f"  {s!r} -> {got}")

    parser = argparse.ArgumentParser(description="Ingest ClinVar subset by rsID")
    parser.add_argument("--upload-id", type=int, help="Upload ID to source rsIDs from staging_array_calls")
    parser.add_argument("--vcf", required=True, help="Path to bgzipped ClinVar VCF")
    parser.add_argument("--rsid-only", dest="rsid_only", help="File containing newline RSIDs to backfill; skips staging read")
    parser.add_argument("--dry-run", action="store_true", help="Only print first 20 parsed tuples; do not write DB")
    args = parser.parse_args()

    # Build DSN from environment
    dsn = build_dsn()

    if not args.upload_id and not args.rsid_only:
        print("[clinvar] require --upload-id or --rsid-only FILE", file=sys.stderr)
        sys.exit(2)

    run_ingest(
        upload_id=args.upload_id or -1,
        vcf_path=args.vcf,
        dsn=dsn,
        rsid_file=args.rsid_only,
        dry_run=args.dry_run,
    )
