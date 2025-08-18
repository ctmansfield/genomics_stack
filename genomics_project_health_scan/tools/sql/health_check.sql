-- Generic health check queries; safe to run
select now() as db_time;
select current_database() as db;
select schema_name from information_schema.schemata order by 1;
select table_schema, count(*) as table_count
from information_schema.tables
group by 1 order by 1;
