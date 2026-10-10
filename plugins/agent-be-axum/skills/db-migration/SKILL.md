---
name: db-migration
description: Writes a PostgreSQL schema change for this Rust service as a new sqlx migration that deploys without downtime - expand, backfill, contract - and refreshes the offline query data. Use when a task adds, alters or drops a table, column, index, constraint or enum value. Not for a query change that leaves the schema as it is, and never for editing a migration a protected branch already has.
---

# Database migration

A merged migration never changes; every schema change is a new file. Commands and file names for
each step are in [references/steps.md](references/steps.md).

1. **Plan the phases.** Split the change into expand (additive, old code keeps working), backfill
   (batched data moves) and contract (removal once no deployed code reads the old shape). Each phase
   is its own migration and its own pull request when old and new code must overlap.
   Done when every phase has one line saying what it changes and which code version it waits for.
2. **Write the expand migration.** New columns are nullable or have a constant default; a new index
   on an existing table is built concurrently in a file of its own that starts with the
   no-transaction marker; a new foreign key gets its index in the same file; a constraint on
   existing rows is added not valid and validated in a later file; a new enum value gets a file of
   its own.
   Done when the migration check passes on the new file.
3. **Apply it from scratch and refresh the query data.** Done when the migrations apply to an empty
   database, the offline query data is regenerated and the build passes offline.
4. **Prove it.** One test at the repo seam for the behaviour the change enables, red first.
   Done when the gates pass, the foreign-key index check included.
