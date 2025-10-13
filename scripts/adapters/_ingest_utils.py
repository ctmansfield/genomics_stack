#!/usr/bin/env python3
import os, sys, csv, time, argparse, subprocess, tempfile, itertools
from typing import Iterable, List, Tuple
import psycopg

def get_pgurl_from_env() -> str:
    # PGURL convenience var preferred; fall back to discrete vars if needed
    pgurl = os.environ.get("PGURL")
    if pgurl:
        return pgurl
    # fallback (expects PGPASSWORD already in env per your convention)
    user = os.environ["PGUSER"]
    pwd  = os.environ["PGPASSWORD"]
    host = os.environ.get("PGHOST","localhost")
    port = os.environ.get("PGPORT","5432")
    db   = os.environ["PGDATABASE"]
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"

def chunked(iterable: Iterable, n: int):
    it = iter(iterable)
    while True:
        chunk = list(itertools.islice(it, n))
        if not chunk:
            break
        yield chunk

def ensure_dir(p: str):
    os.makedirs(p, exist_ok=True)

def run(cmd: List[str]):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return proc.returncode, proc.stdout, proc.stderr

def write_csv_sample(path: str, header: List[str], rows: List[Tuple], limit: int = 100):
    ensure_dir(os.path.dirname(path))
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        for r in rows[:limit]:
            w.writerow(r)
