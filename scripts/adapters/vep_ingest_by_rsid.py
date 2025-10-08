#!/usr/bin/env python3
"""
Adapter A: VEP CSQ → public.vep_by_rsid

- Reads a VEP-annotated VCF (.vcf.gz + .tbi) and backfills per-rsid consequences for a target upload_id's rsIDs
- Candidate selection prefers CANONICAL, then highest IMPACT rank
- Upserts idempotently into public.vep_by_rsid

CLI:
  --vep-vcf PATH         Path to VEP VCF.gz
  --upload-id INT        Upload ID to fetch rsIDs from staging_array_calls
  --limit INT            Process only first N VCF records (0 = all)
  --dry-run              Print first 20 tuples and summary; no DB writes

Env fallbacks:
  VEP_VCF, UPLOAD_ID, PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD

Exit codes:
  0: success / nothing to do
  2: missing CSQ header or invalid inputs
  3: VCF not found or missing .tbi
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import psycopg
import pysam


IMPACT_RANK = {"HIGH": 4, "MODERATE": 3, "LOW": 2, "MODIFIER": 1}


def dsn_from_env() -> str:
    host = os.getenv("PGHOST", "localhost")
    port = os.getenv("PGPORT", "5432")
    db = os.getenv("PGDATABASE", "genomics")
    user = os.getenv("PGUSER", "genouser")
    pw = os.getenv("PGPASSWORD", "")
    return f"postgresql://{user}:{pw}@{host}:{port}/{db}"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Ingest VEP CSQ by rsID into public.vep_by_rsid")
    ap.add_argument("--vep-vcf", dest="vep_vcf", help="Path to VEP VCF.gz", default=os.getenv("VEP_VCF"))
    ap.add_argument("--upload-id", type=int, help="Upload ID to source rsIDs from staging_array_calls", default=int(os.getenv("UPLOAD_ID", "0") or 0))
    ap.add_argument("--limit", type=int, default=0, help="Process first N VCF records (0 = all)")
    ap.add_argument("--dry-run", action="store_true", help="Only print first 20 parsed tuples; do not write DB")
    return ap.parse_args()


def need_file(path: Optional[str]) -> str:
    if not path:
        print("[vep-by-rsid] error: --vep-vcf or VEP_VCF env required", file=sys.stderr)
        sys.exit(2)
    if not os.path.exists(path):
        print(f"[vep-by-rsid] VCF not found: {path}", file=sys.stderr)
        sys.exit(3)
    if not os.path.exists(path + ".tbi"):
        print(f"[vep-by-rsid] missing tabix index (expected {path}.tbi)", file=sys.stderr)
        sys.exit(3)
    return path


def get_target_rsids(dsn: str, upload_id: int) -> Tuple[set[str], set[str]]:
    if not upload_id or upload_id <= 0:
        print("[vep-by-rsid] error: --upload-id or UPLOAD_ID env required", file=sys.stderr)
        sys.exit(2)
    with psycopg.connect(dsn) as con:
        rows = con.execute(
            """
            SELECT DISTINCT rsid
            FROM public.staging_array_calls
            WHERE upload_id = %s AND rsid ~ '^rs[0-9]+$'
            """,
            (upload_id,),
        ).fetchall()
    rs_full = {r[0] for r in rows if r and r[0]}
    rs_nums = {r[2:] for r in rs_full if r.startswith("rs")}
    return rs_full, rs_nums


def parse_csq_header(vf: pysam.VariantFile) -> List[str]:
    if "CSQ" not in vf.header.info:
        print("[vep-by-rsid] error: CSQ INFO header not found; ensure VEP-annotated VCF", file=sys.stderr)
        sys.exit(2)
    desc = vf.header.info["CSQ"].description or ""
    # Find "Format: A|B|C|..." segment
    fmt = None
    for token in desc.split(","):
        if "Format:" in token:
            # The rest after 'Format:' may include spaces
            fmt = token.split("Format:", 1)[1].strip()
            break
    if not fmt:
        # Some headers use 'Format: Allele|Consequence|IMPACT|...'
        # Try a broader search
        if "Format:" in desc:
            fmt = desc.split("Format:", 1)[1].strip()
        else:
            print("[vep-by-rsid] error: could not parse CSQ 'Format' from header", file=sys.stderr)
            sys.exit(2)
    fields = [f.strip() for f in fmt.split("|")]
    return fields


def csq_dicts_for_record(rec, csq_fields: Sequence[str]) -> List[Dict[str, str]]:
    vals = rec.info.get("CSQ")
    if vals is None:
        return []
    if isinstance(vals, (tuple, list)):
        rows = list(vals)
    else:
        rows = [str(vals)]
    out: List[Dict[str, str]] = []
    for row in rows:
        parts = row.split("|")
        # Pad/truncate to header length
        if len(parts) < len(csq_fields):
            parts += [""] * (len(csq_fields) - len(parts))
        elif len(parts) > len(csq_fields):
            parts = parts[: len(csq_fields)]
        out.append({csq_fields[i]: parts[i] for i in range(len(csq_fields))})
    return out


def try_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        s = str(x).strip()
        if s == "":
            return None
        return float(s)
    except Exception:
        return None


def spliceai_max_from_dict(d: Dict[str, str], csq_fields: Sequence[str]) -> Optional[float]:
    # Prefer explicit DS_* fields if present in CSQ header
    ds_keys = [k for k in csq_fields if k.upper().startswith("DS_")]
    vals: List[float] = []
    for k in ds_keys:
        v = try_float(d.get(k))
        if v is not None:
            vals.append(v)
    if vals:
        return max(vals) if vals else None
    # Fallback: a single SpliceAI/SPLICEAI field with pipe-delimited subfields
    for k in ("SpliceAI", "SPLICEAI"):
        raw = d.get(k)
        if not raw:
            continue
        # Extract all floats and take max
        vs: List[float] = []
        for token in raw.replace(",", "|").split("|"):
            v = try_float(token)
            if v is not None:
                vs.append(v)
        if vs:
            return max(vs)
    return None


def build_extras(d: Dict[str, str]) -> Dict[str, Any]:
    keys = ["Transcript", "HGVSp", "HGVSc", "SIFT", "PolyPhen", "CANONICAL", "BIOTYPE"]
    extras = {k: d.get(k) for k in keys if k in d and d.get(k)}
    return extras


def chunks(seq: Sequence[Tuple], size: int) -> Iterable[Sequence[Tuple]]:
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def main() -> int:
    args = parse_args()
    vcf_path = need_file(args.vep_vcf)
    dsn = dsn_from_env()

    rs_full, rs_nums = get_target_rsids(dsn, args.upload_id)
    if not rs_full:
        print("[vep-by-rsid] no target rsids for this upload; nothing to do")
        return 0
    print(f"[vep-by-rsid] targets: {len(rs_full):,} rsIDs for upload {args.upload_id}")

    # Open VCF
    try:
        vf = pysam.VariantFile(vcf_path)
    except Exception as e:
        print(f"[vep-by-rsid] failed to open VCF: {e}", file=sys.stderr)
        return 3

    csq_fields = parse_csq_header(vf)

    rows: Dict[str, Tuple[str, str, str, Optional[float], Optional[float], Optional[float], str]] = {}
    seen = matched = 0

    for rec in vf.fetch():
        seen += 1
        if args.limit and seen > args.limit:
            break
        hit_rs: set[str] = set()

        # ID match (rs123)
        rid = rec.id or ""
        if rid.startswith("rs") and rid in rs_full:
            hit_rs.add(rid)

        # INFO/RS match
        rs_info = rec.info.get("RS")
        if rs_info is not None:
            vals = rs_info if isinstance(rs_info, (tuple, list)) else (rs_info,)
            for v in vals:
                if str(v) in rs_nums:
                    hit_rs.add("rs" + str(v))

        if not hit_rs:
            continue
        matched += 1

        csq_dicts = csq_dicts_for_record(rec, csq_fields)
        candidates = [d for d in csq_dicts if d.get("SYMBOL")]
        if not candidates:
            continue
        canon = [d for d in candidates if d.get("CANONICAL", "") == "YES"]
        pool = canon if canon else candidates
        pick = max(pool, key=lambda d: IMPACT_RANK.get(d.get("IMPACT", "MODIFIER"), 1))

        gene_symbol = pick.get("SYMBOL") or None
        consequence = pick.get("Consequence") or None
        impact = pick.get("IMPACT") or None
        cadd_phred = try_float(pick.get("CADD_PHRED") or pick.get("CADD"))
        revel_score = try_float(pick.get("REVEL") or pick.get("REVEL_SCORE") or pick.get("REVEL_SCORE_PRED"))
        spliceai_max = spliceai_max_from_dict(pick, csq_fields)
        extras_json = json.dumps(build_extras(pick), separators=(",", ":"))

        for rs in hit_rs:
            rows[rs] = (
                rs,
                gene_symbol,
                consequence,
                impact,
                cadd_phred,
                revel_score,
                spliceai_max,
                extras_json,
            )

    print(f"[vep-by-rsid] seen={seen:,} matched={matched:,} upserting={len(rows):,}")

    if args.dry_run:
        print("[vep-by-rsid] --dry-run: first 20 tuples:")
        for i, v in enumerate(list(rows.values())[:20], 1):
            print(f"  {i:02d}: {v}")
        return 0

    if not rows:
        print("[vep-by-rsid] nothing to upsert; exiting")
        return 0

    # Upsert with explicit transaction (autocommit off)
    create_sql = """
    CREATE TABLE IF NOT EXISTS public.vep_by_rsid(
      rsid         text PRIMARY KEY,
      gene_symbol  text,
      consequence  text,
      impact       text,
      cadd_phred   double precision,
      revel_score  double precision,
      spliceai_max double precision,
      extras       jsonb
    )
    """

    with psycopg.connect(dsn) as con:
        con.execute(create_sql)
        # Build VALUES chunks
        vals: List[Tuple] = list(rows.values())
        BATCH = 1000
        total = 0
        for chunk in chunks(vals, BATCH):
            placeholders = ", ".join(["(" + ",".join(["%s"] * 8) + ")" for _ in chunk])
            sql = f"""
            INSERT INTO public.vep_by_rsid
              (rsid,gene_symbol,consequence,impact,cadd_phred,revel_score,spliceai_max,extras)
            VALUES {placeholders}
            ON CONFLICT (rsid) DO UPDATE SET
              gene_symbol=excluded.gene_symbol,
              consequence=excluded.consequence,
              impact=excluded.impact,
              cadd_phred=excluded.cadd_phred,
              revel_score=excluded.revel_score,
              spliceai_max=excluded.spliceai_max,
              extras=excluded.extras
            """
            flat_params: List[Any] = []
            for tup in chunk:
                flat_params.extend(tup)
            con.execute(sql, flat_params)
            total += len(chunk)
            if total % 5000 == 0:
                print(f"[vep-by-rsid] upserted {total}/{len(vals)}")
        con.commit()

    print("[vep-by-rsid] upsert complete")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit as e:
        raise
    except Exception as e:
        print(f"[vep-by-rsid] fatal: {e}", file=sys.stderr)
        sys.exit(1)
