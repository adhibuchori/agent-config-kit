# Choosing the React Doctor CLI

The exact paths and commands behind `SKILL.md` § Where the CLI comes from, and the repo files the
skill names. The rules stay in `SKILL.md`: the project's own copy first, the pinned download only
after the user's yes, never `@latest`.

## The project's own copy

It is `node_modules/.bin/react-doctor`. When it exists, nothing is downloaded. Print its version
once, and say so when it is not 0.9.14:

```bash
node_modules/.bin/react-doctor --version
```

## The pinned download

`bunx react-doctor@0.9.14` fetches that exact version from the npm registry the first time and
caches it; it runs only after the user's yes. On a no, stop and suggest this instead, which puts the
CLI in the project:

```bash
bun add -d react-doctor@0.9.14
```

## The line every shell call starts with

Each shell call starts fresh, so every command in `SKILL.md` starts with this line, which chooses
the CLI (the other references carry their own copy):

```bash
RD=(bunx react-doctor@0.9.14); [ -x node_modules/.bin/react-doctor ] && RD=(node_modules/.bin/react-doctor)
```

## Repo files the skill names

| In `SKILL.md`                  | Path in the repo                        |
| ------------------------------ | --------------------------------------- |
| the audit gate                 | `scripts/check/audit.ts`                |
| the repo's React Doctor config | `doctor.config.json`                    |
| the repo's dead-code rule      | `.claude/rules/typescript/dead-code.md` |

## Raising the pin

An upgrade changes 0.9.14 together in `SKILL.md`, in every file in this folder, and in
agent-fe-nextjs's `templates/fe-nextjs/.github/workflows/react-doctor.yml`, after reading the
release notes.
