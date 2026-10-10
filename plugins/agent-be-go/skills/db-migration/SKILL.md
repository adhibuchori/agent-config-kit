---
name: db-migration
description: Writes a PostgreSQL schema change for this Go service as a new goose migration that deploys without downtime - expand, backfill, contract - and regenerates the query code. Use when a task adds, alters or drops a table, column, index, constraint or enum value. Not for a query change on an unchanged schema, and never for editing a migration that is already merged.
---

# Database migration

A merged migration never changes; every schema change is a new file. Commands and file names for
each step are in [references/steps.md](references/steps.md).

1. **Plan the phases.** Split the change into expand (additive, old code keeps working), backfill
   (batched data moves) and contract (removal once no deployed code reads the old shape). Each phase
   is its own migration, and its own pull request when old and new code must overlap.
   Done when every phase has one line saying what it changes and which code version it waits for.
2. **Write the expand migration.** New columns are nullable or have a constant default; a new index
   on an existing table is built concurrently, alone in a file the tool runs outside a transaction;
   a new foreign key gets its index in the same change; a constraint on existing rows is added not
   valid and validated in a later file; the file sets a short lock timeout.
   Done when the migration check passes on the new file.
3. **Apply it and regenerate.** Apply the migrations to the test database through the tests, then
   regenerate the query code.
   Done when the migrations apply cleanly, the generated code is current and the build passes.
4. **Prove it.** One test at the store seam for the behaviour the change enables, red first.
   Done when the gates pass.
