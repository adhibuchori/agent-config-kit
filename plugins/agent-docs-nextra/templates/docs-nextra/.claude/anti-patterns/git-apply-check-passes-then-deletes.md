# `git apply --check` passes, then the patch deletes the files

**Applies to:** Any patch built with `git diff --no-index`
**Status:** Permanent (git works as designed)

## Symptom

`git apply --check patch` exits 0. `git apply patch` reports nothing wrong, and `git status` then
shows:

```text
 D CLAUDE.md
 D README.md
?? var/
```

The files you meant to edit are gone, and copies of them appear under a folder named after the
machine's temp path.

## Root Cause

`git diff --no-index a b` writes the **literal paths it was given** into the diff header. Build a
patch by copying a file to a temp folder and diffing against it, and you get:

```diff
--- a/README.md
+++ b/var/folders/.../T/tmpXXXX/README.md
```

`git apply` reads that as one instruction: delete `README.md`, create `var/folders/.../README.md`.
It is not a malformed patch. It is a valid patch for a rename you did not intend, so nothing warns
you. Rewriting the `a/` side and missing the `b/` side is easy, because the `b/` path is long and
scrolls off.

## Why `--check` does not save you

`git apply --check` answers "can this patch be applied cleanly?", not "is this the change you
meant?" A delete-and-recreate applies perfectly cleanly. **A green `--check` is a merge-conflict
test, not a safety net.** That is the whole trap: the natural precaution is taken, it passes, and
the outcome is still destructive.

## Fix

1. **Do not generate patches with `git diff --no-index`.** Edit the target file directly, after
   asserting that the anchor text exists and is unique. It is simpler, and it cannot silently
   become a rename.
2. If you must use a patch, read its `+++ b/` lines before applying. Every one should be a
   repo-relative path.
3. Whatever the route, run `git status` **after** applying and read it. The post-state is the
   confirmation; `--check` passing is not.

## Recovery

Nothing is lost when the files were tracked and committed:

```bash
git checkout -- README.md CLAUDE.md   # restore from HEAD
git clean -fd -- var                  # scoped: only the stray tree
git diff --quiet HEAD -- README.md CLAUDE.md && echo restored
```

Scope the `clean` to the stray folder. A bare `git clean -fd` also removes untracked work that
belongs to somebody else, which in a checkout shared by several sessions is the more expensive
mistake of the two.
