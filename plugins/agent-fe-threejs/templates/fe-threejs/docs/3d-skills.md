# 3D skills, installed by reference

A skill is a folder of instructions, and sometimes scripts, that Claude loads when a task matches
it. Useful third-party skills for three.js and React Three Fiber exist, and this kit copies none of
them: a copy goes stale, loses its license context and hides who maintains it. You install the ones
you want from their source, pin the version, review them like any other dependency, and keep the
record in the repo.

## 1. Choose a skill

- Find candidates in a project's README, or search the installer's index:
  `npx skills@1.7.0 find three`.
- Before installing, read its `SKILL.md` and every script beside it. A skill runs with Claude's
  permissions in this repo.
- Check its license, and that it has a maintainer and a release tag you can pin.

### A vetted pack

The [Three.js Claude Skill Package](https://github.com/OpenAEC-Foundation/Three.js-Claude-Skill-Package)
is 24 skills for three.js r160+, React Three Fiber, Drei, WebGPU, physics and loaders, under
`skills/source/<group>/<skill-name>/`. It is MIT-licensed (Copyright 2026 OpenAEC Foundation) and
pinned below to release `v1.1.1` (commit `6c190f0db95d6e4b77d7843d181c6d3325c09d0e`). GitHub now
serves the repository as `Impertio-Studio/Three.js-Claude-Skill-Package` and redirects the old
name. Take only the skills your scenes need, one at a time:

```bash
DO_NOT_TRACK=1 npx skills@1.7.0 add https://github.com/OpenAEC-Foundation/Three.js-Claude-Skill-Package/tree/v1.1.1/skills/source/threejs-core/threejs-core-renderer --agent claude-code
```

That writes `.claude/skills/threejs-core-renderer/` and a `skills-lock.json` entry with
`"ref": "v1.1.1"`. Its `LICENSE` sits at the repository root, not in the skill folder: keep a copy
beside each skill you commit (`.claude/skills/<skill-name>/LICENSE`), since MIT asks for the notice
to travel with the files.

## 2. Install it into this repo

```bash
DO_NOT_TRACK=1 npx skills@1.7.0 add <owner>/<repo> --skill <skill-name> --agent claude-code
```

- `skills@1.7.0` pins the installer itself. `DO_NOT_TRACK=1` (or `DISABLE_TELEMETRY=1`) turns off
  the installer's usage reporting.
- To pin the skill as well, install it from a release tag:
  `DO_NOT_TRACK=1 npx skills@1.7.0 add https://github.com/<owner>/<repo>/tree/<tag>/skills/<skill-name> --agent claude-code`.
  The installer clones with `git clone --branch <ref>`, so it takes a tag or a branch; a bare commit
  id fails with "Remote branch ... not found". Without a tag, the pin is the content hash below.
- With `--agent claude-code` alone, the installer copies the skill into
  `.claude/skills/<skill-name>/` and records it in `skills-lock.json` at the root of the repo.

`skills-lock.json` holds one entry per skill. `ref` is there when the skill came from a tag:

```json
{
  "version": 1,
  "skills": {
    "<skill-name>": {
      "source": "<owner>/<repo>",
      "ref": "<tag>",
      "sourceType": "github",
      "skillPath": "skills/<skill-name>/SKILL.md",
      "computedHash": "<sha-256 of the installed folder>"
    }
  }
}
```

`computedHash` covers every file in `.claude/skills/<skill-name>/`, so an edit by hand or an upgrade
changes it.

## 3. Review it like a dependency

1. Commit the skill folder and `skills-lock.json` together, in a commit of their own.
2. Run `bash scripts/check/skills.sh` (agent-core's skill scan) and read every finding.
3. Accept the reviewed tree by its hash: add an entry under `vendored:` in
   `.skillspector-baseline.yaml` with `target: .claude/skills/<skill-name>`, the `sha256` the scan
   prints, and a `reason` naming the source, the version and why each finding is acceptable. An
   upgrade changes the hash, and the scan fails until someone reviews it again.

## 4. Keep the listing cheap

Claude sees the name and description of every installed skill in every session, including the ones
that never touch 3D. `skillOverrides` in the settings decides how each skill is listed:

| Value | Effect |
| --- | --- |
| absent, or `"on"` | listed with its description (the default) |
| `"name-only"` | listed by name, without its description |
| `"user-invocable-only"` | hidden from Claude; you still run it as `/<skill-name>` |
| `"off"` | hidden from both |

`/agent-fe-threejs:setup` prints this snippet as a `by-hand` line for `.claude/settings.json`. Add it
once you know the skill names:

```json
{
  "skillOverrides": {
    "<skill-claude-should-reach-for>": "name-only",
    "<skill-you-only-run-yourself>": "user-invocable-only"
  }
}
```

Put it in `.claude/settings.json` to decide for the team, or in `.claude/settings.local.json` for
yourself. The `/skills` menu writes to the local file.

## 5. Update or remove

- Update: `DO_NOT_TRACK=1 npx skills@1.7.0 update <skill-name>`, then read the diff, run the scan
  again and record the new hash (step 3).
- Remove: `npx skills@1.7.0 remove <skill-name>`, then delete its `vendored:` entry and its
  `skillOverrides` entry.

## What this kit does not do

It copies no third-party skill into its plugins or templates, and nothing in it runs the installer.
You run it, and the downloads are the installer's.
