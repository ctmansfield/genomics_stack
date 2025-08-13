# Genomics stack – handoff (paste this into the next chat)
- Services: Postgres 16, Hasura, Metabase, pgAdmin, Ingest API, Ingest worker.
- Portal: upload + claim/token working; duplicate guard via trigger + partial unique index.
- Risk panel: seeded (MTHFR, F5, F2, SLCO1B1). Command: `genomicsctl.sh risk-panel-seed`.
- Reports: `report-top5` makes HTML/TSV; `report-pdf` renders PDF via headless Chrome container.
- VEP cache: downloaded/extracted; GRCh38 FASTA indexed; offline VEP self-test OK.
- Last successful report: /mnt/nas_storage/genomics-stack/reports/upload_2/top5.{html,tsv,pdf}

## Open items / next steps
1) Add a portal link to download the latest report by upload_id.
2) Expand risk panel + weights; add nutritional blurbs.
3) “Reset ingest” menu path tested; continue hard/soft delete flows.
4) Bundle install self-check into one command; finish idempotent guardrails.

(Attached: compose, redacted .env, scripts/, recent logs, DB schema, uploads & risk panel snapshots.)
