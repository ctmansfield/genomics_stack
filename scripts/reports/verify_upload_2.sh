#!/usr/bin/env bash
# Verify required artifacts for upload_2.
# No strict mode. No 'exit'. No env sourcing. Pure file checks.

fail(){ echo "[verify_upload_2] FAIL: $1" >&2; failed=1; }
ok(){   echo "[verify_upload_2] OK: $1" >&2; }

failed=0
OUT="reports/upload_2"
[ -d "$OUT" ] || fail "Missing $OUT"

# Main report
[ -s "$OUT/ctd_report_v2.html" ] || fail "ctd_report_v2.html missing/empty"
[ -s "$OUT/ctd_report_v2.pdf" ]  || fail "ctd_report_v2.pdf missing/empty"
[ "${failed:-0}" -eq 0 ] && ok "Main report HTML/PDF present"

# Expression Balance CSVs (warn if empty)
for f in ctd_expr_balance_genes.csv ctd_expr_balance_chemicals.csv ctd_expr_balance_kpis.csv ctd_expr_balance_sentinels.csv; do
  if [ -f "$OUT/$f" ]; then
    if [ -s "$OUT/$f" ]; then ok "$f present"; else echo "[verify_upload_2] WARN: $f exists but empty" >&2; fi
  fi
done

# DDI overlay artifacts
[ -s "$OUT/ctd_ddi_patient_overlay.csv" ]  || fail "ctd_ddi_patient_overlay.csv missing/empty"
[ -s "$OUT/ctd_ddi_patient_overlay.html" ] || fail "ctd_ddi_patient_overlay.html missing/empty"
[ "${failed:-0}" -eq 0 ] && ok "DDI overlay CSV/HTML present"

if [ "${failed:-0}" -eq 0 ]; then
  echo "[verify_upload_2] All checks passed."
else
  echo "[verify_upload_2] One or more checks failed. See messages above." >&2
fi
# end
