## Summary

<!-- What changed and why, in 1-3 sentences. Say whether this is hand-written content or a
     change to the generators or the workflows themselves. -->

## How to Verify

<!-- `bun run dev` (or `bun run preview` for the Cloudflare `wrangler dev` preview) and check the affected page(s) render correctly — a successful `bun run build` alone does not confirm the rendered output. -->

## Checklist

`quality-gate.yaml` already ran the full gate on this PR, and pre-commit ran
`scripts/check/gates.list` before each commit. That gate is the list; copying it here only
creates a second one to keep in step, and the copy is what goes stale. Nothing the gate
decides is repeated below. This repo has no test runner and no i18n layer, so neither applies.

- [ ] `_meta.js` updated for any content file added, removed, or renamed under
      `content/` (nav order and titles stay in sync)
- [ ] If this PR changes the doc/changelog generation scripts: re-ran them locally
      and committed the resulting output
- [ ] Every claim a changed page makes about the documented repository is true at its
      current commit
- [ ] No dead internal links or broken anchors introduced
