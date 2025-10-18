#!/usr/bin/env bash
# Convenience runner: export gene annotations and inject into CTD report v2.
# No strict mode; never 'exit'. Assumes DB env + PGOPTIONS already set by your venv/workflow.

fail(){ echo "[add_gene_annotations] ERROR: $1" >&2; failed=1; }
note(){ echo "[add_gene_annotations] $1" >&2; }

failed=0
EXPORT="scripts/reports/gene_annotations_export.sh"
INJECT="scripts/reports/inject_gene_annotations.sh"

[ -x "$EXPORT" ] || fail "Missing or non-executable $EXPORT"
[ -x "$INJECT" ] || fail "Missing or non-executable $INJECT"
[ "${failed:-0}" -eq 0 ] || { echo "[add_gene_annotations] Aborting."; return 1 2>/dev/null || exit 1; }

note "Exporting gene annotations..."
"$EXPORT" || fail "Export failed"

note "Injecting gene annotations..."
"$INJECT" || fail "Injection failed"

[ "${failed:-0}" -eq 0 ] && note "Done."
# end
