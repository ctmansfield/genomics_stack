# End-to-End Pipeline Verification & Reports

This bundle adds:
- A pipeline verifier (`tools/pipeline_verify/e2e_pipeline_check.sh`)
- Two report scripts (`scripts/reports/generate_full_report.py`, `scripts/reports/generate_top10.py`)
- DDL for a basic `ingest_registry` + `ingest_events` (idempotent)

## Install
```bash
REPO_DIR=/root/genomics-stack
tar -xzf patch-0008-core.tar.gz
cp -a patch-0008-core/* "$REPO_DIR"/
```
