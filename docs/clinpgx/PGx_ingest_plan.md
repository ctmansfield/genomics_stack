# ClinPGx (PharmGKB + CPIC) — ingestion plan

> System/app map lives in **/mnt/nas_storage/ops** (`docs/living-brief.md`, `sysmap.yaml`). This doc only describes data flows & DB schema used by the genomics-stack app.

## What PharmGKB & CPIC provide (and how we’ll use them)

### PharmGKB (pharmacogenomics knowledgebase)
- Clinical annotations for gene/variant ↔ drug ↔ phenotype with evidence (1A, 1B, 2A…).
- Drug label annotations (FDA/EMA…).
- Pathways and mechanism context.

**We’ll ingest:**
- Clinical annotations → `gene_drug_guidelines` (+ evidence).
- Drug label flags → `pgx_drug_labels`.
- (Optional) pathway membership for systems model.

### CPIC
- Peer-reviewed gene–drug guidelines: allele definitions, diplotype→phenotype, phenotype→recommendation, strength.

**We’ll ingest:**
- Guideline metadata + URLs.
- Allele function tables → `pgx_allele_definitions`.
- Diplotype→phenotype → `pgx_diplotype_phenotype`.
- Phenotype→recommendation → `pgx_pheno_recommendations`.

### Licensing heads-up
- Confirm current PharmGKB & CPIC licenses before ingest; store the license/version strings with `knowledge_sources`.
- Do **not** redistribute guideline text; store links + minimal normalized prose.

## Minimal schema (see `migrations/2025-10-07_clinpgx_core.sql`)
Tables:
- `drug_catalog`, `gene_drug_guidelines`,
- `pgx_allele_definitions`, `pgx_diplotype_phenotype`, `pgx_pheno_recommendations`,
- `pgx_drug_labels`, `evidence_pgx_drug_labels`.

## Adapter plan
**Phase 1 (safe link-only)**: PharmGKB labels adapter → `pgx_drug_labels` + evidence links.

**Phase 2 (opt-in per gene)**: CPIC star-calling modules → provisional phenotypes and candidate dosing guidance.

## App view (sketch)
`v_pgx_candidates(upload_id, gene_symbol, drug_name, source, level, phenotype, recommendation, strength, needs_haplotype_call, needs_cnv, url, n_evidence)` sorted by CPIC A/B, evidence, drug.
