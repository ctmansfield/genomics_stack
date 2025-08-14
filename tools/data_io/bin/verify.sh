#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?Set DATABASE_URL}"
psql "$DATABASE_URL" -f "$(dirname "$0")/../schema/verify_integrity.sql"
