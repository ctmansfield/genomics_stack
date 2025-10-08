# ---- ClinPGx (PharmGKB) ------------------------------------------------------
.PHONY: migrate/clinpgx labels/dry labels/run

PGHOST ?= 192.168.1.225
PGPORT ?= 5432
PGDATABASE ?= genome_db
PGUSER ?= genouser
PHARMGKB_LABELS ?= /mnt/nas_storage/ref/pharmgkb/drugLabels.tsv
PHARMGKB_LICENSE ?= CC BY-SA 4.0
PHARMGKB_VERSION ?= $(shell date +%Y-%m)

migrate/clinpgx:
	@psql -h $(PGHOST) -p $(PGPORT) -U $(PGUSER) -d $(PGDATABASE) \
	  -f migrations/2025-10-07b_clinpgx_core_compat.sql

labels/dry:
	@. .venv_gs2/bin/activate && \
	  PHARMGKB_LABELS="$(PHARMGKB_LABELS)" \
	  PHARMGKB_LICENSE="$(PHARMGKB_LICENSE)" \
	  PHARMGKB_VERSION="$(PHARMGKB_VERSION)" \
	  CLINPGX_SKIP_KS=1 \
	  python scripts/adapters/clinpgx_ingest_labels.py --dry-run

labels/run:
	@. .venv_gs2/bin/activate && \
	  PHARMGKB_LABELS="$(PHARMGKB_LABELS)" \
	  PHARMGKB_LICENSE="$(PHARMGKB_LICENSE)" \
	  PHARMGKB_VERSION="$(PHARMGKB_VERSION)" \
	  CLINPGX_SKIP_KS=1 \
	  python scripts/adapters/clinpgx_ingest_labels.py

.PHONY: clinpgx
clinpgx: migrate/clinpgx labels/run
