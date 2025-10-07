
## clinician-top20-system-coverage (2025-10-05T12:01:00Z)

- Added patch plan and deliverables docs
- Introduced systems taxonomy doc
- Added migration sql/20251005_add_system_tag_to_risk_rules.sql to extend risk_rules with system_tag

## report-top (2025-08-13T10:22:52+00:00)

- See docs/changes/20250813_102252_report-top.md

## report-top-fix (2025-08-13T10:37:50+00:00)

- See docs/changes/20250813_103750_report-top-fix.md

## pair-aware-report (2025-08-13T10:47:13+00:00)

- See docs/changes/20250813_104713_pair-aware-report.md
## reference-aware-rare-snps-export (2025-10-07T00:23:47Z)

**Summary**
- Added a reference-aware export that flags **non-reference genotypes** and filters to **rare or AF-missing** calls.
- Created a durable SQL **view** for downstream use and a CSV/HTML artifact in .
- Hardened the pipeline around chromosome normalization, FASTA indexing, and rsID annotation upserts.

**Scope / Why**
- Clinician review needs a compact table of potentially interesting SNPs (non-ref vs GRCh37/38) with optional gnomAD AF filtering.
- Keeps analysis reproducible (pure SQL view) and easy to ship (CSV/HTML).

**Data & Reference Prep**
- Reference FASTA (GRCh37 / hs37d5):
  - 
  - If RAZF warning: 
  - Index: 
- Chromosome normalization:
  - Map , , , strip  prefix, enforce .
- rsID annotation store (idempotent):
  - 
  - Upsert strategy used to avoid PK conflicts.

**SQL view (reproducible output)**
- Created :
  - Joins upload’s staged calls to .
  - Classifies genotype vs reference (, , ; else ).
  - Filters to non-reference only and **AF < 1% OR AF missing** (tunable).

**Artifacts**
- CSV:  (example: 319,475 rows on upload_id=2).
- Optional HTML preview:  (first 5k rows rendered for speed).

**How to Reproduce (concise)**
1) Ensure  populated (Ancestry 5-col format).
2) Build/verify FASTA index: 
3) Populate  (filtered to valid contig bounds via ):
   - Export coords, filter by  lengths, Usage: samtools faidx <file.fa|file.fa.gz> [<reg> [...]]
Option: 
 -o, --output FILE        Write FASTA to file.
 -n, --length INT         Length of FASTA sequence line. [60]
 -c, --continue           Continue after trying to retrieve missing region.
 -r, --region-file FILE   File of regions.  Format is chr:from-to. One per line.
 -i, --reverse-complement Reverse complement sequences.
     --mark-strand TYPE   Add strand indicator to sequence name
                          TYPE = rc   for /rc on negative strand (default)
                                 no   for no strand indicator
                                 sign for (+) / (-)
                                 custom,<pos>,<neg> for custom indicator
     --fai-idx      FILE  name of the index file (default file.fa.fai).
     --gzi-idx      FILE  name of compressed file index (default file.fa.gz.gzi).
 -f, --fastq              File and index in FASTQ format.
 -h, --help               This message. one-base pulls, upsert clean .
4) Create/refresh view:
```sql
DROP VIEW IF EXISTS public.v_reference_aware_rare;
CREATE VIEW public.v_reference_aware_rare AS
WITH base AS (
  SELECT sac.upload_id, sac.rsid, sac.chrom::text AS chromosome, sac.pos::bigint AS position,
         UPPER(sac.allele1) AS a1, UPPER(sac.allele2) AS a2
  FROM public.staging_array_calls sac
  WHERE sac.upload_id = 2
),
annot AS (
  SELECT a.rsid, NULLIF(UPPER(a.ref37),'') AS ref37, NULLIF(UPPER(a.ref38),'') AS ref38, a.gnomad_af_global AS af
  FROM public.rsid_annotation a
),
joined AS (
  SELECT b.*, COALESCE(annot.ref37, annot.ref38) AS ref_allele, annot.af
  FROM base b LEFT JOIN annot USING (rsid)
),
typed AS (
  SELECT *,
  CASE
    WHEN ref_allele IN ('A','C','G','T') AND a1 IN ('A','C','G','T') AND a2 IN ('A','C','G','T') THEN
      CASE
        WHEN a1 = ref_allele AND a2 = ref_allele THEN 'hom_ref'
        WHEN a1 = a2 AND a1 <> ref_allele THEN 'hom_alt'
        ELSE 'het_alt'
      END
    ELSE 'nocall/other'
  END AS genotype_class
  FROM joined
)
SELECT rsid, chromosome, position, a1 AS allele1, a2 AS allele2,
       ref_allele, genotype_class, af AS gnomad_af_global
FROM typed
WHERE genotype_class IN ('het_alt','hom_alt')
  AND (af IS NULL OR af < 0.01)
ORDER BY
  CASE chromosome WHEN 'X' THEN 23 WHEN 'Y' THEN 24 WHEN 'MT' THEN 25 ELSE NULL END NULLS LAST,
  chromosome, position NULLS LAST, rsid;
```
5) Export:
```bash
psql "$PGDATABASE" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"   -c "COPY (SELECT * FROM public.v_reference_aware_rare) TO STDOUT WITH CSV HEADER"   > reports/upload_2/reference_aware_rare_snps.csv
```

**Verification**
- Rowcount > 0; only / present in output.
-  ∈ {A,C,G,T}; no stray FASTA headers.
- Spot-check a few rsIDs vs raw file and GRCh37 reference base.
- Optional summaries:
  - 
  - 

**Troubleshooting**
-  → filter coords by  contig lengths and normalize chrom labels.
-  → prefer  + shell redirection (no backslashes).
- PK conflicts in  → use temp table + .
- Missing AFs → keep  until AFs are loaded; then switch to strict rare.

**Security / VCS hygiene**
- Keep large outputs out of git:
  - : add , , 
- Artifacts may contain sensitive genomic data; handle per policy.

**Next**
- Load gnomAD AFs for GRCh37 rsIDs locally and switch filter to .
- Add small HTML summary (counts by genotype/chromosome) to the preview page.
- Wire this table into the clinician report as a download link and/or appendix.


cat >> docs/CHANGELOG.md <<MD
## reference-aware-rare-snps-export ($(date -u +%Y-%m-%dT%H:%M:%SZ))

**Summary**
- Added a reference-aware export that flags **non-reference genotypes** and filters to **rare or AF-missing** calls.
- Created a durable SQL **view** for downstream use and a CSV/HTML artifact in `reports/upload_2/`.
- Hardened the pipeline around chromosome normalization, FASTA indexing, and rsID annotation upserts.

**Scope / Why**
- Clinician review needs a compact table of potentially interesting SNPs (non-ref vs GRCh37/38) with optional gnomAD AF filtering.
- Keeps analysis reproducible (pure SQL view) and easy to ship (CSV/HTML).

**Data & Reference Prep**
- Reference FASTA (GRCh37 / hs37d5):
  - `curl -L -o /mnt/nas_storage/ref/grch37/hs37d5.fa.gz https://storage.googleapis.com/genomics-public-data/references/hs37d5/hs37d5.fa.gz`
  - If RAZF warning: `truncate -s 901399327 hs37d5.fa.gz && gunzip hs37d5.fa.gz`
  - Index: `samtools faidx /mnt/nas_storage/ref/grch37/hs37d5.fa`
- Chromosome normalization:
  - Map `23→X`, `24→Y`, `25/26/M→MT`, strip `chr` prefix, enforce `[1-22,X,Y,MT]`.
- rsID annotation store (idempotent):
  - `CREATE TABLE IF NOT EXISTS public.rsid_annotation(rsid text PRIMARY KEY, ref37 text, ref38 text, gnomad_af_global double precision, CONSTRAINT rsid_annotation_ref37_chk CHECK (ref37 IS NULL OR ref37 ~ '^[ACGT]$'));`
  - Upsert strategy used to avoid PK conflicts.

**SQL view (reproducible output)**
- Created `public.v_reference_aware_rare`:
  - Joins upload’s staged calls to `rsid_annotation`.
  - Classifies genotype vs reference (`hom_ref`, `het_alt`, `hom_alt`; else `nocall/other`).
  - Filters to non-reference only and **AF < 1% OR AF missing** (tunable).

**Artifacts**
- CSV: `reports/upload_2/reference_aware_rare_snps.csv` (example: 319,475 rows on upload_id=2).
- Optional HTML preview: `reports/upload_2/reference_aware_rare_snps.html` (first 5k rows rendered for speed).

**How to Reproduce (concise)**
1) Ensure `staging_array_calls.upload_id=2` populated (Ancestry 5-col format).
2) Build/verify FASTA index: `samtools faidx /mnt/nas_storage/ref/grch37/hs37d5.fa`
3) Populate `rsid_annotation.ref37` (filtered to valid contig bounds via `.fai`):
   - Export coords, filter by `.fai` lengths, `samtools faidx -n 1` one-base pulls, upsert clean `A/C/G/T`.
4) Create/refresh view:
\`\`\`sql
DROP VIEW IF EXISTS public.v_reference_aware_rare;
CREATE VIEW public.v_reference_aware_rare AS
WITH base AS (
  SELECT sac.upload_id, sac.rsid, sac.chrom::text AS chromosome, sac.pos::bigint AS position,
         UPPER(sac.allele1) AS a1, UPPER(sac.allele2) AS a2
  FROM public.staging_array_calls sac
  WHERE sac.upload_id = 2
),
annot AS (
  SELECT a.rsid, NULLIF(UPPER(a.ref37),'') AS ref37, NULLIF(UPPER(a.ref38),'') AS ref38, a.gnomad_af_global AS af
  FROM public.rsid_annotation a
),
joined AS (
  SELECT b.*, COALESCE(annot.ref37, annot.ref38) AS ref_allele, annot.af
  FROM base b LEFT JOIN annot USING (rsid)
),
typed AS (
  SELECT *,
  CASE
    WHEN ref_allele IN ('A','C','G','T') AND a1 IN ('A','C','G','T') AND a2 IN ('A','C','G','T') THEN
      CASE
        WHEN a1 = ref_allele AND a2 = ref_allele THEN 'hom_ref'
        WHEN a1 = a2 AND a1 <> ref_allele THEN 'hom_alt'
        ELSE 'het_alt'
      END
    ELSE 'nocall/other'
  END AS genotype_class
  FROM joined
)
SELECT rsid, chromosome, position, a1 AS allele1, a2 AS allele2,
       ref_allele, genotype_class, af AS gnomad_af_global
FROM typed
WHERE genotype_class IN ('het_alt','hom_alt')
  AND (af IS NULL OR af < 0.01)
ORDER BY
  CASE chromosome WHEN 'X' THEN 23 WHEN 'Y' THEN 24 WHEN 'MT' THEN 25 ELSE NULL END NULLS LAST,
  chromosome, position NULLS LAST, rsid;
\`\`\`
5) Export:
\`\`\`bash
psql "\$PGDATABASE" -h "\$PGHOST" -p "\$PGPORT" -U "\$PGUSER" \
  -c "COPY (SELECT * FROM public.v_reference_aware_rare) TO STDOUT WITH CSV HEADER" \
  > reports/upload_2/reference_aware_rare_snps.csv
\`\`\`

**Verification**
- Rowcount > 0; only `het_alt`/`hom_alt` present in output.
- `ref_allele` ∈ {A,C,G,T}; no stray FASTA headers.
- Spot-check a few rsIDs vs raw file and GRCh37 reference base.
- Optional summaries:
  - `SELECT genotype_class, COUNT(*) FROM public.v_reference_aware_rare GROUP BY 1 ORDER BY 2 DESC;`
  - `SELECT chromosome, COUNT(*) FROM public.v_reference_aware_rare GROUP BY 1 ORDER BY 1;`

**Troubleshooting**
- `Zero length sequence: MT:…` → filter coords by `.fai` contig lengths and normalize chrom labels.
- `\copy parse error` → prefer `COPY (...) TO STDOUT` + shell redirection (no backslashes).
- PK conflicts in `rsid_annotation` → use temp table + `INSERT … ON CONFLICT DO UPDATE`.
- Missing AFs → keep `(af IS NULL OR af < 0.01)` until AFs are loaded; then switch to strict rare.

**Security / VCS hygiene**
- Keep large outputs out of git:
  - `.gitignore`: add `/reports/`, `/tmp/`, `/mnt/nas_storage/ref/`
- Artifacts may contain sensitive genomic data; handle per policy.

**Next**
- Load gnomAD AFs for GRCh37 rsIDs locally and switch filter to `af IS NOT NULL AND af < 0.01`.
- Add small HTML summary (counts by genotype/chromosome) to the preview page.
- Wire this table into the clinician report as a download link and/or appendix.
MD

## clinvar-ingest-improvements (2025-10-07T00:00:00Z)

Summary
- Added unit-tested helpers to robustly parse ClinVar CLNREVSTAT into 0..4 stars and normalize CLNSIG lists (delimiter/case normalization while preserving multi-word terms).
- Improved error logging with counts for missing RS and malformed INFO fields during VCF iteration.
- Implemented two new CLI modes in scripts/adapters/clinvar_ingest_subset.py:
  - --dry-run: prints the first 20 parsed tuples; no DB writes.
  - --rsid-only FILE: reads a newline RSID list (rs123 or 123) and backfills public.clinvar_by_rsid only for those targets, skipping full staging lookup.
- Added small inline tests for helpers under if __name__ == '__main__': (no external test runner required).
- Added scripts/tests/verify_clinvar_ingest.sh to validate ingest outcomes and idempotency.

Details
- File: scripts/adapters/clinvar_ingest_subset.py
  - review_stars(): maps CLNREVSTAT → 0..4, tolerant of delimiters/casing.
  - normalize_clnsig(): normalizes significance strings (commas/pipes/semicolons, lowercasing, preserving multi-word labels like "likely pathogenic").
  - normalize_conditions(), parse_clndate(): quality-of-life helpers for output fields.
  - Error counters: missing_rs and malformed_info reported with final stats.
  - Upsert is idempotent via ON CONFLICT (rsid) DO UPDATE.
- File: scripts/tests/verify_clinvar_ingest.sh
  - Checks: row count threshold, idempotency (total vs distinct rsid), review_stars range, presence of rs1801133 and rs1800562, and presence/sample of v_evidence_counts (schema-aware: supports n_evidence column).

How to Run (examples)
- Dry-run (rsid-only file):
  python scripts/adapters/clinvar_ingest_subset.py \
    --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz \
    --rsid-only rsids.txt \
    --dry-run
- Full ingest (writes to DB):
  python scripts/adapters/clinvar_ingest_subset.py \
    --vcf /mnt/nas_storage/data/clinvar/GRCh38/current/clinvar.vcf.gz \
    --rsid-only rsids.txt

Acceptance Verification (observed)
- Ingested ≥ 75,000 clinvar_by_rsid rows without errors.
- rs1801133 and rs1800562 exist with non-null clnsig_raw and reasonable review_stars for their categories.
- v_evidence_counts shows ≥1 evidence row attached to at least one known variant_effect (column name n_evidence in this schema).
- No schema migration errors; reruns are idempotent (ON CONFLICT prevents duplicates).

