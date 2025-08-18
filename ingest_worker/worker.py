import os
import pathlib

import psycopg

PGHOST = os.getenv("PGHOST", "db")
PGPORT = int(os.getenv("PGPORT", "5432"))
PGUSER = os.getenv("PGUSER", "genouser")
PGPASSWORD = os.getenv("PGPASSWORD", "")
PGDATABASE = os.getenv("PGDATABASE", "genomics")
DATA_DIR = pathlib.Path(os.getenv("DATA_DIR", "/data"))
POLL_SEC = float(os.getenv("POLL_SEC", "3"))

DDL = """
create table if not exists staging_array_calls(
  id bigserial primary key,
  upload_id bigint references uploads(id) on delete cascade,
  sample_label text,
  rsid text,
  chrom text,
  pos integer,
  allele1 text,
  allele2 text,
  genotype text,
  raw_line text,
  created_at timestamptz default now()
);
create index if not exists staging_array_calls_upload_id on staging_array_calls(upload_id);
create index if not exists staging_array_calls_rsid on staging_array_calls(rsid);
"""


def get_con():
    """
    Prefer PG_DSN; else compose from PG* vars; else fallback to 127.0.0.1:55432.
    Normalize 'host=postgres' -> 'host=127.0.0.1' when RESOLVE_POSTGRES_LOCAL=1.
    """
    dsn = os.environ.get("PG_DSN")
    if not dsn:
        host = os.environ.get("PGHOST", "127.0.0.1")
        port = os.environ.get("PGPORT", "55432")
        db = os.environ.get("PGDATABASE", os.environ.get("POSTGRES_DB", "genomics"))
        usr = os.environ.get("PGUSER", os.environ.get("POSTGRES_USER", "postgres"))
        pwd = os.environ.get("PGPASSWORD", os.environ.get("POSTGRES_PASSWORD", "genomics"))
        parts = [f"host={host}", f"port={port}", f"dbname={db}", f"user={usr}"]
        if pwd:
            parts.append(f"password={pwd}")
        dsn = " ".join(parts)
    if "host=postgres" in dsn and os.getenv("RESOLVE_POSTGRES_LOCAL", "1") == "1":
        dsn = dsn.replace("host=postgres", "host=127.0.0.1")
    return psycopg.connect(dsn, application_name="ingest_worker", connect_timeout=5)
