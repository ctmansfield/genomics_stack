from __future__ import annotations

import base64
import hashlib
import hmac
import os
import pathlib

import psycopg
from fastapi import FastAPI, HTTPException

PGHOST = os.getenv("PGHOST", "db")
PGPORT = int(os.getenv("PGPORT", "5432"))
PGUSER = os.getenv("PGUSER", "genouser")
PGPASSWORD = os.getenv("PGPASSWORD", "")
PGDATABASE = os.getenv("PGDATABASE", "genomics")
DATA_DIR = pathlib.Path(os.getenv("DATA_DIR", "/data"))
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", "2147483648"))  # 2GB
GLOBAL_UPLOAD_TOKEN = os.getenv("UPLOAD_TOKEN", "")  # optional
TOKEN_SECRET = os.getenv("TOKEN_SECRET", "")  # required for email tokens

app = FastAPI()


def b64u(s: bytes) -> str:
    return base64.urlsafe_b64encode(s).decode().rstrip("=")


def b64u_dec(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def norm_email(e: str) -> str:
    return e.strip().lower()


def issue_token(email: str) -> str:
    if not TOKEN_SECRET:
        raise HTTPException(500, "TOKEN_SECRET not configured")
    e = norm_email(email).encode()
    mac = hmac.new(TOKEN_SECRET.encode(), e, hashlib.sha256).digest()
    return f"{b64u(e)}.{b64u(mac)}"


def verify_token(token: str) -> str | None:
    try:
        email_b64, mac_b64 = token.split(".", 1)
        e = b64u_dec(email_b64)
        mac = b64u_dec(mac_b64)
        if not TOKEN_SECRET:
            return None
        good = hmac.new(TOKEN_SECRET.encode(), e, hashlib.sha256).digest()
        if hmac.compare_digest(mac, good):
            return e.decode()
    except Exception:
        return None
    return None


def get_con():
    """
    Build a robust connection string:
    - Prefer PG_DSN if set.
    - Else compose from PG* vars (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD).
    - Else fall back to localhost:55432 with common defaults.
    Also avoid DNS for "postgres" by normalizing to 127.0.0.1 when requested.
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

    # Normalize "host=postgres" -> "host=127.0.0.1" if desired (default on)
    if "host=postgres" in dsn and os.getenv("RESOLVE_POSTGRES_LOCAL", "1") == "1":
        dsn = dsn.replace("host=postgres", "host=127.0.0.1")

    # psycopg v3 connect with short timeout & app name
    return psycopg.connect(dsn, application_name="ingest_api", connect_timeout=5)
