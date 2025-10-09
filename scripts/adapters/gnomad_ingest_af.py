#!/usr/bin/env python3
"""
Ingest gnomAD per-rsid allele frequencies (global + subpops) into public.gnomad_by_rsid.

Notes:
- Input: bgz + .tbi gnomAD *sites* VCF (GRCh37), e.g. genomes v2.1.x.
- Filters: only rsIDs present in a given upload_id (like your ClinVar subset ingest).
- Matching: gnomAD v2 sites VCF typically does NOT define INFO/RS, so we match by VCF ID
  (which holds "rs..." and may contain multiple semicolon-separated IDs). If INFO/RS does
  exist in the header, we also match on it (numeric -> "rs{num}").
- Subpop tags handled across versions:
    Global: AF
    AFR/AMR/EAS/SAS: AF_AFR / AF_AMR / AF_EAS / AF_SAS
    EUR: AF_EUR if present, else max(AF_NFE, AF_FIN) if present
    POPMAX: POPMAX, AF_POPMAX when available
- Upsert in chunks (default 1000 rows).
"""

from __future__ import annotations

import os
import sys
import argparse
import datetime as dt
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple, Set

import pysam
import psycopg


# ---------- helpers ----------

def env_dsn() -> str:
    """Build a DSN from PG* env vars, error clearly if missing."""
    try:
        return (
            f"postgresql://{os.environ['PGUSER']}:{os.environ['PGPASSWORD']}"
            f"@{os.environ['PGHOST']}:{os.environ['PGPORT']}/{os.environ['PGDATABASE']}"
        )
    except KeyError as e:
        print(f"[gnomad] missing env var: {e}", file=sys.stderr)
        sys.exit(2)


def _to_float(x: Any) -> Optional[float]:
    if x is None:
        return None
    try:
        return float(x)
    except Exception:
        return None


def _first_or_max(v: Any) -> Optional[float]:
    """
    AF fields can be scalar or arrays (multi-allelic). For a site-level rsID,
    taking the max across ALT alleles is a reasonable proxy. If scalar, return scalar.
    """
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        vals = [ _to_float(x) for x in v ]
        vals = [ x for x in vals if x is not None ]
        return max(vals) if vals else None
    return _to_float(v)


def _get_info_any(rec: pysam.VariantRecord, keys: Sequence[str]) -> Any:
    """
    Try INFO fields case-sensitively first, then case-insensitively.
    Returns first match or None.
    """
    # exact
    for k in keys:
        if k in rec.info:
            return rec.info.get(k)
    # case-insensitive
    lower = { k.lower(): k for k in rec.info.keys() }
    for k in keys:
        lk = k.lower()
        if lk in lower:
            return rec.info.get(lower[lk])
    return None


def _extract_afs(rec: pysam.VariantRecord) -> Dict[str, Optional[float]]:
    """Extract AFs from a gnomAD record in a version-tolerant way."""
    # global
    af_global = _first_or_max(_get_info_any(rec, ["AF"]))

    # subpops (primary)
    afr = _first_or_max(_get_info_any(rec, ["AF_AFR"]))
    amr = _first_or_max(_get_info_any(rec, ["AF_AMR"]))
    eas = _first_or_max(_get_info_any(rec, ["AF_EAS"]))
    sas = _first_or_max(_get_info_any(rec, ["AF_SAS"]))
    eur = _first_or_max(_get_info_any(rec, ["AF_EUR"]))

    # v2 style splits: NFE/FIN (if AF_EUR absent)
    if eur is None:
        nfe = _first_or_max(_get_info_any(rec, ["AF_NFE"]))
        fin = _first_or_max(_get_info_any(rec, ["AF_FIN"]))
        eur = max([x for x in [nfe, fin] if x is not None], default=None)

    # popmax label + AF
    popmax = _get_info_any(rec, ["POPMAX"])
    if isinstance(popmax, (list, tuple)):
        popmax = popmax[0] if popmax else None
    popmax = None if popmax in (None, ".", "") else str(popmax)

    af_popmax = _first_or_max(_get_info_any(rec, ["AF_POPMAX"]))

    return {
        "af_global": af_global,
        "af_afr": afr,
        "af_amr": amr,
        "af_eas": eas,
        "af_eur": eur,
        "af_sas": sas,
        "af_popmax": af_popmax,
        "popmax": popmax,
    }


def _build_rs_sets(conn: psycopg.Connection, upload_id: int) -> Tuple[Set[str], Set[str]]:
    """Return (rs_full, rs_nums) for an upload's rsIDs: {'rs123', ...}, {'123', ...}."""
    rs_full: Set[str] = set()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT rsid
            FROM public.staging_array_calls
            WHERE upload_id = %s AND rsid ~ '^rs[0-9]+$'
        """, (upload_id,))
        for (r,) in cur.fetchall():
            rs_full.add(r)
    rs_nums = { r[2:] for r in rs_full }
    return rs_full, rs_nums


def _chunked(seq: Sequence[Tuple], n: int) -> Iterable[Sequence[Tuple]]:
    for i in range(0, len(seq), n):
        yield seq[i:i+n]


def _upsert_rows(conn: psycopg.Connection, rows: List[Tuple], page_size: int = 1000) -> None:
    """
    Chunked upsert using a single INSERT ... VALUES ... ON CONFLICT per chunk (psycopg3).
    """
    if not rows:
        return

    cols = (
        "rsid", "af_global", "af_afr", "af_amr", "af_eas", "af_eur", "af_sas",
        "af_popmax", "popmax", "version", "updated_at"
    )

    base_sql = f"""
    INSERT INTO public.gnomad_by_rsid ({", ".join(cols)})
    VALUES {{values}}
    ON CONFLICT (rsid) DO UPDATE
       SET af_global = EXCLUDED.af_global,
           af_afr    = EXCLUDED.af_afr,
           af_amr    = EXCLUDED.af_amr,
           af_eas    = EXCLUDED.af_eas,
           af_eur    = EXCLUDED.af_eur,
           af_sas    = EXCLUDED.af_sas,
           af_popmax = EXCLUDED.af_popmax,
           popmax    = COALESCE(EXCLUDED.popmax, public.gnomad_by_rsid.popmax),
           version   = COALESCE(EXCLUDED.version, public.gnomad_by_rsid.version),
           updated_at= EXCLUDED.updated_at
    """

    with conn.cursor() as cur:
        for chunk in _chunked(rows, page_size):
            placeholders = ", ".join(["(" + ",".join(["%s"] * len(cols)) + ")"] * len(chunk))
            flat: List[Any] = []
            for row in chunk:
                flat.extend(row)
            cur.execute(base_sql.format(values=placeholders), flat)
        conn.commit()


# ---------- main ----------

def main():
    ap = argparse.ArgumentParser(description="Ingest gnomAD AFs for rsIDs in an upload")
    ap.add_argument("--upload-id", type=int, default=int(os.environ.get("UPLOAD_ID", "0")),
                    help="limit to rsIDs present in this staging upload (required)")
    ap.add_argument("--vcf", default=os.environ.get("GNOMAD_VCF", ""),
                    help="path to gnomAD VCF (bgz + .tbi)")
    ap.add_argument("--version", default=os.environ.get("GNOMAD_VERSION", None),
                    help="optional source version string to store")
    ap.add_argument("--chunk", type=int, default=1000, help="upsert chunk size")
    ap.add_argument("--progress-every", type=int, default=10000, help="progress print interval")
    args = ap.parse_args()

    if not args.upload_id or not args.vcf:
        print("[gnomad] set --upload-id and --vcf (or env UPLOAD_ID / GNOMAD_VCF)", file=sys.stderr)
        sys.exit(2)

    dsn = env_dsn()
    now = dt.datetime.now(dt.timezone.utc)

    with psycopg.connect(dsn) as con:
        # Ensure table exists (no-op if already created elsewhere)
        with con.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS public.gnomad_by_rsid(
              rsid         text PRIMARY KEY,
              af_global    double precision,
              af_afr       double precision,
              af_amr       double precision,
              af_eas       double precision,
              af_eur       double precision,
              af_sas       double precision,
              af_popmax    double precision,
              popmax       text,
              version      text,
              updated_at   timestamptz
            )
            """)

        rs_full, rs_nums = _build_rs_sets(con, args.upload_id)
        print(f"[gnomad] upload={args.upload_id} vcf={args.vcf}")
        print(f"[gnomad] target rsids: {len(rs_full):,}")

    vf = pysam.VariantFile(args.vcf)
    header_has_rs = ("RS" in vf.header.info)  # ClinVar yes, gnomAD sites usually no

    rows: Dict[str, Tuple] = {}
    seen = matched_records = 0

    for rec in vf.fetch():
        seen += 1
        hit: Set[str] = set()

        # Match by VCF ID (may be "rs123" or "rs123;rs456" etc.)
        if rec.id:
            for tok in str(rec.id).replace(",", ";").split(";"):
                tok = tok.strip()
                if tok.startswith("rs") and tok in rs_full:
                    hit.add(tok)

        # Only touch INFO/RS if the header actually defines it (avoid pysam header error)
        if header_has_rs:
            try:
                rs_info = rec.info.get("RS")
            except Exception:
                rs_info = None
            if rs_info is not None:
                if isinstance(rs_info, (list, tuple)):
                    for v in rs_info:
                        s = str(v)
                        rs = "rs" + s if s.isdigit() else ("rs" + s.lstrip("rs"))
                        if rs in rs_full:
                            hit.add(rs)
                else:
                    s = str(rs_info)
                    rs = "rs" + s if s.isdigit() else ("rs" + s.lstrip("rs"))
                    if rs in rs_full:
                        hit.add(rs)

        if not hit:
            if args.progress_every and seen % args.progress_every == 0:
                print(f"[gnomad] scanned {seen:,} (matched records {matched_records:,})")
            continue

        afs = _extract_afs(rec)
        for rs in hit:
            rows[rs] = (
                rs,
                afs["af_global"],
                afs["af_afr"],
                afs["af_amr"],
                afs["af_eas"],
                afs["af_eur"],
                afs["af_sas"],
                afs["af_popmax"],
                afs["popmax"],
                args.version,
                now,
            )
        matched_records += 1

    print(f"[gnomad] matched records: {matched_records:,}; unique rsids to upsert: {len(rows):,}")
    if not rows:
        print("[gnomad] nothing to upsert; exiting")
        return

    # Upsert
    all_rows = list(rows.values())
    total = len(all_rows)
    with psycopg.connect(dsn) as con:
        for i, chunk in enumerate(_chunked(all_rows, args.chunk), start=1):
            _upsert_rows(con, list(chunk), page_size=args.chunk)
            done = min(i * args.chunk, total)
            print(f"[gnomad] upserted {done}/{total}")

    print("[gnomad] upsert complete")


if __name__ == "__main__":
    main()
