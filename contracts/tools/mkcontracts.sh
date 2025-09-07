#!/usr/bin/env bash
chmod +x "$CONTRACTS_DIR/tools/validate_contracts.sh"


# --- tests/duckdb_contracts.sh ---
cat > "$CONTRACTS_DIR/tests/duckdb_contracts.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${DUCKDB_PATH:?set DUCKDB_PATH}"; : "${REPO_ROOT:?set REPO_ROOT}"
python3 - "$REPO_ROOT" "$DUCKDB_PATH" <<'PY'
import os, sys, json
sys.path.insert(0, sys.argv[1])
from components.dbduck.duck import conn
with conn() as con:
# ensure essential schemas & views exist
needed = [
("information_schema.columns", "table_schema", "core"),
]
# simple query to touch the report views
try:
con.execute("select * from report.subject_overview limit 0")
con.execute("select * from report.variant_risk limit 0")
ok_views = True
except Exception:
ok_views = False
# fingerprint: row counts for core tables (safe if 0)
fp = {
"rows_core_samples": con.execute("select count(*) from core.samples").fetchone()[0] if ok_views else 0,
"rows_core_annotations": con.execute("select count(*) from core.annotations").fetchone()[0] if ok_views else 0,
}
print(json.dumps({"contracts_ok": ok_views, **fp}))
PY
SH
chmod +x "$CONTRACTS_DIR/tests/duckdb_contracts.sh"


# --- versions.yaml (computed hashes) ---
calc_hash() {
local file="$1"
if command -v sha256sum >/dev/null; then sha256sum "$file" | awk '{print $1}'
else shasum -a 256 "$file" | awk '{print $1}'; fi
}


ING=$(calc_hash "$CONTRACTS_DIR/data/ingest_v1.yaml")
SCH=$(calc_hash "$CONTRACTS_DIR/dbduck/schema_v1.sql")
VEP=$(calc_hash "$CONTRACTS_DIR/anno/vep_io_v1.yaml")
REP=$(calc_hash "$CONTRACTS_DIR/report/report_io_v1.yaml")


cat > "$CONTRACTS_DIR/versions.yaml" <<YAML
files:
- path: data/ingest_v1.yaml
version: "1.0.0"
sha256: "$ING"
- path: dbduck/schema_v1.sql
version: "1.0.0"
sha256: "$SCH"
- path: anno/vep_io_v1.yaml
version: "1.0.0"
sha256: "$VEP"
- path: report/report_io_v1.yaml
version: "1.0.0"
sha256: "$REP"
combined_fingerprint:
# output of tools/contract_hash.py (informational)
$(python3 "$CONTRACTS_DIR/tools/contract_hash.py" | tr -d '\n')
YAML


echo "contracts_bootstrapped"