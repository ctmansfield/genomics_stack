#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 -m pip install -U pip >/dev/null 2>&1 || true
pip install radon xenon >/dev/null 2>&1 || true
echo "==== Radon CC (functions) ===="
radon cc -s -a ingest ingest_worker lib scripts snp_enrichment_system || true
echo "==== Radon MI (maintainability) ===="
radon mi -s ingest ingest_worker lib scripts snp_enrichment_system || true
echo "==== Xenon thresholds (B/B/B, non-fatal) ===="
xenon --max-absolute B --max-modules B --max-average B ingest ingest_worker lib scripts snp_enrichment_system || true
