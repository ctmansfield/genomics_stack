# ------------------------------------------------------------------------------
ENV_SOURCE := . tools/env/load_env.sh;
# Genomics Stack — VEP Pipeline Makefile
# One-liners for cache prep, verify, annotation, and import verification.
# All paths/vars can be overridden: make <target> VAR=VALUE
# ------------------------------------------------------------------------------

# --- Defaults (override on the CLI) -------------------------------------------
REPO        ?= /root/genomics-stack
ASSEMBLY    ?= GRCh38
VEP_IMAGE   ?= ensemblorg/ensembl-vep:release_111.0
CACHE_DIR   ?= /mnt/nas_storage/vep/cache
REF_DIR     ?= /mnt/nas_storage/vep/reference
PGURL       ?= postgresql://postgres:postgres@localhost:5432/postgres

# For annotate/import targets
INPUT       ?= /tmp/test.vcf
OUT_TSV     ?= /mnt/nas_storage/reports/out.tsv
FORKS       ?= 8
CHUNK_SIZE  ?= 150000
RESUME      ?= true
HEADER      ?= true
CHROM_COL   ?= 1
TABLE       ?= public.annotated_variants_staging

# --- Helpers ------------------------------------------------------------------
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help
.PHONY: help vep-install vep-verify vep-update-cache annotate manifest histogram import-schema import-verify promote verify-all

# --- Help ---------------------------------------------------------------------
help:
	@echo ""
	@echo "Make targets (override vars like INPUT=... OUT_TSV=...):"
	@echo "  make vep-install            # prepare container + dirs (no cache changes)"
	@echo "  make vep-verify             # canary run through wrapper (requires FASTA/cache)"
	@echo "  make vep-update-cache       # EXPLICIT cache install/update via INSTALL.pl"
	@echo "  make annotate               # run VEP annotator → TSV"
	@echo "  make manifest               # write manifest for OUT_TSV"
	@echo "  make histogram              # write per-chrom histogram for OUT_TSV"
	@echo "  make import-schema          # create DB tables & view"
	@echo "  make import-verify          # COPY → staging + row/shape checks"
	@echo "  make promote                # promote staging → main"
	@echo "  make verify-all             # annotate → manifest → import-verify (end-to-end)"
	@echo ""
	@echo "Common overrides:"
	@echo "  ASSEMBLY=$(ASSEMBLY)  VEP_IMAGE=$(VEP_IMAGE)"
	@echo "  INPUT=$(INPUT)"
	@echo "  OUT_TSV=$(OUT_TSV)"
	@echo "  PGURL=$(PGURL)"
	@echo ""

# --- VEP env lifecycle --------------------------------------------------------
vep-install:
	@echo "[make] vep-install"
	ASSEMBLY=$(ASSEMBLY) VEP_IMAGE=$(VEP_IMAGE) CACHE_DIR=$(CACHE_DIR) REF_DIR=$(REF_DIR) \
	bash tools/vep_cache_update/install.sh

vep-verify:
	@echo "[make] vep-verify"
	ASSEMBLY=$(ASSEMBLY) CACHE_DIR=$(CACHE_DIR) REF_DIR=$(REF_DIR) \
	bash tools/vep_cache_update/verify.sh

vep-update-cache:
	@echo "[make] vep-update-cache"
	ASSEMBLY=$(ASSEMBLY) VEP_IMAGE=$(VEP_IMAGE) CACHE_DIR=$(CACHE_DIR) REF_DIR=$(REF_DIR) \
	bash tools/vep_cache_update/update_cache.sh

# --- Annotation ---------------------------------------------------------------
annotate:
	@echo "[make] annotate"
	test -f "$(INPUT)" || { echo "[ERR] INPUT not found: $(INPUT)"; exit 1; }
	mkdir -p "$$(dirname "$(OUT_TSV)")"
	scripts/vep/vep_annotate.py \
	  --vcf "$(INPUT)" \
	  --out-tsv "$(OUT_TSV)" \
	  --assembly "$(ASSEMBLY)" \
	  --forks "$(FORKS)" \
	  --chunk-size "$(CHUNK_SIZE)" \
	  $(if $(filter $(RESUME),true),--resume,) \
	  --vep-path scripts/vep/vep.sh
	@echo "[OK] wrote $(OUT_TSV)"

# --- File verification helpers -----------------------------------------------
manifest:
	@echo "[make] manifest"
	test -f "$(OUT_TSV)" || { echo "[ERR] OUT_TSV not found: $(OUT_TSV)"; exit 1; }
	tools/import_verify/make_manifest.sh "$(OUT_TSV)" "$(HEADER)"

histogram:
	@echo "[make] histogram"
	test -f "$(OUT_TSV)" || { echo "[ERR] OUT_TSV not found: $(OUT_TSV)"; exit 1; }
	tools/import_verify/make_histogram.sh "$(OUT_TSV)" "$(CHROM_COL)" "$(HEADER)"

# --- Database schema & import -------------------------------------------------
import-schema:
	@echo "[make] import-schema"
	psql "$(PGURL)" -v ON_ERROR_STOP=1 -f sql/schema_vep.sql

import-verify:
	@echo "[make] import-verify"
	test -f "$(OUT_TSV)" || { echo "[ERR] OUT_TSV not found: $(OUT_TSV)"; exit 1; }
	PGURL="$(PGURL)" tools/import_verify/verify_import.sh "$(OUT_TSV)" "$(TABLE)"

promote:
	@echo "[make] promote staging → main"
	psql "$(PGURL)" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
TRUNCATE public.annotated_variants;
INSERT INTO public.annotated_variants SELECT * FROM public.annotated_variants_staging;
TRUNCATE public.annotated_variants_staging;
COMMIT;
SQL

# --- End-to-end shortcut ------------------------------------------------------
verify-all: annotate manifest import-schema import-verify
	@echo "[OK] end-to-end file verified and loaded (staging)."

# --- Verify an already-imported DNA/variants file against DB -------------------
# Usage:
#   make verify-dna FILE=/mnt/nas_storage/incoming/variants.tsv TABLE=public.annotated_variants_staging
verify-dna:
	@echo "[make] verify-dna: FILE=$(FILE) TABLE=$(TABLE)"
	PGURL="$(PGURL)" tools/import_verify/verify_dna_import.sh \
	  --file "$(FILE)" \
	  --table "$(TABLE)" \
	  --identity "chrom||'|'||pos||'|'||ref||'|'||alt" \
	  --header "$(HEADER)"


# Re-declare default vars (non-secret). Password via ~/.pgpass.
ASSEMBLY    ?= GRCh38
VEP_IMAGE   ?= ensemblorg/ensembl-vep:release_111.0
CACHE_DIR   ?= /mnt/nas_storage/vep/cache
REF_DIR     ?= /mnt/nas_storage/vep/reference
INPUT       ?= /tmp/test.vcf
OUT_TSV     ?= /mnt/nas_storage/reports/out.tsv
FORKS       ?= 8
CHUNK_SIZE  ?= 150000
RESUME      ?= true
HEADER      ?= true
CHROM_COL   ?= 1
TABLE       ?= public.annotated_variants_staging

vep-install:
	$(ENV_SOURCE) bash tools/vep_cache_update/install.sh

vep-verify:
	$(ENV_SOURCE) bash tools/vep_cache_update/verify.sh

annotate:
	$(ENV_SOURCE) test -f "$(INPUT)" || { echo "[ERR] INPUT not found: $(INPUT)"; exit 1; }
	$(ENV_SOURCE) mkdir -p "$$(dirname "$(OUT_TSV)")"
	$(ENV_SOURCE) scripts/vep/vep_annotate.py \
	  --vcf "$(INPUT)" \
	  --out-tsv "$(OUT_TSV)" \
	  --assembly "$(ASSEMBLY)" \
	  --forks "$(FORKS)" \
	  --chunk-size "$(CHUNK_SIZE)" \
	  $(if $(filter $(RESUME),true),--resume,) \
	  --vep-path scripts/vep/vep.sh
	@echo "[OK] wrote $(OUT_TSV)"

manifest:
	$(ENV_SOURCE) tools/import_verify/make_manifest.sh "$(OUT_TSV)" "$(HEADER)"

histogram:
	$(ENV_SOURCE) tools/import_verify/make_histogram.sh "$(OUT_TSV)" "$(CHROM_COL)" "$(HEADER)"

import-schema:
	$(ENV_SOURCE) psql -v ON_ERROR_STOP=1 -f sql/schema_vep.sql

import-verify:
	$(ENV_SOURCE) tools/import_verify/verify_import.sh "$(OUT_TSV)" "$(TABLE)"

verify-dna:
	$(ENV_SOURCE) tools/import_verify/verify_dna_import.sh \
	  --file "$(FILE)" \
	  --table "$(TABLE)" \
	  --header "$(HEADER)"

# --- added by lint-baseline-v1 ---
# >>> lint-baseline-v1
.PHONY: lint format precommit-install

precommit-install:
	pre-commit install

lint:
	pre-commit run --all-files

format:
	ruff --config pyproject.ruff.toml format .
# <<< lint-baseline-v1
