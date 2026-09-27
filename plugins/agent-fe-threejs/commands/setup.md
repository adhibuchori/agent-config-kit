---
description: Install agent-fe-threejs's 3D scene rules, asset-budget check and skills-by-reference guide into this Next.js repo, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*), Bash(node scripts/check/3d-budget.mjs:*)
---

# /agent-fe-threejs:setup — Set Up agent-fe-threejs In This Repo

A plugin cannot carry a repo's rules or check scripts, so this command installs them as files:

- `.claude/rules/web/3d.md`: gate the scene, keep a still fallback, honour reduced motion, dispose
  GPU resources, keep to the asset budgets. It loads only when a scene or asset file is touched.
- `scripts/check/3d-budget.mjs` and its config `scripts/check/3d-budget.json` (the config is created
  once and is the repo's from then on).
- `docs/3d-skills.md`: how to add third-party 3D skills by reference, with `skills-lock.json` and
  `skillOverrides`. The kit vendors no skill.
- An `allow` rule so Claude runs the budget check without asking (it reads local files only).

Nothing is written until the user has seen the whole draft and replied **go**. Existing files are
never overwritten: the only edits to files that already exist are the managed merges the draft lists
(`.claude/settings.json`, one block each in `.gitignore` and `CLAUDE.md`).

**Arguments:** $ARGUMENTS. Each `--answer id=value` there answers one of agent-core's questions in
advance (this plugin asks none of its own); ask only the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-fe-threejs:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- `package.json`: does it depend on `three`, `@react-three/fiber` or `@react-three/drei`? If none,
  say so and ask whether to go on: this add-on is for a site that ships a 3D scene.
- `.claude/agent-config-kit.lock`: if it already lists `agent-fe-threejs`, stop and point the user at
  `/agent-fe-threejs:sync`. If it lists neither `agent-fe-nextjs` nor `agent-fe-nextjs-static`,
  suggest setting up the stack plugin first (`/agent-fe-nextjs:setup` or
  `/agent-fe-nextjs-static:setup`): this add-on's rules assume a Next.js site, and the gate list it
  adds a line to comes from there. It is a suggestion; setup works without it.
- Where the 3D code and assets live. Grep for imports of `three` and `@react-three/`, and Glob for
  `**/*.{glb,gltf,ktx2,hdr,exr}` outside `node_modules`. Compare with the rule's `paths` (scene files,
  `3d/`, `three/`, `webgl/`, `shaders/`, `*Scene*.tsx`, `*Canvas*.tsx`, models) and with the budget
  config's `roots` (`public`) and `textureDirs` (`public/models`, `public/textures`, `public/3d`).
  Anything outside them is handed over in step 5.
- `skills-lock.json` and `.claude/skills/`: skills already installed are listed in step 5 for
  `skillOverrides`.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs a
  `.claude/hooks/*.sh` script the kit's plugins also run is double wiring; setup never edits `hooks`,
  so the user removes those entries.
- `scripts/check/gates.list`, `CLAUDE.md`, `.gitignore`.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup lands
  as a change of its own.

## 2. Ask, one question at a time

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-threejs --json
```

This plugin asks nothing of its own; the list holds agent-core's questions when this repo has no
agent-core setup yet, and is empty otherwise. For each question the arguments did not answer: ask it
on its own with its choices, give the **recommended** answer and one line of why (adjusted by what
step 1 found, citing the file), accept "ok" as the recommended answer, and wait for the reply before
the next question.

## 3. Draft

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-threejs --project "$PWD" --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, by-hand, warn and
lock line, and the digest. Two `by-hand` lines are expected, because the engine writes neither file:

- `scripts/check/gates.list`: the line that runs the budget check with the other gates.
- `.claude/settings.json`: the `skillOverrides` example from `docs/3d-skills.md`, for when 3D skills
  are installed.

End with: "Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, and only then, run `apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-threejs --project "$PWD" --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-threejs --project "$PWD"
node scripts/check/3d-budget.mjs
```

Report both exit codes. The budget check prints how many models, textures and environment maps it
read; zero with assets in the repo means `roots` or `textureDirs` miss them. Exit 2 with "root ...
is not a folder" means the site serves its assets from somewhere else: fix `roots`.

Then tell the user, briefly:

- Commit the new files together with `.claude/agent-config-kit.lock`: the lock records what setup
  installed, and it is what turns the kit's hooks on for everyone who clones the repo.
- Add the budget check's line to `scripts/check/gates.list` (the `by-hand` line), so it runs with the
  other gates in the pre-commit hook and in CI.
- If 3D code lives outside the rule's `paths`, add its folders to the frontmatter of
  `.claude/rules/web/3d.md`, then run
  `agent-sync own --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack fe-threejs --project "$PWD" .claude/rules/web/3d.md`
  so sync keeps the edited copy instead of reporting it as drift.
- `scripts/check/3d-budget.json` is theirs: set `roots` and `textureDirs` to where the assets live,
  and tune the budgets after measuring on a mid-range phone. One file that needs more gets an
  `exceptions` entry with its reason.
- Third-party 3D skills: `docs/3d-skills.md`. Nothing is installed by this setup.
