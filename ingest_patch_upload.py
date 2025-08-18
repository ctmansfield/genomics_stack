import csv
import hashlib
import io
import os
import pathlib
import re
from typing import Iterable, Optional, Tuple

import psycopg
from fastapi import APIRouter, File, HTTPException, UploadFile
from psycopg.rows import dict_row

router = APIRouter()


def _dsn() -> str:
    # Map compose-provided vars to psycopg keywords
    host = os.getenv("PGHOST", "db")
    port = os.getenv("PGPORT", "5432")
    db = os.getenv("POSTGRES_DB") or os.getenv("PGDATABASE", "genomics")
    user = os.getenv("POSTGRES_USER") or os.getenv("PGUSER", "genouser")
    pwd = os.getenv("POSTGRES_PASSWORD") or os.getenv("PGPASSWORD", "")
    return f"host={host} port={port} dbname={db} user={user} password={pwd}"


def _parse_array_stream(lines: Iterable[str]) -> Iterable[Tuple[str, str, str]]:
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
        rsid, genotype = parts[0], parts[3]
        if genotype in {"--", "00", "NN"}:
            a1, a2 = "N", "N"
        elif len(genotype) == 2:
            a1, a2 = genotype[0], genotype[1]
        elif len(genotype) == 1:
            a1, a2 = genotype, genotype
        else:
            continue
        yield rsid, a1, a2


def _stage_calls(
    conn: psycopg.Connection, upload_id: int, rows: Iterable[Tuple[str, str, str]]
) -> int:
    with conn.cursor() as cur:
        cur.execute("SET search_path TO public, genomics")
        # wipe existing rows for this upload
        cur.execute("DELETE FROM public.staging_array_calls WHERE upload_id = %s", (upload_id,))
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["upload_id", "sample_label", "rsid", "allele1", "allele2"])
        count = 0
        for rsid, a1, a2 in rows:
            w.writerow([upload_id, f"Sample_{upload_id}", rsid, a1, a2])
            count += 1
        buf.seek(0)
        with cur.copy(
            "COPY public.staging_array_calls (upload_id,sample_label,rsid,allele1,allele2) FROM STDIN WITH (FORMAT csv, HEADER true)"
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


@router.get("/healthz")
def healthz():
    return {"ok": True}


@router.post("/upload")
async def upload(file: UploadFile = File(...)):
    try:
        raw_bytes = await file.read()
        sha = hashlib.sha256(raw_bytes).hexdigest()
        # tolerate any encoding; preserve bytes as text best-effort
        text = raw_bytes.decode("utf-8", errors="ignore")

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

            staged = _stage_calls(conn, upload_id, _parse_array_stream(text.splitlines()))
        return {"ok": True, "upload_id": upload_id, "staged_rows": staged}
    except Exception as e:
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
