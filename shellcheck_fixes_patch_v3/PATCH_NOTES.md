## Changes applied

- `scripts/dev/gitctl.sh`: split `local safety="..."` into declare + assign (SC2155).
- `scripts/env.sh`:
  - Annotate unused-but-exported config variables with `# shellcheck disable=SC2034`.
  - Replace `export $(grep ... | xargs ...)` with a safe `while read` loop (fixes SC2046).
- `scripts/lib/common.sh`: add `# shellcheck source=/dev/null` before dynamic `source` (SC1090).
- `scripts/tasks/fasta_install.sh`: split `local gz=...` declaration (SC2155).
- `scripts/tasks/report_pdf_any.sh`: quote `$(basename ...)` expansions (SC2046).
- `scripts/tasks/vep_cache_install.sh`:
  - split `local tar=...` declaration (SC2155).
  - rename shadowed `local` variable to `local_path` (SC2316).
- `scripts/tasks/report_top5.sh`:
  - remove leading blank lines so shebang is first (SC1128).
  - replace `sudo bash -lc "cat ... <<'HTML'"` heredocs with `sudo tee` form to avoid quoting issues (SC1078/SC2140).
- `tools/env/load_env.sh`: add `# shellcheck source=/dev/null` (SC1090).
- `tools/repo_upgrade_menu.sh`: split `local dir=...` declaration (SC2155).
- `tools/stage_sample.sh`: disable SC2120 on `PSQL()` wrapper since it may be called with 0 args.
