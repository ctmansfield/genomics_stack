# CTD Report v2 convenience targets
# Non-invasive: no env sourcing, no DB vars. Only passes patient via PGOPTIONS.
# Usage:
#   make report_v2              # patient=2 default
#   make report_v2 PATIENT=3    # switch patient
#   make overlay_pdf            # render standalone DDI overlay PDF
#   make verify                 # check artifacts
#   make open                   # try to open main PDF
#   make clean_artifacts        # remove generated HTML/PDF (keeps CSVs)

PATIENT ?= 2
REPORTS_DIR := reports/upload_2
PIPELINE := scripts/reports/run_ctd_report_pipeline.sh
OVERLAY_PDF := scripts/reports/ddi_overlay_pdf.sh
VERIFY := scripts/reports/verify_upload_2.sh

.PHONY: report_v2 overlay_pdf verify open clean_artifacts ctd_help
.DEFAULT_GOAL := ctd_help

ctd_help:
	@echo "CTD Report v2 targets:"
	@echo "  make report_v2 [PATIENT=N]  - Build + inject + render main PDF (default PATIENT=$(PATIENT))"
	@echo "  make overlay_pdf            - Render standalone DDI overlay PDF"
	@echo "  make verify                 - Verify artifacts in $(REPORTS_DIR)"
	@echo "  make open                   - Open main PDF (xdg-open/open)"
	@echo "  make clean_artifacts        - Remove generated HTML/PDF only"

report_v2:
	@echo "[make] Running CTD v2 pipeline for patient upload_id=$(PATIENT)"
	@PGOPTIONS='-c app.patient_upload_id=$(PATIENT)' $(PIPELINE)

overlay_pdf:
	@echo "[make] Rendering standalone DDI overlay PDF"
	@$(OVERLAY_PDF)

verify:
	@$(VERIFY)

open:
	@pdf="$(REPORTS_DIR)/ctd_report_v2.pdf"; \
	if [ ! -s "$$pdf" ]; then \
	  echo "[make] ERROR: $$pdf not found or empty. Run 'make report_v2' first." >&2; \
	  exit 1; \
	fi; \
	if command -v xdg-open >/dev/null 2>&1; then \
	  xdg-open "$$pdf" >/dev/null 2>&1 || true; \
	elif command -v open >/dev/null 2>&1; then \
	  open "$$pdf" >/dev/null 2>&1 || true; \
	else \
	  echo "[make] No opener found. PDF at: $$pdf"; \
	fi

clean_artifacts:
	@echo "[make] Cleaning HTML/PDF artifacts in $(REPORTS_DIR)"
	@rm -f $(REPORTS_DIR)/ctd_report_v2.html \
	       $(REPORTS_DIR)/ctd_report_v2.pdf \
	       $(REPORTS_DIR)/ctd_ddi_patient_overlay.html \
	       $(REPORTS_DIR)/ctd_ddi_patient_overlay.pdf
	@echo "[make] Note: CSVs preserved. Remove manually if desired:"
	@echo "       rm -f $(REPORTS_DIR)/ctd_ddi_patient_overlay.csv"
