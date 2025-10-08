# Adapters — Ingest Utilities

This directory contains ingest adapters for ClinVar and VEP-derived annotations.

## ClinVar — Subset by rsID

Script: `scripts/adapters/clinvar_ingest_subset.py`

- Features
  - Robust CLNREVSTAT → 0..4 star mapping
  - CLNSIG normalization (delimiters, case)
  - Error counters for missing RS and malformed INFO
  - Modes: `--dry-run`, `--rsid-only FILE`, `--upload-id`
- Usage (env-driven DSN)
```bash
export PGHOST=127.0.0.1 PGPORT=5433 PGDATABASE=genomics PGUSER=postgres PGPASSWORD=...
python scripts/adapters/clinvar_ingest_subset.py \
  --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz \
  --rsid-only rsids.txt \
  --dry-run
# Full ingest (writes to DB)
python scripts/adapters/clinvar_ingest_subset.py \
  --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz \
  --rsid-only rsids.txt
```
- Quick checks
```sql
SELECT COUNT(*) FROM public.clinvar_by_rsid;
SELECT rsid, clnsig_raw, review_stars FROM public.clinvar_by_rsid WHERE rsid IN ('rs1801133','rs1800562');
```

## Adapter A — VEP CSQ → vep_by_rsid

Script: `scripts/adapters/vep_ingest_by_rsid.py`

- Purpose
  - Parse VEP CSQ from a VCF.gz and upsert per-rsid consequences into `public.vep_by_rsid`.
  - Targets rsIDs for a specific upload (reads from `public.staging_array_calls`).
- Selection logic
  - Filter CSQ rows to those with `SYMBOL`.
  - Prefer `CANONICAL=YES`; else use all.
  - Pick the one with max IMPACT rank: `{'HIGH':4,'MODERATE':3,'LOW':2,'MODIFIER':1}`.
- Extracted fields
  - `gene_symbol`, `consequence`, `impact`
  - Optional: `cadd_phred`, `revel_score`, `spliceai_max`
  - `extras` JSON: `Transcript, HGVSp, HGVSc, SIFT, PolyPhen, CANONICAL, BIOTYPE`
- Usage (env or CLI)
```bash
# Environment
export VEP_VCF=/mnt/nas_storage/data/vep/GRCh38/current/vep.vcf.gz
export UPLOAD_ID=1234
export PGHOST=127.0.0.1 PGPORT=5433 PGDATABASE=genomics PGUSER=postgres PGPASSWORD=...
python scripts/adapters/vep_ingest_by_rsid.py --dry-run

# CLI
python scripts/adapters/vep_ingest_by_rsid.py \
  --vep-vcf /mnt/nas_storage/data/vep/GRCh38/current/vep.vcf.gz \
  --upload-id 1234 \
  --limit 0
```
- Sanity SQL
```sql
SELECT COUNT(*) FROM public.vep_by_rsid;
SELECT rsid, gene_symbol, consequence, impact FROM public.vep_by_rsid WHERE rsid IN ('rs1801133','rs1800562');
SELECT impact, COUNT(*) FROM public.vep_by_rsid GROUP BY 1 ORDER BY 2 DESC;
```

## Notes
- For ClinVar VCF, use a stable symlink such as `/mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz` (see tools/clinvar_sync.sh).
- Ensure `.tbi` indices are present next to `.vcf.gz` files.
