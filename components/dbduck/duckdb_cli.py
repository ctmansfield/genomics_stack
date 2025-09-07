import os, sys, glob
from pathlib import Path
import duckdb

# allow "from components..." imports when run directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))
from components.dbduck.duck import conn, bootstrap

NAS_ROOT = os.environ.get("NAS_ROOT", "/mnt/nas_storage")
REPO_ROOT = os.environ.get("REPO_ROOT", "/mnt/nas_storage/repos/genomics-stack")
DB = os.environ.get("DUCKDB_PATH", "/mnt/nas_storage/duckdb/genomics.duckdb")

def do_bootstrap():
    bootstrap(os.path.join(REPO_ROOT, "components/dbduck/bootstrap.sql"))
    print("bootstrap_ok")

def hydrate():
    Path(os.path.dirname(DB)).mkdir(parents=True, exist_ok=True)

    # ensure schema exists (idempotent)
    try:
        with conn() as con:
            con.execute("SELECT 1 FROM core.samples LIMIT 1")
    except Exception:
        do_bootstrap()

    manifest_glob = f"{NAS_ROOT}/data/staging/*/staging_manifest.parquet"

    with conn() as con:
        # 1) load files from manifest (if present)
        man_files = sorted(glob.glob(manifest_glob))
        if man_files:
            con.execute("DELETE FROM core.files")
            # Map columns explicitly: manifest has an extra 'ts' column that we ignore
            con.execute(f"""
                INSERT INTO core.files (sample_id, path, md5, size_bytes, created_at)
                SELECT sample_id, path, md5, size_bytes, now()
                FROM read_parquet('{manifest_glob}');
            """)
            # derive samples from files if samples are empty or you prefer full refresh
            con.execute("DELETE FROM core.samples")
            con.execute("""
                INSERT INTO core.samples (sample_id, subject_id, created_at)
                SELECT DISTINCT sample_id, NULL, now()
                FROM core.files;
            """)

        # 2) optional legacy hydrators (no-op if dirs are empty)
        def copy_glob(globpat, table):
            files = sorted(glob.glob(globpat))
            if not files:
                return
            con.execute(f"DELETE FROM {table}")
            con.execute(f"COPY {table} FROM '{globpat}' (FORMAT PARQUET);")

        copy_glob(f"{NAS_ROOT}/data/variants/*.parquet", "core.variants")
        copy_glob(f"{NAS_ROOT}/data/annotations/*.parquet", "core.annotations")

    print("hydrate_ok")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "bootstrap":
        do_bootstrap()
    elif cmd == "hydrate-from-parquet":
        hydrate()
    elif cmd == "refresh-views":
        print("refresh_ok")
    else:
        print("usage: bootstrap | hydrate-from-parquet | refresh-views")
        sys.exit(2)
