Patch 0022-vep-guard-and-report-fixes

Adds:
- tools/vep_cache_bootstrap_guard.sh
  * Prompts before overwriting or downloading a different VEP release
  * Defaults to VEP_IMAGE=ensemblorg/ensembl-vep:release_111.0 unless overridden
  * Honors DRY_RUN=1
- Symlink tools/vep_cache_bootstrap_safe.sh -> guard (convenience)

Usage:
  # Safe default (asks before replace)
  /mnt/nas_storage/tools/vep_cache_bootstrap_guard.sh

  # Dry-run (no changes)
  DRY_RUN=1 /mnt/nas_storage/tools/vep_cache_bootstrap_guard.sh

  # Force without prompt
  /mnt/nas_storage/tools/vep_cache_bootstrap_guard.sh --force

  # Pin explicitly to a different release on purpose
  VEP_IMAGE=ensemblorg/ensembl-vep:release_114.2 /mnt/nas_storage/tools/vep_cache_bootstrap_guard.sh
