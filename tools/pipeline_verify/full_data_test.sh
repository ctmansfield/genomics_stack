#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

# Load/export PG_DSN if present; else default to local docker on 55432.
if [[ -z "${PG_DSN:-}" ]] && [[ -f "$REPO_DIR/env.d/pg.env" ]]; then
  set -a; source "$REPO_DIR/env.d/pg.env"; set +a
fi
: "${PG_DSN:=host=127.0.0.1 port=55432 dbname=genomics user=postgres password=genomics}"
export PG_DSN

PYBIN="${PYBIN:-$REPO_DIR/.venv/bin/python}"; [[ -x "$PYBIN" ]] || PYBIN="$(command -v python3 || command -v python)"

usage(){ echo "Usage: $0 --file /path/to/raw.txt [--label SAMPLE_LABEL] [--report-dir DIR]"; }
IN_FILE=""; SAMPLE_LABEL=""; REPORT_DIR="${REPORT_DIR:-$REPO_DIR/risk_reports/out}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) IN_FILE="$2"; shift 2;;
    --label) SAMPLE_LABEL="$2"; shift 2;;
    --report-dir) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done
[[ -n "$IN_FILE" ]] || { echo "Missing --file"; usage; exit 2; }
[[ -f "$IN_FILE" ]] || { echo "Input not found: $IN_FILE"; exit 2; }

bn="$(basename -- "$IN_FILE")"
[[ -n "$SAMPLE_LABEL" ]] || SAMPLE_LABEL="${bn%.*}"
mkdir -p "$REPORT_DIR" "$REPO_DIR/tmp"

# Create uploads row
UPLOAD_ID="$(psql "$PG_DSN" -Atqc \
  "insert into uploads(original_name,stored_path,size_bytes,kind,status,sample_label,claim_code)
   values ($(printf %s "'$bn'"), $(printf %s "'$IN_FILE'"),
           $(stat -c%s "$IN_FILE" 2>/dev/null || echo 0), 'array','parsed',
           $(printf %s "'$SAMPLE_LABEL'"), 'AUTO')
   returning id;")"
[[ -n "$UPLOAD_ID" ]] || { echo "Failed to create upload row"; exit 3; }
echo "[full-test] upload_id=$UPLOAD_ID  label=$SAMPLE_LABEL"

# Make TSV for staging_array_calls (accept 4/5/6-col formats; map 23/24/25 → X/Y/MT)
OUT_TSV="$REPO_DIR/tmp/staging_${UPLOAD_ID}.tsv"
"$PYBIN" - <<'PY' "$IN_FILE" "$OUT_TSV" "$UPLOAD_ID" "$SAMPLE_LABEL"
import sys, pathlib

inp = pathlib.Path(sys.argv[1])
outp = pathlib.Path(sys.argv[2])
upload_id, label = sys.argv[3], sys.argv[4]

def map_chrom(ch):
    ch = ch.strip().replace("chr","").upper()
    return {"23":"X","24":"Y","25":"MT"}.get(ch, ch)

def parse_line(line):
    if not line or line.startswith("#"):
        return None
    parts = line.strip().split()
    if not parts: return None
    head = [p.lower() for p in parts[:5]]
    if head[:1] == ["rsid"] or head[:2] == ["rsid","chromosome"]:
        return None

    if len(parts) >= 6:  # rsid chrom pos a1 a2 gt
        rsid, chrom, pos, a1, a2, gt = parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
    elif len(parts) == 5:  # Ancestry: rsid chrom pos a1 a2
        rsid, chrom, pos, a1, a2 = parts[:5]
        gt = f"{(a1 or '-')}{(a2 or '-')}"
    elif len(parts) >= 4:  # 23andMe: rsid chrom pos gt
        rsid, chrom, pos, gt = parts[0], parts[1], parts[2], parts[3]
        a1 = gt[0] if gt and gt[0] != "-" else ""
        a2 = gt[1] if len(gt) > 1 and gt[1] != "-" else (a1 or "")
    else:
        return None

    chrom = map_chrom(chrom)
    try:
        posi = int(pos)
    except Exception:
        return None

    raw_line = line.rstrip("\n").replace("\t","    ")
    return rsid, chrom, posi, a1, a2, gt, raw_line

with inp.open("r", encoding="utf-8", errors="ignore") as f, outp.open("w", encoding="utf-8") as w:
    w.write("upload_id\tsample_label\trsid\tchrom\tpos\tallele1\tallele2\tgenotype\traw_line\n")
    for raw in f:
        row = parse_line(raw)
        if not row: continue
        rsid, chrom, posi, a1, a2, gt, raw_line = row
        w.write(f"{upload_id}\t{label}\t{rsid}\t{chrom}\t{posi}\t{a1}\t{a2}\t{gt}\t{raw_line}\n")
print(outp)
PY

# Sanity: TSV exists & non-empty (besides header)
lines=$(wc -l < "$OUT_TSV" || echo 0)
if [[ "$lines" -le 1 ]]; then
  echo "No parsed rows produced from $IN_FILE"; exit 4
fi

# Bulk load using STDIN to avoid path/quoting issues
psql "$PG_DSN" -c "\copy staging_array_calls(upload_id,sample_label,rsid,chrom,pos,allele1,allele2,genotype,raw_line) FROM STDIN WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '')" < "$OUT_TSV"

# E2E quickcheck → reports
if [[ -x "$REPO_DIR/tools/pipeline_verify/e2e_quickcheck.sh" ]]; then
  "$REPO_DIR/tools/pipeline_verify/e2e_quickcheck.sh" --file-id "$UPLOAD_ID" --dsn "$PG_DSN" --report-dir "$REPORT_DIR"
else
  export IMPORT_TABLE=variants IMPORT_ID_COL=file_id
  export VEP_TABLE=vep_annotations VEP_ID_COL=file_id
  export JOIN_KEY=variant_id
  mkdir -p "$REPORT_DIR"
  "$PYBIN" "$REPO_DIR/scripts/reports/generate_full_report.py" --file-id "$UPLOAD_ID" || true
  "$PYBIN" "$REPO_DIR/scripts/reports/generate_top10.py"      --file-id "$UPLOAD_ID" || true
  echo "[e2e] Imported variants: $(psql "$PG_DSN" -Atqc "select count(*) from ${IMPORT_TABLE} where ${IMPORT_ID_COL}='${UPLOAD_ID}';")"
  echo "[e2e] VEP annotations : $(psql "$PG_DSN" -Atqc "select count(*) from ${VEP_TABLE} where ${VEP_ID_COL}='${UPLOAD_ID}';")"
  echo "[e2e] Outputs:"; ls -1 "$REPORT_DIR" | sed 's/^/ - /'
fi

echo "[full-test] done: upload_id=$UPLOAD_ID  reports -> $REPORT_DIR"
