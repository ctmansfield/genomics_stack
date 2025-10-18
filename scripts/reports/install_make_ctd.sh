#!/usr/bin/env bash
# Safe installer to wire CTD make targets without breaking your existing Makefile.
# - Creates mk/ctd_report.mk (if missing, or overwrites if you want to paste content)
# - Appends a single include line to Makefile if not present
# - No strict mode, no 'exit'; won't close your shell if sourced.

say(){ echo "[install-make-ctd] $*" >&2; }

# 1) Ensure mk/ exists (does nothing if already there)
mkdir -p mk 2>/dev/null || true

# 2) Check that mk/ctd_report.mk exists (you should have pasted it already)
if [ ! -s mk/ctd_report.mk ]; then
  say "mk/ctd_report.mk not found or empty. Paste the full mk/ctd_report.mk first."
  return 1 2>/dev/null || exit 1
fi

# 3) Ensure Makefile exists
if [ ! -f Makefile ]; then
  say "Makefile not found at repo root."
  return 1 2>/dev/null || exit 1
fi

# 4) Append include if missing (idempotent)
if ! grep -qE '^[[:space:]]*include[[:space:]]+mk/ctd_report\.mk' Makefile; then
  printf '\n# --- CTD Report v2 targets ---\ninclude mk/ctd_report.mk\n' >> Makefile
  say "Appended: include mk/ctd_report.mk"
else
  say "Include already present; no changes."
fi

say "Done. Try: make report_v2  or  make report_v2 PATIENT=3"
