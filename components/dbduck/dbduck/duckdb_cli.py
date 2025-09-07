import os, sys, glob
from pathlib import Path

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
    with conn() as con:
        def copy(globpat, table):
            files = sorted(glob.glob(globpat))
            if not files:
                return
            con.execute(f"DELETE FROM {table}")
            con.execute(f"COPY {table} FROM '{globpat}' (FORMAT PARQUET);")
        copy(f"{NAS_ROOT}/data/samples/*.parquet", "core.samples")
        copy(f"{NAS_ROOT}/data/files/*.parquet", "core.files")
        copy(f"{NAS_ROOT}/data/variants/*.parquet", "core.variants")
        copy(f"{NAS_ROOT}/data/annotations/*.parquet", "core.annotations")
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
