# Clinician Top-20 Report with System Coverage

Patch name: clinician-top20-system-coverage

Summary
- Deliver a clinician-facing report that prioritizes the Top 20 genetic findings per patient, includes clear biochemical explanations, and guarantees coverage across physiological systems so the big picture is preserved.

Goals and Scope
- Add a system tag per risk rule to group findings by physiological systems (e.g., Cardiovascular, Metabolic, Neuro, Immune, Endocrine, Detox/Liver, Nutrient Metabolism, Other).
- Extend Top-N pipeline to:
  1) Score risk hits (existing) and include VEP fallback (existing).
  2) Apply pair-aware de-duplication (existing via gene_pairs).
  3) Enforce system coverage in Top 20 (new selection step).
- Render clinician-facing HTML/PDF with: RSID, Gene, Title, Zygosity, Clinical impact, Biochemical explanation, Practical notes, Evidence strength; grouped by system.

Non-goals (this patch)
- Deep curation of all rules; we seed minimal examples and allow iteration.
- Introducing a strict enum/foreign-key for systems; initial soft tag only.

Deliverables
1) Schema augmentation
   - risk_rules.system_tag text NOT NULL DEFAULT 'General'.
2) Systems taxonomy doc
   - docs/clinician_report/SYSTEMS_TAXONOMY.md listing systems, display order, and mapping guidance.
3) Selection and coverage logic
   - A report builder (script) that fetches pair-aware candidates and applies system coverage to select Top 20.
4) Clinician report outputs
   - HTML and PDF renderer including biochemical explanations (impact_blurb) and nutrition notes.
5) Verification protocol and examples
   - A reproducible set of commands and acceptance checks; sample outputs checked into risk_reports/out/ (or paths configured).

Acceptance criteria (verify when complete)
- AC1: Schema has risk_rules.system_tag with default populated as 'General'.
- AC2: Systems taxonomy exists and is referenced in the renderer.
- AC3: For any upload_id with >=1 finding per system present, the Top 20 includes at least one entry from each present system.
- AC4: If fewer than 20 candidates exist, report lists all; otherwise 20 with pair-aware de-duplication, then ranked by score with system coverage enforced.
- AC5: Each Top 20 row shows RSID, Gene, Title, Zygosity, Clinical impact, Biochemical explanation (impact_blurb), Nutrition note, Evidence note.
- AC6: HTML and PDF renderers produce outputs without errors for two example uploads (or simulated data); files are created and sizes > 0.

Verification steps (commands)
- Ensure DB ready and risk panel installed:
  - psql -f scripts/sql/risk_panel.sql
- Recalculate risk hits for an example upload:
  - psql -c "SELECT public.risk_hits_recalc(<UPLOAD_ID>);"
- Run report builder (to be added in this patch):
  - python scripts/reports/clinician_top20.py --upload-id <UPLOAD_ID> --out-html ... --out-pdf ...
- Validate ACs:
  - Inspect HTML/PDF for system headers and presence of required fields.
  - Confirm at least one item per present system; count 20 when possible.

Rollout and backout
- Additive schema change; safe to deploy incrementally.
- Backout: renderer can ignore system_tag; column can be left unused or dropped in a later migration if needed.

Risks and mitigations
- Incomplete curation of system tags: provide default 'General'; add taxonomy doc and mapping guidance.
- Divergent env vars across scripts: normalize in the report builder (accept DSN or compose exec db + psql route).
