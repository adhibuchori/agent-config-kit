# One checkout, several sessions, one `.git/index`

**Applies to:** Any repository that more than one agent session works in at a time
**Status:** Permanent (git design: the index belongs to the worktree, not to the process)

## Symptom

You stage two files, and `git diff --cached` shows six. A commit named for one change lands
carrying another session's half-finished work. `git status` reports a file staged while
`git diff --cached` comes back empty.

Each of these looks like a tool lying: a pre-commit hook that secretly re-stages, or a wrapper
returning stale output. Test such a claim before believing it. The usual cause is a race: another
session's `git add` or commit landed between two of your reads, and both reads were right when
taken.

## Root Cause

`.git/index` belongs to the **worktree**, not to the process. Sessions that share a checkout share
one index. Every `git add` from every session collects there, and `git commit` commits the index,
so it sweeps up whatever the others staged.

## Fix

**Commit by pathspec.** `git commit -- <paths>` commits those paths from the working tree and
ignores the rest of the index, so nothing another session staged rides along:

```bash
bash scripts/check/gates.sh --fix <paths>   # format only your own files
git add <new files>                         # a pathspec reaches only tracked files
git commit -F message.txt -- <paths>
git show --stat HEAD                        # read what the commit actually carried
```

- A pathspec commits only files git already tracks. A new file still needs `git add` first, or the
  commit lands without it and says nothing.
- A pathspec commit takes the working tree as it was when the command started. A pre-commit hook
  that rewrote files would leave its fixes outside the commit, so the hook only checks, and you
  format your own paths before committing, never the whole tree, where another session's work in
  progress lives too.
- Read `git show --stat HEAD` after every commit, before pushing. It is the only line that reports
  what happened; everything above it reports intent. agent-core's `post-commit` hook prints the
  same list and warns about paths the pathspec did not name.

## Scope

Concurrent sessions in one checkout. Separate git worktrees each have their own index, which is the
structural fix when sessions run long and independently.

Related: `git-apply-check-passes-then-deletes.md` has the same shape: a guard that passes up front
while the outcome is still wrong. In both, only reading the state after the action proves it.
