import os, pathlib, hashlib
import duckdb

DB_PATH = os.environ.get("DUCKDB_PATH", "/mnt/nas_storage/duckdb/genomics.duckdb")
pathlib.Path(os.path.dirname(DB_PATH)).mkdir(parents=True, exist_ok=True)

def conn():
    con = duckdb.connect(DB_PATH)
    # Some DuckDB builds don't accept 'threads=auto'; use a safe fallback.
    try:
        # Prefer explicit integer threads for maximum compatibility
        n = max(1, (os.cpu_count() or 1))
        con.execute(f"PRAGMA threads={n};")
    except Exception:
        # As a last resort, ignore if PRAGMA is unsupported
        pass
    return con

def bootstrap(sql_path: str):
    with conn() as con, open(sql_path, "r", encoding="utf-8") as f:
        con.execute(f.read())

def schema_hash():
    with conn() as con:
        rows = con.execute("""
            SELECT table_schema, table_name, column_name, data_type
            FROM information_schema.columns
            ORDER BY 1,2,3
        """).fetchall()
    m = hashlib.sha256()
    for r in rows:
        m.update(("|".join(map(str, r)) + "\n").encode())
    return m.hexdigest()[:8]
