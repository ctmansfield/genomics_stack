#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$ROOT_DIR/lib/common.sh"

task_risk_panel_seed() {
  say "[+] Seeding risk panel (idempotent)…"
  dc exec -T db psql -U "$PGUSER" -d "$PGDB" <<'SQL'
BEGIN;

CREATE TABLE IF NOT EXISTS risk_panel(
  rsid        text NOT NULL,
  gene        text NOT NULL,
  condition   text,
  zygosity    text NOT NULL CHECK (zygosity IN ('any','het','hom')),
  risk_allele text NOT NULL CHECK (risk_allele ~ '^[ACGT]$'),
  weight      int  NOT NULL DEFAULT 1,
  summary     text,
  nutrition   text,
  PRIMARY KEY (rsid, zygosity, risk_allele)
);

CREATE OR REPLACE FUNCTION _rp_upsert(
  _rsid text,_gene text,_cond text,_zyg text,_allele text,_w int,_sum text,_nut text
) RETURNS void
LANGUAGE plpgsql AS $rp$
BEGIN
  INSERT INTO risk_panel(rsid,gene,condition,zygosity,risk_allele,weight,summary,nutrition)
  VALUES(_rsid,_gene,_cond,_zyg,_allele,_w,_sum,_nut)
  ON CONFLICT (rsid, zygosity, risk_allele) DO UPDATE
  SET gene=EXCLUDED.gene,
      condition=EXCLUDED.condition,
      weight=EXCLUDED.weight,
      summary=EXCLUDED.summary,
      nutrition=EXCLUDED.nutrition;
END;
$rp$;

-- Entries (same as one-off above)
SELECT _rp_upsert('rs1801133','MTHFR','Methylation/folate','het','T',1,
  'One T allele may modestly reduce enzyme activity.',
  'Folate-rich diet; discuss supplementation if appropriate.');
SELECT _rp_upsert('rs1801133','MTHFR','Methylation/folate','hom','T',2,
  'Two T alleles associated with larger drop in activity.',
  'Prioritize natural folate; avoid high-dose vitamins without guidance.');
SELECT _rp_upsert('rs1801131','MTHFR','Methylation/folate','het','C',1,
  'May mildly affect methylation pathways.',
  'Greens/legumes; monitor B vitamins as advised.');
SELECT _rp_upsert('rs1801131','MTHFR','Methylation/folate','hom','C',1,
  'Typically smaller effect than C677T.',
  'Balanced diet; avoid self-prescribing high doses.');
SELECT _rp_upsert('rs6025','F5','Thrombosis risk','any','A',2,
  'Increased clotting tendency; context matters.',
  'Hydration, movement on long travel; clinical discussion before procedures.');
SELECT _rp_upsert('rs1799963','F2','Thrombosis risk','any','A',2,
  'Linked to increased clot risk.',
  'Avoid smoking; discuss peri-op risk mitigation if indicated.');
SELECT _rp_upsert('rs4149056','SLCO1B1','Statin myopathy risk','any','C',1,
  'Reduced OATP1B1 function; higher myopathy risk for some statins.',
  'Report muscle symptoms promptly; clinicians may adjust therapy.');

COMMIT;
SQL
  ok "Risk panel seeded."
}

register_task "risk-panel-seed" "Seed/refresh curated risk panel" task_risk_panel_seed
