## Summary

<!-- What changed and why, in 1-3 sentences. -->

## How to Verify

<!-- What a reviewer does on a simulator to see this working, and what a correct result looks
     like: the screen, the account or data it needs, the locale. "CI is green" is not a
     verification step. Attach a screenshot of each changed screen, light and dark. -->

## Checklist

`quality-gate.yml` already ran the full gate on this PR: format, lint, the catalog, error codes,
privacy manifest, build with zero warnings, tests, coverage, the accessibility audit and client
drift. Nothing it decides is repeated below; what follows is what it cannot decide.

- [ ] Each changed screen was opened on a simulator in every shipped locale, at the largest
      Dynamic Type size, in light and dark
- [ ] A new primary screen has its accessibility audit test (AGENTS.md Rule 24)
- [ ] New copy reads naturally in every locale; no translation is a placeholder (Rule 6)
- [ ] A new error code shows a message that tells the person what to do next (Rule 12)

### If this PR copies a new spec from the backend

Delete this block if `Packages/AppCore/Sources/APIClient/openapi.json` did not change.

- [ ] The backend change it copies is merged, or ships before this app version
- [ ] Every new `ProblemCode` case is handled on every screen that can receive it
- [ ] The problem-type base did not change (a changed base turns every error in installed apps into
      the generic message)
