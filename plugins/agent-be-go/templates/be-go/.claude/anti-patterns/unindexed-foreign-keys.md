# Foreign keys without an index

**Applies to:** every migration that adds a foreign key.
**Status:** a standing trap of PostgreSQL itself (the catalog query below was checked on 18.6,
17.11 and 16.15).

## Symptom

Deleting or updating a parent row is slow, and gets slower as the child table grows: each one
scans the child table to check the constraint, under a lock. Joins from parent to child scan too.

## Root cause

The PostgreSQL docs: "the declaration of a foreign key constraint does not automatically create
an index on the referencing columns." A text check over migration or schema files misses cases
that look indexed: the same column name indexed on another table, the key column as the second
column of an index, a composite key, a partial or expression index, an INVALID index.

## Fix

Add the index in the migration that adds the key, with the key's columns leading:

```sql
CREATE INDEX things_owner_id_idx ON things (owner_id);  -- concurrently, in its own file, on a filled table
```

Ask the database, not the files. The quality gate runs this on the database it migrates from
scratch and fails on any row:

```sql
select c.conrelid::regclass as table_name, c.conname as constraint_name
from pg_constraint c
join pg_class rel on rel.oid = c.conrelid
join pg_namespace ns on ns.oid = rel.relnamespace
where c.contype = 'f'
  and ns.nspname not in ('pg_catalog', 'information_schema') and ns.nspname !~ '^pg_toast'
  and not exists (select 1 from pg_index i
                  where i.indrelid = c.conrelid and i.indisvalid and i.indpred is null
                    and (i.indkey::int2[])[0 : cardinality(c.conkey) - 1] @> c.conkey);
```

It accepts an index of exactly the key's columns, one that starts with them (in any order among
themselves), the primary key or a unique constraint leading with them, and an `INCLUDE` index. It
flags partial and expression indexes on purpose. On 18, a `NOT ENFORCED` key needs no index; add
`and c.conenforced` when you use one.

## When to revisit

If PostgreSQL starts indexing foreign keys by itself.
