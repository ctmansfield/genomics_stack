Genomics Stack — Curated Annotations Bootstrap
==============================================

Files
-----
- migrations/20250816_report_curated_view.sql
  Creates `report_curated_join` view (idempotent).

- sql/load_curated_seed.sql
  Loads curated rsid seed data *via STDIN* and upserts into `curated_rsid`,
  mapping `layman_desc` -> `layman_summary`. Uses only columns that are
  guaranteed to exist to avoid NOT NULL violations.

- curation/curated_rsid_seed.csv
  Starter rows with **valid JSON** under `nutrition_support_json`.

How to Apply
------------
# A) Create the view (no environment variables required)
psql -h 127.0.0.1 -p 55432 -U postgres -d genomics -v ON_ERROR_STOP=1       -f migrations/20250816_report_curated_view.sql

# B) Load the CSV via STDIN (IMPORTANT: the '<' redirection)
psql -h 127.0.0.1 -p 55432 -U postgres -d genomics -v ON_ERROR_STOP=1       -f sql/load_curated_seed.sql < curation/curated_rsid_seed.csv

# C) Quick peek
psql -h 127.0.0.1 -p 55432 -U postgres -d genomics       -c "SELECT rsid, left(layman_summary,60) AS preview, nutrition_support::text FROM curated_rsid ORDER BY rsid LIMIT 5;"

Notes
-----
- `sql/load_curated_seed.sql` intentionally uses `\copy ... FROM STDIN` — this keeps the file read on the client side (your shell) and avoids server FS permissions.
- If you *do* prefer server-side COPY, move the CSV into a directory that the DB server user can read (and reference it with absolute path).
- All JSON is valid and will cast cleanly into `jsonb` to prevent the `Token ... invalid` errors you saw earlier.
