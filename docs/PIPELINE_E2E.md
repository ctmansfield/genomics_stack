# End-to-End Pipeline Verification & Reports
Validate: upload → import → VEP annotate → report.

## E2E check
tools/pipeline_verify/e2e_pipeline_check.sh \
  --file-id <UUID-or-filename> \
  --import-table variants --import-id-col file_id \
  --vep-table vep_annotations --vep-id-col file_id \
  --report-dir /root/genomics-stack/risk_reports/out

## Reports
export PG_DSN="postgresql://user:pass@host:5432/genomics"
export IMPORT_TABLE="variants"; export IMPORT_ID_COL="file_id"
export VEP_TABLE="vep_annotations"; export VEP_ID_COL="file_id"
export JOIN_KEY="variant_id"; export REPORT_OUT="/root/genomics-stack/risk_reports/out"
python scripts/reports/generate_full_report.py --file-id <ID>
export SCORE_COLUMN="priority_score"
python scripts/reports/generate_top10.py --file-id <ID>
