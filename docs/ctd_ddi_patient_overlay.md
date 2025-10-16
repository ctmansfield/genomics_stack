# CTD DDI — Patient Overlay
_Aim: rank chemicals/drugs by how they **increase vs decrease** expression across the patient’s active genes, with clear filters and a whitelist override._

**Status:** stable  
**Outputs:**  
- `reports/upload_2/ctd_ddi_patient_overlay.csv`  
- `reports/upload_2/ctd_ddi_patient_overlay_body.html` (HTML section)  
- `reports/upload_2/ctd_ddi_patient_overlay.html` (standalone HTML)  
- (optional) `reports/upload_2/ctd_ddi_patient_overlay.pdf`

---

## Prereqs

- Postgres env set (same as the rest of the repo):
  ```bash
  export PGHOST=localhost PGPORT=5432 PGUSER=genouser PGDATABASE=genome_db
  export PGPASSWORD='…'
Choose the patient context:

bash
Copy code
export PGOPTIONS='-c app.patient_upload_id=2'
Quick Start
A) Generate the overlay CSV
Default thresholds; no whitelist.

bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh
B) (Optional) HTML + PDF
bash
Copy code
scripts/reports/ctd_ddi_patient_overlay_html.sh

docker run --rm -v "$PWD/reports/upload_2":/data zenika/alpine-chrome:124 \
  --no-sandbox --headless --disable-gpu \
  --print-to-pdf="/data/ctd_ddi_patient_overlay.pdf" "file:///data/ctd_ddi_patient_overlay.html"
C) Inject the overlay into the main report
bash
Copy code
scripts/reports/build_ctd_report_v2.sh
scripts/reports/inject_ddi_overlay.sh

# Optional fresh PDF of the full report
docker run --rm -v "$PWD/reports/upload_2":/data zenika/alpine-chrome:124 \
  --no-sandbox --headless --disable-gpu \
  --print-to-pdf="/data/ctd_report_v2.pdf" "file:///data/ctd_report_v2.html"
Tunables (env vars)
Var	Default	What it does
MIN_TOTAL	5	Minimum total expression edges (inc+dec) for a chemical to be considered.
MIN_GENES	2	Minimum distinct patient genes covered for that chemical.
BAL_THR	0.70	Majority threshold for badges: inc_majority / dec_majority else balanced.
TOPN	300	Max rows returned, ordered by score then coverage.
EXCLUDE_REGEX	(set)	Regex (case-insensitive) for obvious non-drug exposures. Set to "" to disable.
WHITELIST_REGEX	""	Optional regex to force-include specific names (e.g., `^(Homocysteine

Notes

The CSV includes an include_reason column: meets_thresholds or whitelist.

Setting EXCLUDE_REGEX="" disables the default “environmental exposures” filter.

Common Recipes
Force-include a few drugs of interest
bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$' \
  MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh
Tighten evidence requirements
bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=8 MIN_GENES=3 BAL_THR=0.70 TOPN=200 \
  scripts/reports/ctd_ddi_patient_overlay.sh
Loosen for exploratory review
bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=3 MIN_GENES=1 BAL_THR=0.65 TOPN=500 \
  scripts/reports/ctd_ddi_patient_overlay.sh
Interpreting Columns
genes_covered: count of distinct patient genes this chemical touches (strict CTD).

inc_n / dec_n: number of increase/decrease expression edges that matched.

total_n: inc_n + dec_n.

inc_frac / dec_frac: proportions of increase/decrease edges.

balance_flag: inc_majority (≥ BAL_THR), dec_majority (≥ BAL_THR), else balanced.

score: total_n * (abs(inc_frac - 0.5) * 2.0) — favors more evidence and stronger tilt.

include_reason: meets_thresholds vs whitelist.

Sanity Checks
bash
Copy code
# CSV present and not empty
head -n 10 reports/upload_2/ctd_ddi_patient_overlay.csv
wc -l    reports/upload_2/ctd_ddi_patient_overlay.csv

# Confirm overlay injection (appears exactly once)
grep -n "DDI overlay" reports/upload_2/ctd_report_v2.html || true
Troubleshooting
Password prompts / connection errors

Ensure PGPASSWORD is exported (not passed as PGPASSWORD='…' only to a single command).

Verify PGOPTIONS='-c app.patient_upload_id=2' is set in the same shell session.

Whitelist did nothing

Regex must match the drug_name exactly as printed. Try anchoring: ^…$.

Confirm include_reason shows whitelist for at least one row.

Rows missing you expected

Lower MIN_TOTAL and/or MIN_GENES.

Set EXCLUDE_REGEX="" to disable environment filters.

PDF small or truncated

Re-open the HTML in a browser to verify visuals.

Re-run chrome container (already pinned to zenika/alpine-chrome:124).

Example One-Liners
bash
Copy code
# Clean pass with strict thresholds, no whitelist
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh

# Force-include homocysteine/ascorbic/estradiol and rebuild full report
EXCLUDE_REGEX="" WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$' \
  MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh && \
scripts/reports/build_ctd_report_v2.sh && \
scripts/reports/inject_ddi_overlay.sh
Last updated: $(date -u +"%Y-%m-%d %H:%M UTC")

install -d docs

cat > docs/ctd_ddi_patient_overlay.md <<'MARKDOWN'
# CTD DDI — Patient Overlay
_Aim: rank chemicals/drugs by how they **increase vs decrease** expression across the patient’s active genes, with clear filters and a whitelist override._

**Status:** stable  
**Outputs:**  
- `reports/upload_2/ctd_ddi_patient_overlay.csv`  
- `reports/upload_2/ctd_ddi_patient_overlay_body.html` (HTML section)  
- `reports/upload_2/ctd_ddi_patient_overlay.html` (standalone HTML)  
- (optional) `reports/upload_2/ctd_ddi_patient_overlay.pdf`

---

## Prereqs

- Postgres env set (same as the rest of the repo):
  ```bash
  export PGHOST=localhost PGPORT=5432 PGUSER=genouser PGDATABASE=genome_db
  export PGPASSWORD='…'
Choose the patient context:

bash
Copy code
export PGOPTIONS='-c app.patient_upload_id=2'
Quick Start
A) Generate the overlay CSV
Default thresholds; no whitelist.

bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh
B) (Optional) HTML + PDF
bash
Copy code
scripts/reports/ctd_ddi_patient_overlay_html.sh

docker run --rm -v "$PWD/reports/upload_2":/data zenika/alpine-chrome:124 \
  --no-sandbox --headless --disable-gpu \
  --print-to-pdf="/data/ctd_ddi_patient_overlay.pdf" "file:///data/ctd_ddi_patient_overlay.html"
C) Inject the overlay into the main report
bash
Copy code
scripts/reports/build_ctd_report_v2.sh
scripts/reports/inject_ddi_overlay.sh

# Optional fresh PDF of the full report
docker run --rm -v "$PWD/reports/upload_2":/data zenika/alpine-chrome:124 \
  --no-sandbox --headless --disable-gpu \
  --print-to-pdf="/data/ctd_report_v2.pdf" "file:///data/ctd_report_v2.html"
Tunables (env vars)
Var	Default	What it does
MIN_TOTAL	5	Minimum total expression edges (inc+dec) for a chemical to be considered.
MIN_GENES	2	Minimum distinct patient genes covered for that chemical.
BAL_THR	0.70	Majority threshold for badges: inc_majority / dec_majority else balanced.
TOPN	300	Max rows returned, ordered by score then coverage.
EXCLUDE_REGEX	(set)	Regex (case-insensitive) for obvious non-drug exposures. Set to "" to disable.
WHITELIST_REGEX	""	Optional regex to force-include specific names (e.g., `^(Homocysteine

Notes

The CSV includes an include_reason column: meets_thresholds or whitelist.

Setting EXCLUDE_REGEX="" disables the default “environmental exposures” filter.

Common Recipes
Force-include a few drugs of interest
bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$' \
  MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh
Tighten evidence requirements
bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=8 MIN_GENES=3 BAL_THR=0.70 TOPN=200 \
  scripts/reports/ctd_ddi_patient_overlay.sh
Loosen for exploratory review
bash
Copy code
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=3 MIN_GENES=1 BAL_THR=0.65 TOPN=500 \
  scripts/reports/ctd_ddi_patient_overlay.sh
Interpreting Columns
genes_covered: count of distinct patient genes this chemical touches (strict CTD).

inc_n / dec_n: number of increase/decrease expression edges that matched.

total_n: inc_n + dec_n.

inc_frac / dec_frac: proportions of increase/decrease edges.

balance_flag: inc_majority (≥ BAL_THR), dec_majority (≥ BAL_THR), else balanced.

score: total_n * (abs(inc_frac - 0.5) * 2.0) — favors more evidence and stronger tilt.

include_reason: meets_thresholds vs whitelist.

Sanity Checks
bash
Copy code
# CSV present and not empty
head -n 10 reports/upload_2/ctd_ddi_patient_overlay.csv
wc -l    reports/upload_2/ctd_ddi_patient_overlay.csv

# Confirm overlay injection (appears exactly once)
grep -n "DDI overlay" reports/upload_2/ctd_report_v2.html || true
Troubleshooting
Password prompts / connection errors

Ensure PGPASSWORD is exported (not passed as PGPASSWORD='…' only to a single command).

Verify PGOPTIONS='-c app.patient_upload_id=2' is set in the same shell session.

Whitelist did nothing

Regex must match the drug_name exactly as printed. Try anchoring: ^…$.

Confirm include_reason shows whitelist for at least one row.

Rows missing you expected

Lower MIN_TOTAL and/or MIN_GENES.

Set EXCLUDE_REGEX="" to disable environment filters.

PDF small or truncated

Re-open the HTML in a browser to verify visuals.

Re-run chrome container (already pinned to zenika/alpine-chrome:124).

Example One-Liners
bash
Copy code
# Clean pass with strict thresholds, no whitelist
EXCLUDE_REGEX="" WHITELIST_REGEX="" MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh

# Force-include homocysteine/ascorbic/estradiol and rebuild full report
EXCLUDE_REGEX="" WHITELIST_REGEX='^(Homocysteine|Ascorbic Acid|Estradiol)$' \
  MIN_TOTAL=5 MIN_GENES=2 BAL_THR=0.70 TOPN=300 \
  scripts/reports/ctd_ddi_patient_overlay.sh && \
scripts/reports/build_ctd_report_v2.sh && \
scripts/reports/inject_ddi_overlay.sh
Last updated: $(date -u +"%Y-%m-%d %H:%M UTC")
MARKDOWN

makefile
Copy code
::contentReference[oaicite:0]{index=0}
