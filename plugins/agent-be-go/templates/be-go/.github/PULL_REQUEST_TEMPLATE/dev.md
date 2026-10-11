## Summary

<!-- What changed and why, in 1-3 sentences. -->

## How to Verify

<!-- The request or command that shows this working, and what a correct result looks like:
     operations touched, manual checks run. "CI is green" is not a verification step. -->

## Checklist

`quality-gate.yml` already ran the full gate on this PR. That file is the list; copying it here only
creates a second one to keep in step. What follows is the part the gate cannot decide.

- [ ] Each new or changed operation in `api/openapi.yaml` lists every error code its handler can
      return (Rule 8), and its tests take their expected values from the spec (Rule 26)
- [ ] A new state-changing operation checks who may call it
- [ ] A new environment variable is read in `internal/config` and listed in the deploy's settings
- [ ] An upstream refusal keeps its code and status (Rule 9)

### If this PR adds a migration

Delete this block if `db/migrations` did not change.

- [ ] Expand only: new columns are nullable or have a constant default; nothing in use is dropped
      or renamed in the same release
- [ ] Each foreign key has its index in the same change (Rule 13); an index on a filled table is
      built concurrently in a `-- +goose NO TRANSACTION` file (Rule 12)
- [ ] Applied to the dev database with `go tool goose ... up`; CI builds a database from scratch,
      it cannot tell whether dev ran it

### If this PR touches queries

Delete this block if it added no database access.

- [ ] Every list query has `LIMIT` and pages by key; the columns are named (Rule 14)
- [ ] No query runs inside a loop: one query per set (Rule 15)
- [ ] Transactions hold database work only, no HTTP or queue calls (Rule 16)

<details><summary>EXPLAIN (ANALYZE, BUFFERS): required for any table expected past ~100k rows</summary>

```text
paste output here, or state why the table stays small
```

</details>
