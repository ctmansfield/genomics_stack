# shellcheck shell=bash
task_apply_db_guards() {
  say "applying DB guards (idempotent)"
  PGPASSWORD="$PGPASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$PGUSER" -d "$PGDB" <<'SQL'
alter table uploads
  add column if not exists email_norm text generated always as (coalesce(user_email,'')) stored;

create unique index if not exists uploads_unique_emailsha
  on uploads(email_norm, sha256)
  where status <> 'duplicate';

create or replace function mark_dup_upload() returns trigger as $$
declare keep_id bigint;
begin
  select id into keep_id
    from uploads
   where sha256 = NEW.sha256
     and coalesce(user_email,'') = coalesce(NEW.user_email,'')
     and id <> NEW.id
   order by id asc
   limit 1;

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
create trigger trg_mark_dup_upload
after insert on uploads
for each row execute function mark_dup_upload();
SQL
  ok "DB guards applied"
}
register_task "apply-db-guards" "Uniq index + duplicate trigger (safe to re-run)" task_apply_db_guards "Modifies DB schema."
