#!/usr/bin/env python3
import os, sys, csv, psycopg2
from psycopg2.extras import execute_values

ALLOWED = {"activates","inhibits","binds","modifies","other"}

def main():
    if len(sys.argv) != 2:
        print("Usage: load_ctd_action_map.py data/ctd_action_map.tsv", file=sys.stderr)
        sys.exit(1)

    tsv_path = sys.argv[1]
    if not os.path.exists(tsv_path):
        print(f"Not found: {tsv_path}", file=sys.stderr)
        sys.exit(1)

    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD"),
        dbname=os.environ.get("PGDATABASE", "postgres"),
    )
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS public.ctd_action_map (
          action_norm   text PRIMARY KEY,
          action_family text NOT NULL CHECK (action_family IN ('activates','inhibits','binds','modifies','other'))
        );
    """)

    # Deduplicate by action_norm (last wins)
    dedup = {}
    with open(tsv_path, "r", newline="") as f:
        rdr = csv.reader(f, delimiter="\t")
        for r in rdr:
            if not r or r[0].strip().startswith("#"):
                continue
            action_norm = r[0].strip().lower()
            action_family = r[1].strip().lower()
            if action_family not in ALLOWED:
                print(f"Skipping {action_norm!r}: invalid family {action_family!r}", file=sys.stderr)
                continue
            dedup[action_norm] = action_family   # last wins

    rows = [(k, v) for k, v in dedup.items()]
    if rows:
        execute_values(cur, """
            INSERT INTO public.ctd_action_map (action_norm, action_family)
            VALUES %s
            ON CONFLICT (action_norm) DO UPDATE SET action_family = EXCLUDED.action_family
        """, rows)
    conn.commit()
    cur.close()
    conn.close()
    print(f"Loaded {len(rows)} rows into public.ctd_action_map")

if __name__ == "__main__":
    main()
