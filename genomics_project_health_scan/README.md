# Genomics Project — Health Scan

Lightweight, read-only checks to quickly validate your local genomics stack is healthy and that expected data & directories exist.

## What it does

- Verifies presence of key directories:
  - `/mnt/nas_storage/incoming`
  - `/mnt/nas_storage/docker/docker_pg_stack/docker_pg_stack`
  - `/mnt/nas_storage/vep/cache`
  - `/mnt/nas_storage/vep/reference`
  - `/root/genomics-stack/tools/vep_cache_bootstrap_guard.sh`
  - `/root/genomics-stack/risk_reports/out`
  - `/mnt/nas_storage/reports`
- Prints disk usage for `/mnt/nas_storage` and cache dirs
- Optional Postgres checks (if `PGHOST/PGUSER/PGPASSWORD` env vars present)
- Optional Docker Compose status for the Postgres stack
- VEP sanity check (version, cache species dirs)
- Lists newest items in `incoming/`
- Emits a timestamped report file under `risk_reports/out/health_checks` by default

> Note: All checks are read-only and safe.

## Quickstart

```bash
tar -xzf genomics_project_health_scan.tgz
cd genomics_project_health_scan
sudo bash install.sh
sudo bash verify.sh
# Run a full scan (read-only)
/root/genomics-stack/tools/health_scan/tools/health_scan.sh run
```

## Environment

- Optional Postgres env vars: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`
- Optional `COMPOSE_DIR` if your docker compose dir differs (defaults to `/mnt/nas_storage/docker/docker_pg_stack/docker_pg_stack`)
- Optional output dir: `HEALTH_OUT_DIR` (defaults to `/root/genomics-stack/risk_reports/out/health_checks`)
