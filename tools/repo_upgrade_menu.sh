#!/usr/bin/env bash
# repo_upgrade_menu.sh
# Menu-driven script to roll in (and roll back) structured repo improvements.
# Patches included:
#   0001 Linting/Formatting/Types (ruff, black, mypy, pre-commit, editorconfig)
#   0002 Refactor Scaffold (radon/xenon, complexity audit script + docs)
#   0003 Error Handling & Validation (custom exceptions, config, logging)
#   0004 Dockerization (Dockerfile.app, .dockerignore, compose.override.yml)
#   0005 Testing Framework (pytest baseline + example test)
#   0006 CI/CD (GitHub Actions for lint/type/test; optional Docker release)
#
# Default repo path: /root/genomics-stack (override via --repo DIR or REPO_DIR)
# State & backups live under: $REPO_DIR/.genomics_patches
#
set -euo pipefail

VERSION="1.0.0"
REPO_DIR="${REPO_DIR:-/root/genomics-stack}"
PATCH_ROOT="$REPO_DIR/.genomics_patches"
BACKUP_DIR="$PATCH_ROOT/backups"
APPLIED_DIR="$PATCH_ROOT/applied"
LOG_FILE="$PATCH_ROOT/upgrade.log"

usage() {
  cat <<'USAGE'
Usage:
  repo_upgrade_menu.sh [--repo DIR] [--apply-all] [--rollback PATCH_ID|all] [--verify] [--push]
Options:
  --repo DIR         Target repository directory (default: /root/genomics-stack or $REPO_DIR)
  --apply-all        Apply all patches 0001..0006 in order
  --rollback ID      Roll back a specific patch (e.g., 0003) or "all"
  --verify           Run verification checks
  --push             Git add/commit/push changes (interactive branch detection)
  -y, --yes          Non-interactive (assume yes where applicable)
  -h, --help         Show this help
USAGE
}

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

confirm() {
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then return 0; fi
  read -r -p "$1 [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

require_git_clean_or_autocommit() {
  pushd "$REPO_DIR" >/dev/null
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: $REPO_DIR is not a git repository." >&2
    popd >/dev/null
    exit 1
  fi
  local status
  status="$(git status --porcelain)"
  if [[ -n "$status" ]]; then
    echo "Working tree is not clean."
    if confirm "Auto-commit current changes before proceeding?"; then
      git add -A
      git commit -m "chore(pre-patch): auto-commit before applying patches $(date -Iseconds)" || true
    else
      echo "Please commit or stash your changes and retry."
      popd >/dev/null
      exit 1
    fi
  fi
  popd >/dev/null
}

ensure_dirs() {
  mkdir -p "$PATCH_ROOT" "$BACKUP_DIR" "$APPLIED_DIR"
  touch "$LOG_FILE"
}

# Utility: backup a file if it exists
backup_file() {
  local f
  f="$1" patch="$2"
  if [[ -f "$f" ]]; then
    local rel
    rel="${f#$REPO_DIR/}"
  local dir
  dir="$BACKUP_DIR/$patch/$(dirname "$rel")"
    mkdir -p "$dir"
    cp -a "$f" "$dir/"
  fi
}

# Utility: record file path in applied manifest
record_applied_file() {
  local patch
  patch="$1" file="$2"
  echo "$file" >> "$APPLIED_DIR/$patch.files"
}

# Utility: write a heredoc to a file (with backup+record)
write_file() {
  local path
  path="$1" patch="$2"
  backup_file "$path" "$patch"
  mkdir -p "$(dirname "$path")"
  # Read from stdin to the target path
  cat > "$path"
  record_applied_file "$patch" "$path"
}

# Utility: append (with backup+record)
append_file() {
  local path
  path="$1" patch="$2"
  backup_file "$path" "$patch"
  mkdir -p "$(dirname "$path")"
  cat >> "$path"
  record_applied_file "$patch" "$path"
}

# Rollback helper
rollback_patch() {
  local patch
  patch="$1"
  local manifest
  manifest="$APPLIED_DIR/$patch.files"
  if [[ ! -f "$manifest" ]]; then
    echo "No manifest found for $patch; nothing to roll back."
    return 0
  fi
  while IFS= read -r f; do
    # If a backup exists for this file in this patch, restore; else remove new file
    local rel
    rel="${f#$REPO_DIR/}"
    local bak
    bak="$BACKUP_DIR/$patch/$rel"
    if [[ -f "$bak" ]]; then
      cp -a "$bak" "$f"
    else
      rm -f "$f"
      # Prune empty dirs
      rmdir --ignore-fail-on-non-empty -p "$(dirname "$f")" || true
    fi
  done < "$manifest"
  rm -f "$manifest"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "revert(patch-$patch): rollback via repo_upgrade_menu.sh" || true
  echo "Rolled back patch $patch."
}

# -------------------- PATCH 0001: Linting --------------------
apply_0001() {
  local P
  P="0001"
  log "Applying $P: Linting/Formatting/Types"
  require_git_clean_or_autocommit
  ensure_dirs
  # Files
  write_file "$REPO_DIR/pyproject.toml" "$P" <<'EOF'
[tool.black]
line-length = 100
target-version = ["py311","py312"]

[tool.ruff]
line-length = 100
extend-exclude = [".venv","metabase_data","risk_reports","db_data",".genomics_patches"]
select = ["E","F","I","UP","B","SIM","W"]
ignore = ["E203","W503"]

[tool.ruff.lint.isort]
known-first-party = ["lib","ingest","ingest_worker","snp_enrichment_system","scripts"]

[tool.ruff.format]
quote-style = "double"
EOF

  write_file "$REPO_DIR/mypy.ini" "$P" <<'EOF'
[mypy]
python_version = 3.12
ignore_missing_imports = True
warn_unused_ignores = True
warn_return_any = False
disallow_untyped_defs = False
EOF

  write_file "$REPO_DIR/.pre-commit-config.yaml" "$P" <<'EOF'
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.5.7
    hooks:
      - id: ruff
      - id: ruff-format
  - repo: https://github.com/psf/black
    rev: 24.4.2
    hooks:
      - id: black
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: end-of-file-fixer
      - id: trailing-whitespace
EOF

  write_file "$REPO_DIR/.editorconfig" "$P" <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2

[*.py]
indent_size = 4
EOF

  # Install tools locally (best-effort)
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install -U pip >/dev/null 2>&1 || true
    python3 -m pip install ruff black mypy pre-commit >/dev/null 2>&1 || true
    (cd "$REPO_DIR" && pre-commit install) || true
  fi
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "patch-0001: linting baseline (ruff/black/mypy/pre-commit/.editorconfig)"
  log "Patch $P applied."
}

# -------------------- PATCH 0002: Refactor scaffold --------------------
apply_0002() {
  local P
  P="0002"
  log "Applying $P: Refactor scaffold"
  require_git_clean_or_autocommit
  ensure_dirs
  write_file "$REPO_DIR/tools/complexity_audit.sh" "$P" <<'EOF'
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
EOF
  chmod +x "$REPO_DIR/tools/complexity_audit.sh"

  write_file "$REPO_DIR/docs/refactor-playbook.md" "$P" <<'EOF'
# Refactor Playbook (SRP-first)

**Principles**
- Single Responsibility: each function does one thing.
- Pure helpers: isolate transformation logic from I/O.
- Dependency injection: pass in DB/session/clients instead of importing globals.

**Workflow**
1) Run `tools/complexity_audit.sh` to identify hotspots.
2) Extract pure helpers: `load_and_validate`, `transform`, `upsert_rows`.
3) Add unit tests around helpers before moving logic.
4) Keep I/O at the edges (`main()` orchestrates).

**Example**
```python
def load_and_validate(path: str) -> list[Record]: ...
def transform(records: list[Record]) -> list[Row]: ...
def upsert_rows(conn, rows: list[Row]) -> int: ...
def main(path: str, conn) -> int:
    return upsert_rows(conn, transform(load_and_validate(path)))
```
EOF

  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "patch-0002: refactor scaffold (complexity audit + playbook)"
  log "Patch $P applied."
}

# -------------------- PATCH 0003: Error handling & validation --------------------
apply_0003() {
  local P
  P="0003"
  log "Applying $P: Error handling & validation"
  require_git_clean_or_autocommit
  ensure_dirs

  write_file "$REPO_DIR/lib/errors.py" "$P" <<'EOF'
class GenomicsError(Exception):
    """Base class for domain errors."""

class DataValidationError(GenomicsError):
    """Raised when input data fails validation."""

class ExternalServiceError(GenomicsError):
    """Raised when an external service (e.g., DB, HTTP) fails."""
EOF

  write_file "$REPO_DIR/support/logging.ini" "$P" <<'EOF'
[loggers]
keys=root

[handlers]
keys=console

[formatters]
keys=std

[logger_root]
level=INFO
handlers=console

[handler_console]
class=StreamHandler
level=INFO
formatter=std
args=(sys.stdout,)

[formatter_std]
format=%(asctime)s %(levelname)s %(name)s - %(message)s
EOF

  write_file "$REPO_DIR/support/config.py" "$P" <<'EOF'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    pg_dsn: str

    class Config:
        env_file = ".env"

settings = Settings()
EOF

  write_file "$REPO_DIR/docs/error-handling-and-validation.md" "$P" <<'EOF'
# Error Handling & Validation

- Use `lib.errors` for domain-specific exceptions.
- Configure logging with `support/logging.ini`.
- Load env config via `support.config.Settings` (pydantic-settings).

**DB Safety Example**
```python
cur.execute("INSERT INTO snps (rsid, pos) VALUES (%s, %s)", (rsid, pos))
```
EOF

  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install pydantic-settings >/dev/null 2>&1 || true
  fi

  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "patch-0003: error handling & validation (errors.py, logging.ini, config.py + docs)"
  log "Patch $P applied."
}

# -------------------- PATCH 0004: Dockerization --------------------
apply_0004() {
  local P
  P="0004"
  log "Applying $P: Dockerization"
  require_git_clean_or_autocommit
  ensure_dirs

  write_file "$REPO_DIR/Dockerfile.app" "$P" <<'EOF'
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS builder
WORKDIR /app
COPY pyproject.toml* requirements*.txt* /app/ 2>/dev/null || true
RUN python -m pip install -U pip && \
    if [ -f requirements.txt ]; then pip wheel --wheel-dir=/wheels -r requirements.txt; else pip wheel --wheel-dir=/wheels ruff black mypy pytest; fi

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN adduser --disabled-password --gecos "" app && mkdir -p /app && chown -R app:app /app
USER app
WORKDIR /app
COPY --from=builder /wheels /wheels
RUN python -m pip install --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY . /app
CMD ["python","-m","ingest_worker.main"]
EOF

  write_file "$REPO_DIR/.dockerignore" "$P" <<'EOF'
.venv
__pycache__/
*.pyc
metabase_data/
db_data/
risk_reports/
.genomics_patches/
EOF

  write_file "$REPO_DIR/compose.override.yml" "$P" <<'EOF'
services:
  ingest-worker:
    build:
      context: .
      dockerfile: Dockerfile.app
    env_file: .env
    depends_on: [ db ]
    volumes:
      - /mnt/nas_storage/vep/cache:/vep/cache:ro
      - /mnt/nas_storage/vep/reference:/vep/reference:ro
    healthcheck:
      test: ["CMD","python","-c","print('ok')"]
      interval: 30s
      timeout: 5s
      retries: 3
EOF

  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "patch-0004: dockerization (Dockerfile.app, .dockerignore, compose.override.yml)"
  log "Patch $P applied."
}

# -------------------- PATCH 0005: Testing --------------------
apply_0005() {
  local P
  P="0005"
  log "Applying $P: Testing Framework"
  require_git_clean_or_autocommit
  ensure_dirs

  write_file "$REPO_DIR/pytest.ini" "$P" <<'EOF'
[pytest]
testpaths = tests
addopts = -q --maxfail=1 --disable-warnings
EOF

  write_file "$REPO_DIR/tests/test_placeholder.py" "$P" <<'EOF'
def test_placeholder():
    assert 1 + 1 == 2
EOF

  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "patch-0005: testing baseline (pytest config + placeholder test)"
  log "Patch $P applied."
}

# -------------------- PATCH 0006: CI/CD --------------------
apply_0006() {
  local P
  P="0006"
  log "Applying $P: CI/CD (GitHub Actions)"
  require_git_clean_or_autocommit
  ensure_dirs

  write_file "$REPO_DIR/.github/workflows/ci.yml" "$P" <<'EOF'
name: CI
on:
  pull_request:
  push:
    branches: [ main ]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix: { python-version: ["3.11","3.12"] }
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: genomics
        ports: ["5432:5432"]
        options: >-
          --health-cmd="pg_isready -U postgres" --health-interval=10s
          --health-timeout=5s --health-retries=5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: ${{ matrix.python-version }} }
      - name: Cache pip
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: pip-${{ runner.os }}-${{ matrix.python-version }}-${{ hashFiles('**/requirements*.txt','pyproject.toml') }}
      - run: python -m pip install -U pip
      - run: pip install -r requirements.txt ruff black mypy pytest || pip install ruff black mypy pytest
      - run: ruff check .
      - run: ruff format --check .
      - run: black --check .
      - run: mypy ingest ingest_worker lib scripts snp_enrichment_system || true
      - run: pytest
EOF

  write_file "$REPO_DIR/.github/workflows/release-docker.yml" "$P" <<'EOF'
name: Release Docker
on:
  push:
    tags: ["v*.*.*"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: Dockerfile.app
          tags: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
          push: true
EOF

  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -m "patch-0006: CI/CD (GitHub Actions workflows)"
  log "Patch $P applied."
}

apply_all() {
  apply_0001
  apply_0002
  apply_0003
  apply_0004
  apply_0005
  apply_0006
}

verify_all() {
  echo "=== Verification ==="
  (cd "$REPO_DIR" && ruff --version >/dev/null 2>&1 && echo "ruff OK" || echo "ruff not installed (ok)") || true
  (cd "$REPO_DIR" && black --version >/dev/null 2>&1 && echo "black OK" || echo "black not installed (ok)") || true
  (cd "$REPO_DIR" && mypy --version >/dev/null 2>&1 && echo "mypy OK" || echo "mypy not installed (ok)") || true
  (cd "$REPO_DIR" && test -f Dockerfile.app && echo "Dockerfile.app present" || echo "Dockerfile.app missing") || true
  (cd "$REPO_DIR" && test -f .github/workflows/ci.yml && echo "CI workflow present" || echo "CI workflow missing") || true
  (cd "$REPO_DIR" && pytest -q 2>/dev/null || true)
  echo "=== Done ==="
}

git_push() {
  pushd "$REPO_DIR" >/dev/null
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git add -A
  git commit -m "chore(patches): apply/rollback via repo_upgrade_menu.sh" || true
  echo "About to push to origin/$branch"
  if confirm "Proceed with git push?"; then
    git push origin "$branch"
  else
    echo "Skipped push."
  fi
  popd >/dev/null
}

rollback_all() {
  rollback_patch 0006 || true
  rollback_patch 0005 || true
  rollback_patch 0004 || true
  rollback_patch 0003 || true
  rollback_patch 0002 || true
  rollback_patch 0001 || true
}

menu() {
  PS3="Select an option: "
  select opt in \
    "Apply 0001 Linting" \
    "Apply 0002 Refactor Scaffold" \
    "Apply 0003 Error Handling & Validation" \
    "Apply 0004 Dockerization" \
    "Apply 0005 Testing" \
    "Apply 0006 CI/CD" \
    "Apply ALL (0001..0006)" \
    "Rollback a patch" \
    "Rollback ALL patches" \
    "Verify" \
    "Git Push" \
    "Exit"; do
    case $REPLY in
      1) apply_0001 ;;
      2) apply_0002 ;;
      3) apply_0003 ;;
      4) apply_0004 ;;
      5) apply_0005 ;;
      6) apply_0006 ;;
      7) apply_all ;;
      8) read -r -p "Enter patch id (0001..0006): " pid; rollback_patch "$pid" ;;
      9) rollback_all ;;
      10) verify_all ;;
      11) git_push ;;
      12) exit 0 ;;
      *) echo "Invalid option" ;;
    esac
  done
}

# -------------------- Arg parsing --------------------
ASSUME_YES=0
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) shift; REPO_DIR="${1:-$REPO_DIR}";;
      --apply-all) ACTION="apply_all";;
      --rollback) shift; ROLLBACK_TARGET="${1:-}"; ACTION="rollback";;
      --verify) ACTION="verify";;
      --push) ACTION="push";;
      -y|--yes) ASSUME_YES=1;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1"; usage; exit 1;;
    esac
    shift
  done
fi

mkdir -p "$REPO_DIR" || true
ensure_dirs

case "${ACTION:-menu}" in
  apply_all) apply_all ;;
  rollback)
    if [[ -z "${ROLLBACK_TARGET:-}" ]]; then echo "--rollback requires a patch id or 'all'"; exit 1; fi
    if [[ "$ROLLBACK_TARGET" == "all" ]]; then rollback_all; else rollback_patch "$ROLLBACK_TARGET"; fi
    ;;
  verify) verify_all ;;
  push) git_push ;;
  menu) echo "Repo: $REPO_DIR"; echo "Version: $VERSION"; menu ;;
esac
