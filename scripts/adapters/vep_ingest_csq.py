#!/usr/bin/env python3
"""
Ingest VEP CSQ annotations into public.vep_by_rsid for rsIDs present in a given upload.

Assumptions:
- Input VCF is your VEP-annotated sites VCF (one ALT per site) created from the upload.
- VEP provides INFO/CSQ; we DO NOT use INFO/RS (VEP output often lacks it).
- We match variants by VCF ID (e.g., 'rs1801133').

Writes (upsert):
  public.vep_by_rsid(
      rsid text,
      gene_symbol text,
      consequence text,
      impact text,
      transcript text,
      sift_pred text,
      polyphen_pred text,
      biotype text,
      canonical boolean,
      mane text,
      source_version text,
      updated_at timestamptz,
      PRIMARY KEY (rsid, gene_symbol, transcript, consequence)
  )
"""

import os
import sys
import argparse
import datetime as dt
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple, Set

import pysam
import psycopg


# ------------- small helpers ------------- #

def parse_csq_header(vf: pysam.VariantFile) -> List[str]:
    """Return the CSQ field order from the header."""
    if "CSQ" not in vf.header.info:
        raise RuntimeError("VEP CSQ header not found in VCF.")
    desc = vf.header.info["CSQ"].description or ""
    # Description contains: 'Consequence annotations ... Format: Allele|Consequence|...'
    anchor = "Format:"
    i = desc.find(anchor)
    if i == -1:
        # Some builds quote it or vary spacing
        for token in ("format:", "FORMAT:"):
            j = desc.find(token)
            if j != -1:
                i = j
                break
    if i == -1:
        raise RuntimeError(f"Cannot parse CSQ header description: {desc}")
    fmt = desc[i+len(anchor):].strip().strip('"').strip()
    # split on '|' and strip whitespace
    fields = [f.strip() for f in fmt.split("|")]
    return fields


def csq_entries(rec: pysam.VariantRecord) -> Iterable[str]:
    """Yield raw CSQ strings for a record (can be 0..N)."""
    if "CSQ" not in rec.info:
        return []
    v = rec.info["CSQ"]
    # pysam returns tuple-of-str for INFO with Number='.'
    if isinstance(v, (tuple, list)):
        return v
    # some builds could be a single string
    return [str(v)]


def _pred_label(val: Optional[str]) -> Optional[str]:
    """
    Convert 'deleterious(0.02)' -> 'deleterious', 'probably_damaging(0.95)' -> 'probably_damaging'
    """
    if not val:
        return None
    s = str(val)
    p = s.find("(")
    return s if p == -1 else s[:p]


def chunked(seq: Sequence[Tuple], n: int) -> Iterable[Sequence[Tuple]]:
    for i in range(0, len(seq), n):
        yield seq[i:i+n]


def build_rsid_set(conn: psycopg.Connection, upload_id: int) -> Set[str]:
    rsids: Set[str] = set()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT rsid
            FROM public.staging_array_calls
            WHERE upload_id = %s AND rsid ~ '^rs[0-9]+$'
        """, (upload_id,))
        for (r,) in cur.fetchall():
            rsids.add(r)
    return rsids


def ensure_table(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        cur.execute("""
        CREATE TABLE IF NOT EXISTS public.vep_by_rsid(
          rsid            text,
          gene_symbol     text,
          consequence     text,
          impact          text,
          transcript      text,
          sift_pred       text,
          polyphen_pred   text,
          biotype         text,
          canonical       boolean,
          mane            text,
          source_version  text,
          updated_at      timestamptz,
          PRIMARY KEY (rsid, gene_symbol, transcript, consequence)
        )
        """)
    conn.commit()


def upsert_rows(conn: psycopg.Connection, rows: List[Tuple], page_size: int = 1000) -> None:
    if not rows:
        return
    cols = (
        "rsid", "gene_symbol", "consequence", "impact", "transcript",
        "sift_pred", "polyphen_pred", "biotype", "canonical", "mane",
        "source_version", "updated_at"
    )
    sql = f"""
    INSERT INTO public.vep_by_rsid ({", ".join(cols)})
    VALUES {{values}}
    ON CONFLICT (rsid, gene_symbol, transcript, consequence) DO UPDATE
      SET impact         = EXCLUDED.impact,
          sift_pred      = COALESCE(EXCLUDED.sift_pred, public.vep_by_rsid.sift_pred),
          polyphen_pred  = COALESCE(EXCLUDED.polyphen_pred, public.vep_by_rsid.polyphen_pred),
          biotype        = COALESCE(EXCLUDED.biotype, public.vep_by_rsid.biotype),
          canonical      = COALESCE(EXCLUDED.canonical, public.vep_by_rsid.canonical),
          mane           = COALESCE(EXCLUDED.mane, public.vep_by_rsid.mane),
          source_version = COALESCE(EXCLUDED.source_version, public.vep_by_rsid.source_version),
          updated_at     = EXCLUDED.updated_at
    """
    with conn.cursor() as cur:
        for chunk in chunked(rows, page_size):
            ph = ", ".join(["(" + ",".join(["%s"] * len(cols)) + ")"] * len(chunk))
            flat: List[Any] = []
            for r in chunk: flat.extend(r)
            cur.execute(sql.format(values=ph), flat)
    conn.commit()


# ------------- main ------------- #

def main():
    ap = argparse.ArgumentParser(description="Ingest VEP CSQ for rsIDs in an upload")
    ap.add_argument("--upload-id", type=int, default=int(os.environ.get("UPLOAD_ID", "0")),
                    help="limit to rsIDs present in this upload (required)")
    ap.add_argument("--vcf", default=os.environ.get("VEP_VCF", ""),
                    help="path to VEP-annotated VCF.bgz")
    ap.add_argument("--version", default=os.environ.get("VEP_VERSION", None),
                    help="optional VEP/cache version string to store")
    ap.add_argument("--chunk", type=int, default=2000, help="upsert chunk size")
    ap.add_argument("--progress-every", type=int, default=20000, help="progress print interval")
    args = ap.parse_args()

    if not args.upload_id or not args.vcf:
        print("[vep] set --upload-id and --vcf (or env UPLOAD_ID / VEP_VCF)", file=sys.stderr)
        sys.exit(2)

    # Use libpq env (PG*); don't bake DSN here
    now = dt.datetime.now(dt.timezone.utc)

    with psycopg.connect() as con:
        rs_full = build_rsid_set(con, args.upload_id)
        print(f"[vep] upload={args.upload_id} vcf={args.vcf}")
        print(f"[vep] target rsids: {len(rs_full):,}")
        ensure_table(con)

    vf = pysam.VariantFile(args.vcf)
    fields = parse_csq_header(vf)

    # Fast index of field positions we care about
    def idx(name: str) -> Optional[int]:
        try:
            return fields.index(name)
        except ValueError:
            return None

    ix_SYMBOL     = idx("SYMBOL")
    ix_Conseq     = idx("Consequence")
    ix_IMPACT     = idx("IMPACT")
    ix_Feature    = idx("Feature")        # transcript ID
    ix_BIOTYPE    = idx("BIOTYPE")
    ix_SIFT       = idx("SIFT")
    ix_PolyPhen   = idx("PolyPhen")
    ix_CANONICAL  = idx("CANONICAL")
    ix_MANE       = idx("MANE")  # composite; okay to store raw

    seen = 0
    matched = 0
    out_rows: Dict[Tuple[str, str, str, str], Tuple] = {}

    for rec in vf.fetch():
        seen += 1

        rid = rec.id or ""
        if not rid.startswith("rs"):
            continue
        if rid not in rs_full:
            continue

        # Iterate CSQ entries
        for raw in csq_entries(rec):
            toks = raw.split("|")
            # pad/truncate defensively
            if len(toks) < len(fields):
                toks += [""] * (len(fields) - len(toks))
            elif len(toks) > len(fields):
                toks = toks[:len(fields)]

            symbol     = (toks[ix_SYMBOL] if ix_SYMBOL is not None else "") or None
            consequence= (toks[ix_Conseq] if ix_Conseq is not None else "") or None
            impact     = (toks[ix_IMPACT] if ix_IMPACT is not None else "") or None
            transcript = (toks[ix_Feature] if ix_Feature is not None else "") or None
            biotype    = (toks[ix_BIOTYPE] if ix_BIOTYPE is not None else "") or None
            sift_raw   = (toks[ix_SIFT] if ix_SIFT is not None else "") or None
            poly_raw   = (toks[ix_PolyPhen] if ix_PolyPhen is not None else "") or None
            canonical  = (toks[ix_CANONICAL] if ix_CANONICAL is not None else "")
            mane       = (toks[ix_MANE] if ix_MANE is not None else "") or None

            if not symbol or not consequence:
                continue

            key = (rid, symbol, transcript or "", consequence)
            # Keep the "strongest" by impact rank if duplicates collide on PK key
            # Rank: HIGH > MODERATE > LOW > MODIFIER > else
            def impact_rank(s: Optional[str]) -> int:
                s = (s or "").upper()
                return {"HIGH": 4, "MODERATE": 3, "LOW": 2, "MODIFIER": 1}.get(s, 0)

            cand = (
                rid,
                symbol,
                consequence,
                impact,
                (transcript or ""),
                _pred_label(sift_raw),
                _pred_label(poly_raw),
                biotype,
                (canonical.upper() == "YES") if canonical else None,
                mane,
                args.version,
                now,
            )

            if key not in out_rows:
                out_rows[key] = cand
            else:
                # replace if new one has higher impact rank
                _, _, _, old_impact, *_ = out_rows[key]
                if impact_rank(impact) > impact_rank(old_impact):
                    out_rows[key] = cand

        matched += 1
        if args.progress_every and (seen % args.progress_every == 0):
            print(f"[vep] scanned {seen:,} (matched {matched:,})")

    rows = list(out_rows.values())
    print(f"[vep] matched sites: {matched:,}; upserting rows: {len(rows):,}")
    if not rows:
        print("[vep] nothing to upsert; exiting")
        return

    with psycopg.connect() as con:
        upsert_rows(con, rows, page_size=args.chunk)

    print("[vep] upsert complete")


if __name__ == "__main__":
    main()
