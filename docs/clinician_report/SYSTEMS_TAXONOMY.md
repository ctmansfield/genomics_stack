# Systems Taxonomy (Clinician Report)

Purpose
- Standardize physiological system tags for grouping and coverage in clinician-facing reports.

Canonical systems and display order
1. Cardiovascular
2. Metabolic
3. Endocrine
4. Immune
5. Neuro
6. Detox/Liver
7. Nutrient Metabolism
8. Other

Tagging guidance
- Choose the primary system where the variant’s dominant effect is most clinically relevant.
- If multiple systems apply, select the one most impactful for decision-making and note cross-links in evidence_notes.
- Use 'Other' sparingly when unclear; prefer mapping to one of the main systems.

Examples (illustrative)
- APOE ε4: Cardiovascular (lipids) or Neuro (cognitive) — prefer Cardiovascular if lipid rules are present; document crossover.
- MTHFR C677T: Nutrient Metabolism (folate one-carbon), with Endocrine/Neuro impacts noted in evidence.
- HFE C282Y: Detox/Liver (iron handling), support note for Hematology (if later expanded).

Mapping file (optional)
- A future CSV (gene_or_rule → system_tag) can be used to bootstrap consistent tagging before embedding into risk_rules.
