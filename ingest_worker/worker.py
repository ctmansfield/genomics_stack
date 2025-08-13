import os, time, pathlib, traceback
import chardet
import psycopg

PGHOST = os.getenv("PGHOST","db")
PGPORT = int(os.getenv("PGPORT","5432"))
PGUSER = os.getenv("PGUSER","genouser")
PGPASSWORD = os.getenv("PGPASSWORD","")
PGDATABASE = os.getenv("PGDATABASE","genomics")
DATA_DIR = pathlib.Path(os.getenv("DATA_DIR","/data"))
POLL_SEC = float(os.getenv("POLL_SEC","3"))

DDL = """
create table if not exists staging_array_calls(
  id bigserial primary key,
  upload_id bigint references uploads(id) on delete cascade,
  sample_label text,
  rsid text,
  chrom text,
  pos integer,
  allele1 text,
  allele2 text,
  genotype text,
  raw_line text,
  created_at timestamptz default now()
);
create index if not exists staging_array_calls_upload_id on staging_array_calls(upload_id);
create index if not exists staging_array_calls_rsid on staging_array_calls(rsid);
"""

def get_con():
  return psycopg.connect(host=PGHOST, port=PGPORT, user=PGUSER, password=PGPASSWORD, dbname=PGDATABASE)

def ensure_ddl():
  with get_con() as con:
    con.execute(DDL)

def claim_one():
  with get_con() as con:
    row = con.execute("""
      with c as (
        select id from uploads
        where status in ('received','unzipped')
        order by id
        limit 1
        for update skip locked
      )
      update uploads u
         set status = 'processing'
      from c
      where u.id = c.id
      returning u.id, u.original_name, u.stored_path, u.sample_label, u.kind, u.status
    """).fetchone()
  return row

def detect_encoding(p: pathlib.Path) -> str:
  with p.open('rb') as f:
    head = f.read(200_000)
  guess = chardet.detect(head) or {}
  return guess.get("encoding") or "utf-8"

def parse_txt(upload_id: int, sample_label: str, p: pathlib.Path, cur) -> int:
  n = 0
  enc = detect_encoding(p)
  with p.open('r', encoding=enc, errors='ignore') as f:
    # find header
    header = None
    for line in f:
      if line.startswith('#') or not line.strip():
        continue
      header = line.rstrip('\n')
      break
    if header is None:
      return 0
    cols = [c.strip().lower() for c in header.split('\t')]
    use_alleles = ('allele1' in cols and 'allele2' in cols)
    use_geno = ('genotype' in cols)

    for line in f:
      if not line or line.startswith('#') or not line.strip():
        continue
      parts = line.rstrip('\n').split('\t')
      if len(parts) < len(cols):
        continue
      rec = dict(zip(cols, parts))
      rsid = rec.get('rsid') or None
      chrom = (rec.get('chromosome') or rec.get('chr') or '').strip()
      if chrom:
        c = chrom.upper().replace('CHROMOSOME','').replace('CHR','').strip()
        if c == '23': c='X'
        if c == '24': c='Y'
        if c in ('M','MT'): c='MT'
        chrom = c
      else:
        chrom = None
      pos_txt = rec.get('position') or rec.get('pos') or None
      pos = int(pos_txt) if (pos_txt and pos_txt.isdigit()) else None
      allele1 = rec.get('allele1') if use_alleles else None
      allele2 = rec.get('allele2') if use_alleles else None
      genotype = rec.get('genotype') if use_geno else ((allele1 or '') + (allele2 or '') or None)

      cur.execute("""
        insert into staging_array_calls(upload_id,sample_label,rsid,chrom,pos,allele1,allele2,genotype,raw_line)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s)
      """, (upload_id, sample_label, rsid, chrom, pos, allele1, allele2, genotype, line.strip()))
      n += 1
  return n

def process_upload(row) -> int:
  up_id, orig, stored, label, kind, _ = row
  p = pathlib.Path(stored)

  candidates = []
  if str(orig).lower().endswith('.zip'):
    zdir = p.parent / (p.stem + "_unzipped")
    if zdir.is_dir():
      candidates = sorted(zdir.rglob("*.txt"))
  else:
    candidates = [p]

  inserted_total = 0
  with get_con() as con:
    with con.cursor() as cur:
      for filep in candidates:
        if not filep.exists() or filep.suffix.lower() != '.txt':
          continue
        inserted_total += parse_txt(up_id, label or p.stem, filep, cur)
      if inserted_total > 0:
        cur.execute("update uploads set status='parsed', notes=coalesce(notes,'') || %s where id=%s",
                    (f" parsed_rows={inserted_total};", up_id))
      else:
        cur.execute("update uploads set status='no_rows', notes=coalesce(notes,'') || %s where id=%s",
                    (" no usable rows;", up_id))
  return inserted_total

def main():
  ensure_ddl()
  while True:
    try:
      row = claim_one()
      if not row:
        time.sleep(POLL_SEC)
        continue
      try:
        n = process_upload(row)
        print(f"[worker] upload {row[0]} → {n} rows", flush=True)
      except Exception as e:
        tb = traceback.format_exc()
        with get_con() as con:
          con.execute("update uploads set status='error', notes=left(%s,1000) where id=%s",
                      (f"{type(e).__name__}: {e}", row[0]))
        print(f"[worker] ERROR on {row[0]}: {e}\n{tb}", flush=True)
    except Exception as outer:
      print(f"[worker] poll error: {outer}", flush=True)
      time.sleep(2)

if __name__ == "__main__":
  main()
