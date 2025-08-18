# shellcheck shell=bash
task_build_images() {
  say "Building images (ingest, ingest_worker)"
  dc build ingest ingest_worker
  ok "build complete"
}
register_task "build-images" "docker compose build ingest & worker" task_build_images
