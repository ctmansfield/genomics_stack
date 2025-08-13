#!/usr/bin/env bash
set -euo pipefail
if command -v man >/dev/null 2>&1 && [[ -r "man/gitctl.1" ]]; then
  exec man -l man/gitctl.1
else
  exec ${PAGER:-less} docs/gitctl_guide.md
fi
