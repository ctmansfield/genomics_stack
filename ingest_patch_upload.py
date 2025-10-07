import argparse
import csv
import hashlib
import io
import logging
import os
import pathlib
import re
import sys
from itertools import islice
from typing import Iterable, Optional, Tuple

import psycopg
from fastapi import APIRouter, File, HTTPException, UploadFile
from psycopg.rows import dict_row

# Initialize logging
logging.basicConfig(level=logging.INFO)

router = APIRouter()


def _dsn() -> str:
    # Map compose-provided vars to psycopg keywords
    host = os.getenv("PGHOST", "db")
    port = os.getenv("PGPORT", "5432")
    db = os.getenv("POSTGRES_DB") or os.getenv("PGDATABASE", "genomics")
    user = os.getenv("POSTGRES_USER") or os.getenv("PGUSER", "genouser")
    pwd = os.getenv("POSTGRES_PASSWORD") or os.getenv("PGPASSWORD", "")
    return f"host={host} port={port} dbname={db} user={user} password={pwd}"


def _parse_array_stream(lines: Iterable[str]) -> Iterable[Tuple[str, str, str, str]]:
    """
    Yield rows as (rsid, allele1, allele2, genotype)
    Supports formats:
      - AncestryDNA: rsid,chrom,pos,allele1,allele2 (tab/space delimited)
      - 23andMe-like: rsid,chrom,pos,genotype (AG/TT/etc)
    Lines starting with # are ignored.
    """
    for raw in lines:
        if not raw or raw.startswith("#"):
            continue
        line = raw.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            parts = re.split(r"\s+", line)
            if len(parts) < 4:
                continue
        rsid = parts[0].strip()
        # Skip header row if present
        if rsid.lower() == "rsid":
            continue
        a1 = a2 = genotype = ""
        try:
            if len(parts) >= 5:
                # AncestryDNA: allele1, allele2 are columns 3,4 (0-based)
                a1 = (parts[3] or "").strip().upper() or "N"
                a2 = (parts[4] or "").strip().upper() or "N"
                genotype = f"{a1}{a2}" if a1 and a2 else "NN"
            else:
                # 4 columns: rsid, chrom, pos, genotype
                g = (parts[3] or "").strip().upper()
                if g in {"--", "00", "NN"} or g == "":
                    a1, a2, genotype = "N", "N", "NN"
                elif len(g) >= 2:
                    a1, a2 = g[0], g[1]
                    genotype = f"{a1}{a2}"
                elif len(g) == 1:
                    a1, a2 = g, g
                    genotype = f"{a1}{a2}"
                else:
                    continue
        except Exception:
            continue
        if not rsid:
            continue
        yield rsid, a1, a2, genotype


def _stage_calls(
    conn: psycopg.Connection, upload_id: int, rows: Iterable[Tuple[str, str, str, str]]
) -> int:
    with conn.cursor() as cur:
        cur.execute("SET search_path TO public, genomics")
        # wipe existing rows for this upload
        cur.execute("DELETE FROM public.staging_array_calls WHERE upload_id = %s", (upload_id,))
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["upload_id", "sample_label", "rsid", "allele1", "allele2", "genotype"])
        count = 0
        for rsid, a1, a2, gt in rows:
            w.writerow([upload_id, f"Sample_{upload_id}", rsid, a1, a2, gt])
            count += 1
        buf.seek(0)
        with cur.copy(
            "COPY public.staging_array_calls (upload_id,sample_label,rsid,allele1,allele2,genotype) FROM STDIN WITH (FORMAT csv, HEADER true)"
        ) as cp:
            cp.write(buf.read())
    return count


def _get_or_create_upload(conn: psycopg.Connection, sha: str, marker_path: str) -> int:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SET search_path TO public, genomics")
        cur.execute("SELECT id FROM public.uploads WHERE sha256 = %s LIMIT 1", (sha,))
        row = cur.fetchone()
        if row:
            upload_id = row["id"]
            cur.execute(
                "UPDATE public.uploads SET stored_path = %s, updated_at = now() WHERE id = %s",
                (marker_path, upload_id),
            )
            return upload_id
        # insert only sha256/stored_path; do NOT touch email/email_norm
        cur.execute(
            "INSERT INTO public.uploads (sha256, stored_path) VALUES (%s,%s) RETURNING id",
            (sha, marker_path),
        )
        return cur.fetchone()["id"]


# New helper functions
def parse_clnrevstat(clnrevstat: str) -> int:
    if not clnrevstat:
        return 0
    clnrevstat_mapping = {
        "no review": 0,
        "reviewed by: expert": 1,
        "reviewed by: curator": 2,
        "reviewed by: clinician": 3,
        "reviewed by: expert and curator": 4,
    }
    return clnrevstat_mapping.get(clnrevstat.lower(), 0)


def normalize_clnsig(clnsig: str) -> str:
    if not clnsig:
        return ""
    clnsig_cleaned = re.sub(r"[\s,]+", ", ", clnsig).strip().lower()
    return clnsig_cleaned


@router.get("/healthz")
def healthz():
    return {"ok": True}


# Modified upload handler to support dry_run and rsid-only filtering
@router.post("/upload")
async def upload(
    file: UploadFile = File(...),
    dry_run: bool = False,
    rsid_file: Optional[str] = None,
):
    try:
        raw_bytes = await file.read()
        sha = hashlib.sha256(raw_bytes).hexdigest()
        # tolerate any encoding; preserve bytes as text best-effort
        text = raw_bytes.decode("utf-8", errors="ignore")

        # Prepare parsed rows generator
        rows_gen = _parse_array_stream(text.splitlines())

        # Optional RSID-only filtering
        rsid_list = None
        if rsid_file:
            try:
                with open(rsid_file, "r", encoding="utf-8") as f:
                    rsid_list = [line.strip() for line in f if line.strip()]
                rsid_set = set(rsid_list)
                rows_gen = (t for t in rows_gen if t and t[0] in rsid_set)
            except Exception as e:
                logging.error(f"Failed to read rsid_file '{rsid_file}': {e}")
                raise HTTPException(status_code=400, detail=f"invalid rsid_file: {e}")

        if dry_run:
            preview = list(islice(rows_gen, 20))
            logging.info(f"Dry run: showing first {len(preview)} tuples")
            return {
                "dry_run": True,
                "sha256": sha,
                "rsid_filter_count": len(rsid_list) if rsid_list else None,
                "first_20_tuples": preview,
            }

        # Normal ingest path
        with psycopg.connect(_dsn()) as conn:
            conn.execute("SET search_path TO public, genomics")
            marker = f"db://uploads/{sha}"
            upload_id = _get_or_create_upload(conn, sha, marker)
            # upsert blob
            conn.execute(
                """
                INSERT INTO public.upload_blobs (upload_id, sha256, content)
                VALUES (%s,%s,%s)
                ON CONFLICT (upload_id) DO UPDATE
                  SET content = EXCLUDED.content, sha256 = EXCLUDED.sha256
            """,
                (upload_id, sha, text),
            )

            staged = _stage_calls(conn, upload_id, rows_gen)
        return {
            "ok": True,
            "upload_id": upload_id,
            "staged_rows": staged,
            "rsid_filter_count": len(rsid_list) if rsid_list else None,
        }
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Upload failed due to: {e}")
        raise HTTPException(status_code=400, detail=f"upload failed: {e}")


@router.post("/reingest/{upload_id}")
def reingest(upload_id: int):
    try:
        with psycopg.connect(_dsn()) as conn:
            conn.execute("SET search_path TO public, genomics")
            # prefer DB blob
            row = conn.execute(
                "SELECT u.stored_path, b.content FROM public.uploads u LEFT JOIN public.upload_blobs b ON b.upload_id=u.id WHERE u.id=%s",
                (upload_id,),
            ).fetchone()
            if not row:
                raise ValueError(f"upload {upload_id} not found")
            stored_path, content = row[0], row[1]

            text: Optional[str] = None
            if content:
                text = content
            elif stored_path and not stored_path.startswith("db://"):
                # fallback: try filesystem if previous uploads used files
                p = pathlib.Path(stored_path)
                if not p.exists():
                    # in older flows the file lived inside the container; try to read anyway
                    with open(stored_path, "r", encoding="utf-8", errors="ignore") as fh:
                        text = fh.read()
                else:
                    text = p.read_text(encoding="utf-8", errors="ignore")
            else:
                raise ValueError("no source content available for reingest")

            staged = _stage_calls(conn, upload_id, _parse_array_stream(text.splitlines()))
        return {"ok": True, "upload_id": upload_id, "restaged_rows": staged}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"reingest failed: {e}")


# Optional CLI support for dry-run parsing outside FastAPI
if __name__ == "__main__":
    # Test the helper functions
    test_clnrevstat = [
        "no review",
        "Reviewed by: expert",
        "REVIEWED BY: CURATOR",
        "Reviewed by: clinician",
        "Reviewed by: expert and curator",
        None,
    ]
    print("CLNREVSTAT Tests:")
    for stat in test_clnrevstat:
        stars = parse_clnrevstat(stat)
        print(f"'{stat}' -> {stars} stars")

    test_clnsig = ["pathogenic, likely pathogenic", "pAthOgEnIC,  likELy pathOgEnIC", None]
    print("\nCLNSIG Normalization Tests:")
    for sig in test_clnsig:
        normalized = normalize_clnsig(sig)
        print(f"'{sig}' -> '{normalized}'")

    # The main execution logic can remain below this line
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print parsed tuples without writing to the DB",
    )
    parser.add_argument(
        "--rsid-only",
        type=str,
        help="File containing list of RSIDs to backfill",
    )
    args = parser.parse_args()

    if args.dry_run:
        input_text = sys.stdin.read()
        gen = _parse_array_stream(input_text.splitlines())
        if args.rsid_only:
            with open(args.rsid_only, "r", encoding="utf-8") as f:
                rsids = set(line.strip() for line in f if line.strip())
            gen = (t for t in gen if t and t[0] in rsids)
        preview = list(islice(gen, 20))
        logging.info(f"Dry run preview ({len(preview)} rows):")
        for row in preview:
            print(row)
    else:
        logging.info("This module is intended to be served via FastAPI (uvicorn).")

