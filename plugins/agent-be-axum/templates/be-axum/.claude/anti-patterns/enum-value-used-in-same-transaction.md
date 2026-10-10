# A new enum value used in the transaction that added it

**Applies to:** migrations that run `ALTER TYPE ... ADD VALUE`.
**Status:** a standing trap (reproduced on PostgreSQL 18.6).

## Symptom

A migration adds a value to an enum and, in the same file, backfills rows or sets a default with
it. It fails with `ERROR: unsafe use of new value "archived" of enum type thing_state` (SQLSTATE
`55P04`, hint: "New enum values must be committed before they can be used").

## Root cause

Since PostgreSQL 12, `ALTER TYPE ... ADD VALUE` may run inside a transaction block, but the new
value cannot be used until that transaction commits. A migration runner that wraps the file in one
transaction makes the add and the use the same transaction. Enum values cannot be dropped either
(`DROP VALUE` is not implemented), so a wrong value stays.

## Fix

- The `ADD VALUE` alone in its migration; the backfill or the default in the next file.
- For a set the product changes, a lookup table with a foreign key, or a `CHECK` constraint
  (changed with `NOT VALID`, then `VALIDATE`), instead of an enum. Keep enums for closed sets.

## When to revisit

If PostgreSQL lets a transaction use the enum values it added.
