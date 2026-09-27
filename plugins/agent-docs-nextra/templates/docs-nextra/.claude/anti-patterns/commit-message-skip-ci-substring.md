# The skip-CI marker anywhere in a commit message silences every workflow

**Applies to:** Any repository whose workflows run on `pull_request` (this one) or `push`
**Status:** Permanent (GitHub Actions behaviour)

## Symptom

A pull request shows no checks at all, or it merges and nothing follows: no deploy, no changelog.
The head commit's check suites list other apps and nothing from GitHub Actions.
Nothing failed, so nothing reports it.

## Root Cause

GitHub skips every `pull_request` run, the `closed` one after a merge included, when the pull
request's head commit message contains one of its skip instructions, such as `skip ci` or `ci skip`
inside square brackets, **anywhere** in the message: subject or body, any case. A `push` run is
skipped the same way by its HEAD commit. The check runs before any workflow file is read, so no
filter in a workflow can undo it.

It lands by accident when text _describes_ the marker, for example a commit body explaining a
workflow that stamps it on its own commits:

- A squash merge copies the body of every squashed commit into one message on `dev`. Once that
  commit is `dev`'s head, the promotion pull request opened from it runs nothing.
- A merge commit carries the pull request's title, so a marker in the title of a pull request into
  `dev` lands in `dev`'s head commit the same way.

## Fix

- Never write the literal marker in a commit message, a PR title or a PR body, not even to describe
  it. Write "the skip-CI marker" instead.
- Merge with `--merge` and turn squash merging off in the repository settings
  (`.claude/OPERATIONS.md` § GitHub and CI). A merge commit does not concatenate the commits'
  bodies.
- A pull request whose head commit carries the marker runs again once a clean commit lands on its
  head branch. A merge that already started nothing cannot be replayed from that event: run the
  deploy by hand, or send the dispatch the changelog listens for.

## Related

The same marker placed on purpose does the same harm: a workflow that stamps it on the commit it
pushes to the development branch disarms the quality gate on every promotion opened from there.
Nothing in `.github/workflows/` writes it, and nothing needs to, since no workflow runs on a push.
