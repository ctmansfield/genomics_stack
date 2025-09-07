#!/usr/bin/env python3
import os, sys, hashlib, time
from pathlib import Path
import duckdb
from datetime import datetime

NAS_ROOT = os.environ.get("NAS_ROOT", "/mnt/nas_storage")
INPUT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(f"{NAS_ROOT}/data/samples_raw")
DATE = datetime.now().strftime("%Y%m%d")
OUT_DIR = Path(f"{NAS_ROOT}/data/staging/{DATE}")
OUT_DIR.mkdir(parents=True, exist_ok=True)
TMP_TSV = OUT_DIR / "manifest_tmp.tsv"
OUT_PARQUET = OUT_DIR / "staging_manifest.parquet"

def file_md5(p: Path, buf=1024*1024):
    m = hashlib.md5()
    with open(p, "rb") as f:
        while True:
            chunk = f.read(buf)
            if not chunk: break
            m.update(chunk)
    return m.hexdigest()

rows = []
if INPUT_DIR.exists():
    for p in INPUT_DIR.rglob("*"):
        if p.is_file():
            stem = p.name
            for suf in [".fastq.gz", ".fq.gz", ".vcf.gz", ".vcf", ".bam", ".cram", ".txt", ".gz"]:
                if stem.endswith(suf):
                    stem = stem[: -len(suf)]
            sample_id = stem
            md5 = file_md5(p)
            size_bytes = p.stat().st_size
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            rows.append((sample_id, str(p), md5, size_bytes, ts))

# Write TSV (schema pinned even if empty)
with open(TMP_TSV, "w", encoding="utf-8") as w:
    w.write("sample_id\tpath\tmd5\tsize_bytes\tts\n")
    for r in rows:
        w.write("\t".join(map(str, r)) + "\n")

# Load TSV -> Parquet via DuckDB (no parameter placeholder in COPY TO)
con = duckdb.connect()
con.execute("""
  CREATE OR REPLACE TABLE manifest AS
  SELECT * FROM read_csv(
    ?, header=true, delim='\t',
    columns={'sample_id':'VARCHAR','path':'VARCHAR','md5':'VARCHAR','size_bytes':'BIGINT','ts':'TIMESTAMP'}
  );
""", [str(TMP_TSV)])

parquet_path_sql = str(OUT_PARQUET).replace("'", "''")
con.execute(f"COPY manifest TO '{parquet_path_sql}' (FORMAT PARQUET);")

n = con.execute("SELECT COUNT(*) FROM manifest;").fetchone()[0]
print(f"manifest_rows={n}")

h = hashlib.sha256(Path(OUT_PARQUET).read_bytes()).hexdigest()[:8]
print(f"manifest_hash={h}")
