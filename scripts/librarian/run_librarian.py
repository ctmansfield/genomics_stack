#!/usr/bin/env python3
import argparse, csv, json, os, sys, time
from pathlib import Path
import psycopg

PG_DSN = os.getenv("PG_DSN") or \
         f"postgresql://{os.getenv('PGUSER','genouser')}:{os.getenv('PGPASSWORD','')}" \
         f"@{os.getenv('PGHOST','localhost')}:{os.getenv('PGPORT','5432')}/{os.getenv('PGDATABASE','genome_db')}"

def _conn():
    return psycopg.connect(PG_DSN, autocommit=True)

def start_job(cur, summary):
    cur.execute("INSERT INTO public.librarian_jobs(summary) VALUES (%s) RETURNING job_id", (summary,))
    return cur.fetchone()[0]

def finish_job(cur, job_id, status="ok"):
    cur.execute("UPDATE public.librarian_jobs SET finished_at=now(), status=%s WHERE job_id=%s", (status, job_id))

def sync_clinvar(args):
    """Ingest a pre-extracted ClinVar TSV (rsid, clnsig_raw, review_stars, conditions, last_eval_date)."""
    tsv = Path(args.tsv)
    if not tsv.exists():
        print(f"ClinVar TSV not found: {tsv}", file=sys.stderr); sys.exit(2)

    with _conn() as con, con.cursor() as cur, open(tsv, newline="") as f:
        job_id = start_job(cur, f"clinvar sync from {tsv}")
        r = csv.DictReader(f, delimiter="\t")
        rows = 0
        for row in r:
            cur.execute("""
                INSERT INTO public.clinvar_by_rsid(rsid, clnsig_raw, review_stars, conditions, last_eval_date)
                VALUES (%s,%s,%s,%s,%s)
                ON CONFLICT (rsid) DO UPDATE
                SET clnsig_raw=EXCLUDED.clnsig_raw,
                    review_stars=EXCLUDED.review_stars,
                    conditions=EXCLUDED.conditions,
                    last_eval_date=EXCLUDED.last_eval_date
            """, (row["rsid"], row.get("clnsig_raw"), int(row.get("review_stars") or 0),
                  row.get("conditions"), row.get("last_eval_date")))
            rows += 1
        cur.execute("""
          INSERT INTO public.librarian_artifacts(job_id, kind, path, rows, meta)
          VALUES (%s,%s,%s,%s,%s)
        """, (job_id, "clinvar_tsv", str(tsv), rows, json.dumps({"note":"loaded"})))
        finish_job(cur, job_id)
        print(f"Loaded ClinVar rows: {rows}")

def sync_vep(args):
    """Ingest a simple VEP TSV (rsid, gene_symbol, consequence, impact, cadd_phred, revel_score, spliceai_max, extras_json)."""
    tsv = Path(args.tsv)
    if not tsv.exists():
        print(f"VEP TSV not found: {tsv}", file=sys.stderr); sys.exit(2)
    with _conn() as con, con.cursor() as cur, open(tsv, newline="") as f:
        job_id = start_job(cur, f"vep sync from {tsv}")
        r = csv.DictReader(f, delimiter="\t")
        rows = 0
        for row in r:
            cur.execute("""
              INSERT INTO public.vep_by_rsid(rsid, gene_symbol, consequence, impact, cadd_phred, revel_score, spliceai_max, extras)
              VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
              ON CONFLICT (rsid) DO UPDATE SET
                gene_symbol=EXCLUDED.gene_symbol,
                consequence=EXCLUDED.consequence,
                impact=EXCLUDED.impact,
                cadd_phred=EXCLUDED.cadd_phred,
                revel_score=EXCLUDED.revel_score,
                spliceai_max=EXCLUDED.spliceai_max,
                extras=EXCLUDED.extras
            """, (
                row["rsid"], row.get("gene_symbol"), row.get("consequence"), row.get("impact"),
                _f(row.get("cadd_phred")), _f(row.get("revel_score")), _f(row.get("spliceai_max")),
                _jsonsafe(row.get("extras_json"))
            ))
            rows += 1
        cur.execute("""
          INSERT INTO public.librarian_artifacts(job_id, kind, path, rows, meta)
          VALUES (%s,%s,%s,%s,%s)
        """, (job_id, "vep_tsv", str(tsv), rows, json.dumps({})))
        finish_job(cur, job_id)
        print(f"Loaded VEP rows: {rows}")

def _f(x):
    try: return float(x) if x not in (None,"","NA",".") else None
    except: return None

def _jsonsafe(s):
    try: return json.loads(s) if s else None
    except: return None

def curate_queue(args):
    """
    Minimal automation:
    - For each queued rsid:
      * look up VEP -> gene_symbol + consequence
      * create a reasonable default mapping into curated_mappings
        (e.g., missense_variant -> effect_kind='protein_function', direction='unknown')
    - DOES NOT call an external LLM (hook left in place).
    """
    CONSEQ_DEFAULTS = {
        "missense_variant": ("protein_function", "unknown", 0.5),
        "synonymous_variant": ("expression", "unknown", 0.1),
        "intron_variant": ("splicing", "unknown", 0.3),
    }
    with _conn() as con, con.cursor() as cur:
        job_id = start_job(cur, "curate queue (scripted defaults)")
        cur.execute("""
          SELECT cq_id, rsid FROM public.curation_queue
          WHERE state='pending' AND rsid IS NOT NULL
          ORDER BY cq_id
          LIMIT %s
        """, (args.limit,))
        todo = cur.fetchall()
        done = 0
        for cq_id, rsid in todo:
            cur.execute("SELECT gene_symbol, consequence FROM public.vep_by_rsid WHERE rsid=%s", (rsid,))
            row = cur.fetchone()
            if not row:
                # leave pending for LLM/manual
                continue
            gene_symbol, consequence = row
            ekind, direction, mag = CONSEQ_DEFAULTS.get(consequence, ("protein_function","unknown",0.4))
            cur.execute("""
              INSERT INTO public.curated_mappings
                (rsid, gene_symbol, effect_kind, direction, magnitude, zygosity_rule,
                 evidence_level, evidence_source, evidence_notes)
              VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
              ON CONFLICT DO NOTHING
            """, (rsid, gene_symbol, ekind, direction, mag, 'het=0.5,hom=1.0',
                  'research', 'script_default', f"heuristic from consequence={consequence}"))
            cur.execute("UPDATE public.curation_queue SET state='done' WHERE cq_id=%s", (cq_id,))
            done += 1
        finish_job(cur, job_id)
        print(f"curated: {done}; left pending: {len(todo)-done}")

def apply_curations(args):
    """
    Move curated_mappings -> variant_catalog/variant_effects and optional gene/process/system wires.
    """
    with _conn() as con, con.cursor() as cur:
        job_id = start_job(cur, "apply curated_mappings")
        # ensure genes/variants exist
        cur.execute("""
          INSERT INTO public.gene_catalog(gene_symbol)
          SELECT DISTINCT gene_symbol FROM public.curated_mappings
          ON CONFLICT DO NOTHING
        """)
        cur.execute("""
          INSERT INTO public.variant_catalog(rsid, gene_symbol)
          SELECT DISTINCT rsid, gene_symbol FROM public.curated_mappings
          ON CONFLICT DO NOTHING
        """)
        # write effects
        cur.execute("""
          INSERT INTO public.variant_effects(rsid, gene_symbol, effect_kind, direction, magnitude, zygosity_rule, evidence, source, notes)
          SELECT rsid, gene_symbol, effect_kind, direction::text, magnitude, zygosity_rule, evidence_level::text, evidence_source, evidence_notes
          FROM public.curated_mappings
          ON CONFLICT (rsid, gene_symbol, effect_kind) DO UPDATE
            SET direction=EXCLUDED.direction,
                magnitude=EXCLUDED.magnitude,
                zygosity_rule=EXCLUDED.zygosity_rule,
                evidence=EXCLUDED.evidence,
                source=EXCLUDED.source,
                notes=EXCLUDED.notes
        """)
        finish_job(cur, job_id)
        print("applied curated mappings.")

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("sync-clinvar"); a.add_argument("--tsv", required=True); a.set_defaults(func=sync_clinvar)
    b = sub.add_parser("sync-vep");     b.add_argument("--tsv", required=True); b.set_defaults(func=sync_vep)
    c = sub.add_parser("curate-queue"); c.add_argument("--limit", type=int, default=100); c.set_defaults(func=curate_queue)
    d = sub.add_parser("apply-curations"); d.set_defaults(func=apply_curations)

    args = ap.parse_args(); args.func(args)

if __name__ == "__main__":
    main()
