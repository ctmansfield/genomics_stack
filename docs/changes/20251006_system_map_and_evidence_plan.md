System Map & Evidence Framework — Implementation Plan

Suggested path: docs/changes/20251006_system_map_and_evidence_plan.md
Owner: @chad
Status: 🚧 in progress

1) Why / Scope

We’re building a reusable, citation-first Human System Map that connects:

Variants → Genes → Processes (metabolic modules) → Organ Systems

Plus optional links to diseases/traits, biomarkers, and interventions
Every mapping is traceable: evidence items cite papers/databases with quotes/snippets and provenance (source, version, license).

This map is person-agnostic (curated once), and the per-upload pipeline evaluates an individual’s genotypes against it to produce ranked system/process impacts and clinician-oriented reports.

2) Current state (done/working)

 Upload pipeline: uploads, upload_blobs, staging_array_calls; Ancestry DNA 5-col format handled; duplicate detection.

 Reference-aware rare SNPs:

View: public.v_reference_aware_rare (calls ref allele from rsid_annotation, classifies het_alt/hom_alt)

Export: reports/upload_2/reference_aware_rare_snps.csv (+ optional HTML preview)

 System taxonomy scaffolding and report alignment kicking off.

 Process graph core: bio_processes, gene_to_process, process_to_system, variant_effects

Seeds included for MTHFR (one-carbon), HFE (iron handling), COMT (catechol methylation)

 Rollups (per upload):

upload_variant_effects, upload_process_impacts, upload_system_impacts

Functions system_impacts_recalc() (and extended version incl. APOE dose) producing normalized % and simple rank

 APOE pair-aware mapping: v_upload_pair_apoe, v_pair_variant_effects, APOE e2/e4 effects seeded

 Working example (upload_id=2):

Systems scored (e.g., Nutrient Metabolism, Neuro, Detox/Liver, Cardiovascular)

Process top: Methylation / One-carbon via MTHFR C677T (het_alt observed)

3) What we’ll gather (data points & citations)

Variant level: rsID, HGVS, chrom/pos (37/38), ref/alt, genotype class, gnomAD AF (global+subpops), VEP consequence/impact, CADD/REVEL/SpliceAI, ClinVar significance & stars.
Gene level: HGNC/Ensembl/Entrez/UniProt, brief function, LOEUF/constraint, GTEx tissue expression.
Process level: slug/label/desc; Reactome/GO/KEGG links; member genes (role/sign/weight).
System level: canonical systems; process→system weights + direction.
Phenotype/Disease: Mondo/OMIM/DOID; HPO; associations ± effect sizes where available.
Interventions (optional): PharmGKB/CPIC/DrugBank targets and guidance (license aware).
Biomarkers: LOINC/tests, units, reference ranges, which process/system they inform.
Citations: every edge can link 1..N evidence items (PMID/DOI/URL, quote/snippet, level, strength, location in doc, source metadata/version/license).

4) New schema to support citations & provenance (to apply)

Tables (idempotent):

knowledge_sources(source_id, name, kind, uri, version, license, accessed_at, notes)

biblio_refs(citation_id, pmid, doi, url, title, authors, journal, year, publisher, abstract, source_id, extra_ids) + unique index on (pmid/doi/url)

evidence_items(evidence_id, citation_id, supports, strength, level, excerpt, location, notes, added_by, added_at)

variant_effects, gene_to_process, process_to_system: ensure row_id bigserial exists for FK links

Evidence link tables:

evidence_variant_effects(row_id, evidence_id)

evidence_gene_to_process(row_id, evidence_id)

evidence_process_to_system(row_id, evidence_id)

System taxonomy enrichment:

Add display_name, display_order, updated_at; backfill display_name = tag

✅ These DDLs were supplied and applied in earlier steps; keep them in /sql/migrations/20251006_system_map_evidence.sql.

5) Work plan (checklist with acceptance criteria)
A) Evidence & provenance (core)

 Create migration SQL files for (4) above and commit.
AC: All tables exist and are idempotent; re-runs are no-ops.

 Seed knowledge_sources entries for: ClinVar, VEP cache, Reactome, GO, dbSNP, gnomAD, GWAS Catalog (and note license).
AC: Each has name/kind/uri/version/license/accessed_at.

 Add at least one biblio_refs + evidence_items per current seed mapping:
MTHFR→one-carbon; iron_handling→Detox/Liver; COMT→catechol_methyl; APOE e2/e4→lipid metabolism/Cardio/Neuro.
AC: Evidence linked via the evidence_* tables and visible in a verification query.

B) Catalog & adapters

 ClinVar ingest (rsID → significance, review stars, conditions).
AC: Table populated for common rsIDs; evidence rows reference the ClinVar release.

 VEP annotations ingest (consequence/impact, predictors).
AC: VEP rows exist for top hits; sources recorded.

 gnomAD AFs ingest (global + subpop).
AC: rsid_annotation.gnomad_af_global filled for ≥80% of observed rsIDs (where available).

 dbSNP ref alleles sanity pass (we’re using hs37d5 now; optionally add GRCh38).
AC: ≥95% of observed rsIDs in upload resolve a single base ref37/ref38.

C) Process & system coverage

 Expand bio_processes to cover additional modules (e.g., hepcidin axis, fatty-acid oxidation, urea cycle, glutathione, nitric oxide synthase, BH4 pathway, steroidogenesis, thyroid hormone synthesis, immune signaling nodes, detox phases I/II/III).
AC: Each has label/desc + at least 1 source link.

 Map gene_to_process for common clinical genes (APOE, F5, F2, CYPs, SLCs, HFE/TFR2/HAMP, MTR/MTRR, MTHFR/MTHFD1, COMT/MAOA/MAOB, NOS3, GSTM1/T1/P1, SOD2, NQO1…).
AC: ≥50 genes mapped with role/sign/weight and ≥1 citation each.

 Map process_to_system weights/directions (use system taxonomy order: Cardiovascular, Metabolic, Endocrine, Immune, Neuro, Detox/Liver, Nutrient Metabolism, Other).
AC: Each process influences ≥1 system with documented evidence.

D) Rollup & scoring polish

 Verify system_impacts_recalc() and _ext() paths on multiple uploads; handle AF thresholds and missing AF.
AC: Non-empty upload_* tables with normalized %; deterministic across runs.

 Add drivers view per system (top contributing variants/processes with links to evidence).
AC: v_up{upload}_system_drivers returns rows with gene/rsid/effect and resolves to evidence via joins.

E) Reporting & UX

 Add links to download artifacts in clinician HTML (reference-aware CSV; system/process tables).
AC: Report renders sections per system; download buttons work.

 Expose citations: show inline badges ([n] linking to evidence modal) in rule/process/system cards.
AC: Clicking shows title, authors, source, quote, and link.

F) Tooling & governance

 “Librarian” CLI: scripts/librarian/*.py to import datasets and mint evidence links (with --source, --pmid/doi/url, --quote, --edge kind, --match keys).
AC: One command can add/update a mapping and attach citations atomically.

 Tests (smoke + integrity):

FK and not-null constraints; unique citation keys; no dangling evidence links.

Deterministic rollups on a fixed sample upload.
AC: pytest -q green; make verify passes.

 Data dictionary & curation SOPs (how to add a mapping + evidence).
AC: Docs live under docs/curation/.

6) Verification queries (copy/paste friendly)

Top systems for upload 2

SELECT * FROM public.upload_system_impacts
WHERE upload_id=2
ORDER BY system_impact_score DESC NULLS LAST;


Top processes

SELECT * FROM public.upload_process_impacts
WHERE upload_id=2
ORDER BY process_delta DESC NULLS LAST
LIMIT 25;


Top variant effects (with evidence counts)

SELECT uve.*, COUNT(eve.evidence_id) AS n_evidence
FROM public.upload_variant_effects uve
LEFT JOIN public.variant_effects ve ON (ve.rsid=uve.rsid AND ve.gene_symbol=uve.gene_symbol)
LEFT JOIN public.evidence_variant_effects eve ON eve.row_id = ve.row_id
WHERE uve.upload_id=2
GROUP BY uve.upload_id, uve.rsid, uve.gene_symbol, uve.effect_kind, uve.direction,
         uve.magnitude, uve.zygosity_scaled_effect, uve.chromosome, uve.position, uve.allele1, uve.allele2, uve.ref_allele, uve.genotype_class
ORDER BY uve.zygosity_scaled_effect DESC NULLS LAST
LIMIT 25;


Evidence drill-down (process→system)

SELECT p2s.system_tag, bp.label AS process_label, p2s.weight, p2s.direction,
       bi.title, bi.pmid, bi.doi, bi.url, ei.excerpt, ei.location, ks.name AS source, ks.version
FROM public.process_to_system p2s
JOIN public.bio_processes bp ON bp.process_id=p2s.process_id
LEFT JOIN public.evidence_process_to_system eps ON eps.row_id = p2s.row_id
LEFT JOIN public.evidence_items ei ON ei.evidence_id = eps.evidence_id
LEFT JOIN public.biblio_refs bi ON bi.citation_id = ei.citation_id
LEFT JOIN public.knowledge_sources ks ON ks.source_id = bi.source_id
ORDER BY p2s.system_tag, bp.label;

7) Data sources (initial set)

dbSNP (ref allele; rsID normalization)

gnomAD (global & subpop AF)

ClinVar (clinical significance, review stars)

VEP cache (consequence/impact/predictors)

Reactome/GO/Pathway Commons (process membership)

HGNC/Ensembl/UniProt (gene identifiers)

GWAS Catalog/Open Targets (gene/variant ↔ trait)

GTEx (tissue expression)

PharmGKB/CPIC/DrugBank (targets/guidelines; watch license)

8) Pitfalls logged / mitigations

Chromosome normalization (Ancestry format): handle 1–22, X|Y|MT, tolerate chr prefix.

Mitochondrial edge cases: ensure MT coordinates match reference FASTA; skip invalid positions.

Owner/privilege mismatches: standardize ownership to genouser; grant DML on sequences/tables.

Port/env mismatches: API uses PGPORT=5432; health at /healthz.

Ref allele availability: if missing, genotype class becomes nocall/other (excluded from ref-aware table).

Licenses: store knowledge_sources.license; keep raw dumps behind access controls if needed.

9) Deliverables

 /sql/migrations/20251006_system_map_evidence.sql (all DDLs above)

 /scripts/librarian/import_* (ClinVar, VEP, gnomAD, Reactome/GO)

 /docs/curation/SOP_SYSTEM_MAP.md (how to add edges + evidence)

 Updated clinician report with:

system sections in canonical order, normalized % bars

top drivers table per system (variant/gene/process with evidence badges)

downloads: reference_aware_rare_snps.csv (+ HTML preview)

10) Actionable next steps (short)

Commit the migration file for evidence & provenance and taxonomy enrichment.

Register sources (knowledge_sources) and seed biblio_refs + evidence_items for the three current mappings (MTHFR, HFE, COMT) + APOE.

Wire a minimal librarian CLI (add-edge-evidence) to attach citations to any edge in one command.

Add drivers view + inject download links into report.

Start ClinVar & VEP adapters; store citation rows per release.

Expand process coverage and gene mappings with evidence.

11) Done definition (for this milestone)

Evidence schema live; evidence attached to ≥6 edges (MTHFR, HFE, COMT, APOE e2/e4→process/system).

Per-upload rollups produce ranked systems and drivers with citations.

Clinician HTML shows system sections, evidence badges, and download links.

Librarian CLI can add/update a mapping and its citations in one step.

Integrity tests passing; re-runs idempotent.

Appendix: quick CLI ideas

# Add evidence to an existing edge
python scripts/librarian/add_edge_evidence.py \
  --edge variant_effects --rsid rs1801133 --gene MTHFR --effect enzyme_activity \
  --pmid 12345678 --quote "MTHFR converts 5,10-methylene-THF to 5-methyl-THF" \
  --level review --source Reactome --version v88 --url https://...

# Import ClinVar snapshot (records source and version)
python scripts/librarian/import_clinvar.py --vcf /path/clinvar.vcf.gz \
  --source ClinVar --version 2025-09-30