task_db_schema() {
  say "Applying base schema (uploads + staging + guards)"
  PGPASSWORD="$PGPASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$PGUSER" -d "$PGDB" <<'SQL'
create table if not exists uploads(
  id bigserial primary key,
  original_name text,
  kind text,
  status text default 'received',
  user_email text,
  email_norm text generated always as (coalesce(user_email,'')) stored,
  stored_path text,
  bytes bigint,
  sha256 text,
  notes text,
  created_at timestamptz default now()
);
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
create index if not exists idx_staging_upload on staging_array_calls(upload_id);
create index if not exists idx_staging_rsid on staging_array_calls(rsid);

create unique index if not exists uploads_unique_emailsha
  on uploads(email_norm, sha256)
  where status <> 'duplicate';

create or replace function mark_dup_upload() returns trigger as $$
declare keep_id bigint;
begin
  select id into keep_id from uploads
   where sha256 = NEW.sha256
     and coalesce(user_email,'') = coalesce(NEW.user_email,'')
     and id <> NEW.id
   order by id asc limit 1;
  if keep_id is not null then
    update uploads
       set status='duplicate',
           notes = coalesce(notes,'') || format(' duplicate_of=%s;', keep_id)
     where id = NEW.id;
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_mark_dup_upload on uploads;
create trigger trg_mark_dup_upload after insert on uploads for each row execute function mark_dup_upload();
SQL
  ok "DB schema/guards applied"
}
register_task "db-schema" "Create/ensure uploads + staging tables & guards" task_db_schema "Modifies DB schema."
