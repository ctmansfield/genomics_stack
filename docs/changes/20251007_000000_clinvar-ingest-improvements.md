# ClinVar Ingest Improvements

Date: 2025-10-07
Tag: clinvar-ingest-improvements

## Summary
Adds robust ClinVar ingest helpers and new modes to streamline backfilling public.clinvar_by_rsid and verifying outcomes:
- Robust parsing of CLNREVSTAT into 0..4 review stars
- Normalization of CLNSIG lists (delimiter/case normalization while preserving multi-word terms)
- Error counters for missing RS and malformed INFO fields
- New CLI flags:
  - `--dry-run`: Print first 20 parsed tuples; skip DB writes
  - `--rsid-only FILE`: Read newline-separated rsIDs to backfill only those targets
- Small inline tests under `if __name__ == '__main__':` (no external test runner)
- One-shot verification script to validate ingest and idempotency

## Why
- CLNREVSTAT texts vary in wording and delimiters; a consistent star mapping (0..4) reduces ambiguity.
- CLNSIG frequently appears with mixed delimiters and casing; normalized strings are easier to use and compare.
- RS values can be missing or malformed in some VCF records; counters help operational visibility.
- `--dry-run` and `--rsid-only` accelerate iteration and targeted backfills without scanning/applying the entire VCF.

## Scope
- Script: `scripts/adapters/clinvar_ingest_subset.py` (primary ingest)
- Added verification helper: `scripts/tests/verify_clinvar_ingest.sh`
- Changelog updates in `docs/CHANGELOG.md`

## Changes in Detail
### scripts/adapters/clinvar_ingest_subset.py
- Helpers
  - `review_stars(clnrev) -> int | None`: Parses CLNREVSTAT to 0..4 stars. Robust to case and delimiters (`, ; |`).
  - `normalize_clnsig(clnsig) -> str | None`: Joins tuples/lists; standardizes separators, lowercases, preserves multi-word tokens like "likely pathogenic".
  - `normalize_conditions(conds) -> str | None`: Renders condition names cleanly using `; ` separators and removes repeated underscores.
  - `parse_clndate(val) -> date | None`: Accepts `%Y%m%d` and `%Y-%m-%d`.
- Error counters
  - `missing_rs`: Incremented when record lacks RS info and ID doesn’t carry an rsID.
  - `malformed_info`: Incremented for exceptions while reading INFO fields.
- Modes
  - `--dry-run`: Prints first 20 parsed tuples and a summary; does not write to DB.
  - `--rsid-only FILE`: Reads a newline-separated rsID list (accepts both `rs123` and `123`) and restricts ingest to those. Skips staging lookup.
  - Optional `--upload-id`: Reads target rsIDs from `public.staging_array_calls` for that upload.
- Upsert behavior
  - Idempotent `ON CONFLICT (rsid) DO UPDATE` on `public.clinvar_by_rsid`.
- Inline tests
  - Demos `review_stars` and `normalize_clnsig` at startup for quick sanity checks.

### scripts/tests/verify_clinvar_ingest.sh
- Validates:
  - Rowcount in `public.clinvar_by_rsid` and PASS/FAIL against a threshold (≥1000)
  - Idempotency via `COUNT(*)` vs `COUNT(DISTINCT rsid)`
  - `review_stars` values are within [0..4]
  - Presence of `rs1801133` and `rs1800562` with non-null `clnsig_raw` and reasonable `review_stars`
  - Evidence summary via `public.v_evidence_counts` if present (handles either `n_evidence` or prints sample if schema differs)

## Usage
Dry-run with rsid-only file:
```bash
python scripts/adapters/clinvar_ingest_subset.py \
  --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz \
  --rsid-only rsids.txt \
  --dry-run
```

Full ingest (writes to DB):
```bash
python scripts/adapters/clinvar_ingest_subset.py \
  --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz \
  --rsid-only rsids.txt
```

Source rsIDs from staging by upload:
```bash
python scripts/adapters/clinvar_ingest_subset.py \
  --upload-id 1234 \
  --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz
```

Verify outcomes:
```bash
PGHOST=localhost PGPORT=5432 PGDATABASE=genomics PGUSER=genouser PGPASSWORD=... \
  scripts/tests/verify_clinvar_ingest.sh
```

## Acceptance Verification (Observed)
- Ingested ≥75k rows into `public.clinvar_by_rsid` without errors
- `rs1801133` and `rs1800562` present with non-null `clnsig_raw` and reasonable `review_stars`
- Evidence view shows ≥1 evidence row for at least one known variant_effect (schema’s `n_evidence` column)
- Reruns do not create duplicates (idempotent upserts)

## Notes & Caveats
- RSID indexing: tabix does not index rsIDs; the VCF scan is required to find targets. Filtering by `--rsid-only` still scans but reduces upsert volume.
- Stars mapping follows ClinVar semantics:
  - 4: practice guideline
  - 3: reviewed by expert panel
  - 2: criteria provided, multiple submitters, no conflicts
  - 1: criteria provided (e.g., single submitter) or conflicting interpretations
  - 0: no assertion provided / other minimal-review states
- Pharmacogenomic `drug_response` entries often carry low/zero star ratings depending on CLNREVSTAT.

## Performance
- Streaming `pysam.VariantFile.fetch()` with simple counters; upserts chunked (default 5k rows/batch).

## Rollback
- The ingest is idempotent and only upserts to `public.clinvar_by_rsid`.
- To revert content, either truncate `public.clinvar_by_rsid` or re-run ingest with a narrower rsID set as needed.

## Appendix: CLNREVSTAT → Stars Mapping (Heuristic)
- Normalize CLNREVSTAT (lowercase, collapse whitespace; split on `, ; |`).
- Assign the highest applicable priority:
  1. Contains "practice guideline" → 4
  2. Contains "reviewed by expert panel" → 3
  3. Contains "criteria provided" + "multiple submitters" + "no conflicts" → 2
  4. Contains "criteria provided" (any) → 1
  5. Contains "conflicting" → 1
  6. Contains "no assertion" → 0
  7. Else → 0
