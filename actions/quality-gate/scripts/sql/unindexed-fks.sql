-- Every foreign key whose columns are not the leading columns of a valid, non-partial index on the
-- referencing table: one row each (table | constraint | columns | referenced table). PostgreSQL
-- never indexes the referencing side by itself, so a delete or key update on the referenced table
-- scans this one. An index with the key's columns first in any order counts, wider indexes and
-- primary or unique keys too; a partial, expression or INVALID index does not. Run by the quality
-- gate (stacks be-go and be-axum) on the database the migrations built from zero.
select c.conrelid::regclass as table_name,
       c.conname as constraint_name,
       (select string_agg(a.attname, ', ' order by k.ord)
          from unnest(c.conkey) with ordinality as k(attnum, ord)
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) as fk_columns,
       c.confrelid::regclass as references_table
from pg_constraint c
join pg_class rel on rel.oid = c.conrelid
join pg_namespace ns on ns.oid = rel.relnamespace
where c.contype = 'f'
  and ns.nspname not in ('pg_catalog', 'information_schema')
  and ns.nspname !~ '^pg_toast'
  and not exists (
    select 1
    from pg_index i
    where i.indrelid = c.conrelid
      and i.indisvalid
      and i.indpred is null
      and (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey
  )
order by 1, 2;
