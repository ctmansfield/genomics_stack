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
    files_loaded = samples_loaded = variants_loaded = annotations_loaded = 0

    with conn() as con:
        # 1) load files from manifest (if present)
        man_count = con.execute(f"SELECT COALESCE(SUM(rows),0) FROM (SELECT COUNT(*) AS rows FROM read_parquet('{manifest_glob}') )").fetchone()[0]
        if man_count > 0:
            con.execute("DELETE FROM core.files")
            con.execute(f"""
                INSERT INTO core.files (sample_id, path, md5, size_bytes, created_at)
                SELECT sample_id, path, md5, size_bytes, now()
                FROM read_parquet('{manifest_glob}');
            """)
            files_loaded = con.execute("SELECT COUNT(*) FROM core.files").fetchone()[0]

            con.execute("DELETE FROM core.samples")
            con.execute("""
                INSERT INTO core.samples (sample_id, subject_id, created_at)
                SELECT DISTINCT sample_id, NULL, now()
                FROM core.files;
            """)
            samples_loaded = con.execute("SELECT COUNT(*) FROM core.samples").fetchone()[0]

        # 2) optional legacy hydrators
        def copy_glob(globpat, table):
            nonlocal variants_loaded, annotations_loaded
            # count before delete to decide if we’ll load
            cnt = con.execute(f"SELECT COUNT(*) FROM glob('{globpat}')").fetchone()[0]
            if cnt == 0:
                return
            con.execute(f"DELETE FROM {table}")
            con.execute(f"COPY {table} FROM '{globpat}' (FORMAT PARQUET);")
            if table == "core.variants":
                variants_loaded = con.execute("SELECT COUNT(*) FROM core.variants").fetchone()[0]
            elif table == "core.annotations":
                annotations_loaded = con.execute("SELECT COUNT(*) FROM core.annotations").fetchone()[0]

        copy_glob(f"{NAS_ROOT}/data/variants/*.parquet", "core.variants")
        copy_glob(f"{NAS_ROOT}/data/annotations/*.parquet", "core.annotations")

    print(f"hydrate_stats: files={files_loaded} samples={samples_loaded} variants={variants_loaded} annotations={annotations_loaded}")
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
