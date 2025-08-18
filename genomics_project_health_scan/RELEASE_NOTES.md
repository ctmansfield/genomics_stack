# Release Notes — Genomics Project Health Scan

**Version:** 0.1.0
**Date:** 2025-08-18 06:58:24 +0000

## Changes
- Initial release of read-only health scan utility
- Adds `install.sh`, `verify.sh`, `uninstall.sh`
- Adds `tools/health_scan.sh` with checks for directories, disk, Docker, Postgres, and VEP
- Emits timestamped report to `risk_reports/out/health_checks/`

## Verification
1. `tar -xzf genomics_project_health_scan.tgz && cd genomics_project_health_scan`
2. `sudo bash install.sh`
3. `sudo bash verify.sh`
4. Run: `/root/genomics-stack/tools/health_scan/tools/health_scan.sh run`

## Expected Output
- `[verify][OK] Files present.`
- `Report written:` path to a `.txt` file under `risk_reports/out/health_checks/`
