-- Every INVALID index: one row each (schema | index | table). A CREATE INDEX CONCURRENTLY that
-- fails leaves one behind, and a retry with IF NOT EXISTS then "succeeds" while it stays INVALID,
-- so the planner never uses it and every write still maintains it. Run by the quality gate (stacks
-- be-go and be-axum) on the database the migrations built from zero.
select n.nspname as schema_name,
       ic.relname as index_name,
       i.indrelid::regclass as table_name
from pg_index i
join pg_class ic on ic.oid = i.indexrelid
join pg_namespace n on n.oid = ic.relnamespace
where not i.indisvalid
  and n.nspname not in ('pg_catalog', 'information_schema')
  and n.nspname !~ '^pg_toast'
order by 1, 2;
