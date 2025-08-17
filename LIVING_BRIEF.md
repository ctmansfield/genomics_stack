# Genomics Stack — Living Brief

> Keep this file lean. Target ≤300 tokens. Update after meaningful changes.

## 1) Goal & Scope
- **Goal:** End‑to‑end SNP/variant pipeline: ingest → annotate (VEP) → enrich/analyze → risk reporting & BI.
- **Primary users:** Local/cluster Docker stack operators.
- **Success:** Reproducible runs, fast re‑ingest, traceable outputs.

## 2) Architecture (high‑level)
- **Containers:** Postgres + workers + tools (compose‑managed).
- **Data flow:** `ingest/` → staging tables → transforms in `lib/` → enrichment (`snp_enrichment_system/`) → reports in `risk_reports/` + BI (`metabase_data/`).
- **Coordination:** `scripts/` entrypoints + guard utilities in `tools/`.

## 3) Components (repo map)
- `ingest/` – loaders for raw SNP/variant datasets.
- `ingest_worker/` – async/queued ingestion worker.
- `lib/` – shared transforms/utilities.
- `snp_enrichment_system/` – enrichment logic + scripts.
- `risk_reports/` – report renderer outputs.
- `docs/` – ADRs/diagrams (to grow).
- `metabase_data/` – Metabase artifacts for dashboards.
- `compose.yml` – Docker stack.

## 4) Public Interfaces (external contracts)
- **DB:** Postgres schema(s) for BI; stable table/column names.
- **CLI:** `scripts/*.sh` entrypoints (ingest, annotate, enrich, render). *Declare canonical commands below.*
- **Reports:** CSV/HTML/PDF in `risk_reports/out/` (stable filenames).

## 5) Invariants (do not break)
- **IDs:** Use ULID/UUID; never reuse; joins on IDs are immutable.
- **Reference builds:** VEP genome/cache versions pinned per run; record `vep_version`, `cache_release`, `ref_build`.
- **Paths (host):**
  - Repo root: `/root/genomics-stack`
  - Docker PG stack: `/mnt/nas_storage/docker/docker_pg_stack/docker_pg_stack`
  - VEP caches: `/mnt/nas_storage/vep/cache`, refs: `/mnt/nas_storage/vep/reference`
  - Guard script: `/root/genomics-stack/tools/vep_cache_bootstrap_guard.sh`
  - Reports: `/root/genomics-stack/risk_reports/out` (renderer may also write `/mnt/nas_storage/reports`)
- **Operational:** All jobs run inside containers; local env never writes directly to DB.

## 6) Decisions (ADR stubs)
- **DB:** Postgres for storage/analysis.
- **Annotation:** Ensembl VEP + local cache; containerized.
- **BI:** Metabase for exploration; artifact snapshots when feasible.

## 7) Runbook (happy path)
1. `docker compose up -d` (from repo root)
2. `scripts/ingest.sh <dataset>` → staging
3. `scripts/annotate_vep.sh <input.vcf>` → annotated table
4. `scripts/enrich.sh <cohort|panel>` → derived metrics
5. `scripts/render_risk_reports.sh <run_id>` → files in `risk_reports/out`

## 8) Open Questions / TODOs (keep short)
- [ ] Declare canonical CLI surface: exact script names, args, exit codes.
- [ ] Freeze DB schema: schemas, tables, indexes.
- [ ] Add `FEATURE_MATRIX.md` (feature ↔ modules ↔ key functions ↔ tests).
- [ ] Add ADRs under `docs/adr/` (DB choice, VEP cache policy, reporting format).
- [ ] Add C4 Context/Container diagrams in `docs/architecture/`.

## 9) Glossary (handles)
- **VEPCACHE** → local Ensembl caches
- **RISKREP** → risk report renderer
- **ENRICH** → SNP enrichment pipeline
- **METABASE** → dashboards

## 10) Lint & Style Protocol (canon)
- **Config files:** `.ruff.toml` (Python), `.pre-commit-config.yaml` (hooks). Exclude: `risk_reports/out/`, `metabase_data/`, `.ruff_cache/`, `build/`, `dist/`, `.venv/`, `venv/`, `support/`, `.git/`.
- **Python:** Ruff lint + format. Commands: `make format` (ruff format), `make lint` (ruff check --fix + format). Rules: `E,F,W,I,UP`; line length 100; `__init__.py` may re-export (`F401` ignored).
- **Shell:** `shellcheck` + `shfmt` via pre-commit; hooks run on executable shebang files. Add `# shellcheck shell=bash` to lint sourced libs.
- **Workflow:** Install once `make precommit-install`; dev loop `make format && make lint`; CI enforces on PRs and pushes.
- **Policy:** No merges if lint fails; waivers need inline comment and ADR if policy-level.

---
**Maintenance command:** “Refresh the Living Brief to ≤300 tokens; update Components, Interfaces, Decisions, and TODOs from the latest repo.”
