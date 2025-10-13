# genomics_stack
genomics database and snp mapping

## Adapters (added 2025-10-10)

### dbSNP (GRCh37) → `public.dbsnp_by_rsid`
- **Script:** `scripts/adapters/dbsnp_ingest_refs.py`
- **Input:** dbSNP b151 (GRCh37p13) All VCF (`All_20180423.vcf.gz` + `.tbi`)
- **Scope:** rsIDs present in the active upload (from `staging_array_calls`)
- **Output columns:** `rsid, chromosome, position, ref, alts[], build, updated_at`
- **Run:**
  ```bash
  source .venv_gs2/bin/activate
  export UPLOAD_ID=2
  PYTHONUNBUFFERED=1 python3 scripts/adapters/dbsnp_ingest_refs.py \
    --upload-id "$UPLOAD_ID" \
    --source /mnt/nas_storage/ref/dbsnp/All_20180423.vcf.gz \
    --version "dbSNP b151 (GRCh37p13)" \
    --chunk 5000 --progress-every 50000

Sanity: reports/upload_${UPLOAD_ID}/dbsnp_sample.csv

Index: CREATE INDEX IF NOT EXISTS ix_dbsnp_by_rsid_chr_pos ON public.dbsnp_by_rsid(chromosome, position);

Gene IDs (HGNC / Ensembl / UniProt) → public.gene_identifiers

Script: scripts/adapters/gene_identifiers_ingest.py

Input: HGNC complete set TSV (CC0); optional Ensembl GRCh37 Biomart TSV; optional UniProt TSV.

Output columns: gene_symbol PK, hgnc_id, ensembl_gene_id, uniprot_id, aliases[]

Run (HGNC-only OK):

source .venv_gs2/bin/activate
export UPLOAD_ID=2
python3 scripts/adapters/gene_identifiers_ingest.py \
  --upload-id "$UPLOAD_ID" \
  --hgnc /mnt/nas_storage/ref/ids/hgnc_complete_set.tsv \
  --version "HGNC 2025-10-06 (CC0)" \
  --chunk 5000


Sanity: reports/upload_${UPLOAD_ID}/gene_identifiers_sample.csv

Indices:

CREATE INDEX IF NOT EXISTS ix_gene_identifiers_ensembl ON public.gene_identifiers(ensembl_gene_id);
CREATE INDEX IF NOT EXISTS ix_gene_identifiers_uniprot ON public.gene_identifiers(uniprot_id);
CREATE INDEX IF NOT EXISTS ix_gene_identifiers_aliases_gin ON public.gene_identifiers USING GIN (aliases);

Gene symbol canonicalization

Tables/Views:

gene_identifier_aliases(alias, canonical) — many-to-many

v_gene_alias_unambiguous, v_gene_alias_ambiguous

gene_identifier_overrides(alias, canonical) — manual override (guarded)

v_clinvar_gene_symbols_resolved — adds resolved_symbol and resolution_method

Function: canonical_gene_symbol(sym) — exact → valid override → unambiguous alias → fallback.

Example join using canonical:

SELECT r.rsid, r.raw_symbol, r.resolved_symbol, gi.hgnc_id, gi.ensembl_gene_id
FROM public.v_clinvar_gene_symbols_resolved r
LEFT JOIN public.gene_identifiers gi ON gi.gene_symbol = r.resolved_symbol
LIMIT 20;

License/Sourcing

dbSNP: public domain (NCBI).

HGNC complete set: CC0 (public domain).

Ensembl Biomart: open data with attribution.

UniProt: CC BY 4.0 (attribution).
