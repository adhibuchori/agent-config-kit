## Summary

<!-- What changed and why, in 1-3 sentences. -->

## How to Verify

<!-- The request or command that shows this working, and what a correct result looks like:
     endpoints touched, manual checks run, the openapi.json diff if the contract moved. "CI is
     green" is not a verification step. -->

## Checklist

`quality-gate.yml` already ran the full gate on this PR. That file is the list; copying it here only
creates a second one to keep in step, and the copy is what goes stale. Nothing the gate decides is
repeated below; what follows is the part it cannot decide.

- [ ] Every error status a changed handler can return is declared in its `#[utoipa::path]` (Rule 8)
- [ ] A new error code has a message in every client that reads `openapi.json` (Rule 6)
- [ ] A state-changing route checks who may call it
- [ ] Tests go through the seam the caller uses, with values taken from the spec (Rule 26)
- [ ] `.env.ci.example` and `Config` list any new environment variable

### If this PR adds a migration

Delete this block if the schema did not move.

- [ ] Each phase deploys on its own: expand, backfill, contract; old code keeps working after expand
- [ ] Applied to the dev database, and `.sqlx/` regenerated with `cargo sqlx prepare`
- [ ] A new foreign key has its index in the same file (Rule 13); a concurrent index sits alone in a
      `-- no-transaction` file (Rule 12)

### If this PR touches queries

Delete this block if it added no database access.

- [ ] Every list query pages with `LIMIT` and a keyset `WHERE` (Rule 14)
- [ ] No query runs inside a loop; batches use `= ANY($1)` or `UNNEST` (Rule 15)
- [ ] Transactions hold database work only, in a `repo.rs` (Rule 16)
- [ ] Every filtered, sorted or joined column is indexed

<details><summary>EXPLAIN (ANALYZE, BUFFERS): required for any table expected past ~100k rows</summary>

```text
paste output here, or state why the table stays small
```

</details>
