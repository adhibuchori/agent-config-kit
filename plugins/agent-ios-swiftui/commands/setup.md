---
description: Install agent-ios-swiftui's iOS rules, anti-patterns, gate scripts, SwiftLint, swift-format and xcconfig settings, the seeded problem type and its tests, a pre-commit hook and pull-request CI into this SwiftUI app, after a dry run you approve
argument-hint: "[--answer id=value ...]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git branch --list:*), Bash(git remote -v), Bash(plutil -convert json -o -:*), Bash(xcodebuild -version), Bash(swift --version), Bash(swiftlint version), Bash(command -v agent-setup), Bash(agent-setup questions:*), Bash(agent-setup plan:*), Bash(agent-sync check:*)
---

# Set up agent-ios-swiftui in this repo

A plugin cannot carry permissions, rules or a repo's own scripts, so this command installs them as
files. Nothing is written until the user has seen the whole draft and replied **go**. Existing files
are never overwritten: the only edits to files that already exist are the managed merges the draft
lists (`.claude/settings.json`, and one block each in `.gitignore` and `CLAUDE.md`). Setup never
creates or edits the Xcode project, never builds, and never touches signing.

Arguments: `$ARGUMENTS`. Each `--answer id=value` there answers that question in advance; ask only
the rest.

Every step runs in this order, and none is skipped. The engine is agent-core's `agent-setup`; the
templates path below is written out in full because the Bash tool does not export
`CLAUDE_PLUGIN_ROOT`.

## 0. Check the engine

Run `command -v agent-setup`. If it prints nothing, stop and tell the user: `agent-setup` ships in
agent-core, which this plugin depends on; install or enable it
(`/plugin install agent-core@agent-config-kit`), then run `/agent-ios-swiftui:setup` again. It needs
python3 3.8 or newer.

## 1. Explore (read-only)

Read what setup would touch, and note what you find, with the file as evidence:

- The `.xcodeproj` at the repo root. Read its project file as JSON with
  `plutil -convert json -o - <App>.xcodeproj/project.pbxproj`, and note its targets, whether
  its folders are buildable folders, whether the project's configurations already name a base
  xcconfig, which `SWIFT_*` keys it sets (they move to `Config/Base.xcconfig`), its
  `IPHONEOS_DEPLOYMENT_TARGET` and its `knownRegions`. No project yet: say that the user creates
  the app in Xcode first, and that setup can still run.
- `Packages/`, `Config/*.xcconfig`, `.swiftlint.yml`, `.swift-format`, the String Catalogs
  (`*.xcstrings`) and any copy of the backend's `openapi.json`. Note which exist: the draft keeps
  each one and reports it as `keep`.
- `xcodebuild -version`, `swift --version` and `swiftlint version`, only to report what is
  installed: the gates expect Xcode 27 and SwiftLint 0.65.1. Setup installs no tool.
- `.claude/settings.json` and `.claude/settings.local.json`: a `hooks` key that runs
  `generated-guard.sh`, or any `.claude/hooks/*.sh` from a copied template. With the plugins
  enabled, each of those runs twice (double wiring); setup never edits `hooks`, so the user removes
  those entries.
- `CLAUDE.md` and `AGENTS.md`. Each is created from the plugin's starter only where it is absent.
  If `AGENTS.md` already exists, say so: the `agent-ios-swiftui:reviewer` subagent cites the
  starter's rule numbers and falls back to whatever the existing file defines.
- `.gitignore`, `.claude/agent-config.json` (does it set `generatedPaths`?), `.github/workflows/`,
  `.github/PULL_REQUEST_TEMPLATE/`, and `git remote -v`. Run `git branch --list dev prod` to see
  whether the dev → prod flow exists.
- `.claude/agent-config-kit.lock`: if it already lists `agent-ios-swiftui`, stop and point the user
  at `/agent-ios-swiftui:sync`.
- `git status --short`. If the tree is dirty, say so, and suggest committing first so the setup
  lands as a change of its own.

If the repo is not a SwiftUI app with an Xcode project (a UIKit app, a library, another platform),
say what you found and ask whether to go on.

## 2. Ask, one question at a time

Run:

```bash
agent-setup questions --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ios-swiftui --json
```

The list starts with agent-core's questions when this repo has no agent-core setup yet; that layer
is planned in the same draft. For each question the arguments did not answer:

- ask it on its own, with its choices;
- give the **recommended** answer and one line of why, adjusted by what step 1 found: cite the file
  (for example, the project's deployment target is 18.0, so `min-ios` is probably `18.0`);
- accept "ok" as the recommended answer, and wait for the reply before the next question.

## 3. Draft

Run `agent-setup plan` with every answer:

```bash
agent-setup plan --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ios-swiftui --answer <id>=<value> ...
```

Show its output verbatim: every create, same, keep, seed, merge, conflict, block, warn and lock
line, and the digest. Below it, add at most three lines on what matters here (a `keep` of a file
the user may want to compare, a `conflict`, a `warn` about double wiring or a held CI caller). End
with: "Reply **go** to write exactly this."

## 4. Write only on "go"

On **go**, run `agent-setup apply` with the same answers and the digest from step 3:

```bash
agent-setup apply --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ios-swiftui --answer <id>=<value> ... --digest sha256:<hex>
```

`apply` is left out of this command's allowed tools on purpose, so the user's permission prompt is a
second, independent confirmation. Any reply other than **go** writes nothing. If `apply` exits 3, the
repo changed since the draft: go back to step 3 and show the new plan.

## 5. Verify and hand over

Run:

```bash
agent-sync check --templates "${CLAUDE_PLUGIN_ROOT}/templates" --stack ios-swiftui
```

Report its exit code and findings (0 means in sync). Then prove the generated guard on this repo:

```bash
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"Packages/AppCore/Sources/APIClient/openapi.json"}}' \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/generated-guard.sh"; echo "exit=$?"
```

Expect `exit=2` and a `[generated-guard] BLOCKED` line naming the API contract; nothing is written,
the hook only reads the payload.

Then hand the user the steps only they can take, briefly and in this order:

1. In Xcode, set the project's Debug and Release configurations to `Config/Debug.xcconfig` and
   `Config/Release.xcconfig` (the project, Info tab, Configurations), and delete the `SWIFT_*`
   settings the project file holds: `Config/Base.xcconfig` sets them now.
2. Add `Packages/AppCore` to the project as a local package and link its `APIClient` product to the
   app target. Then resolve once (open the project in Xcode, or run
   `xcodebuild -resolvePackageDependencies`) and in the package folder (`swift package resolve`),
   and commit both `Package.resolved` files: CI builds only from them.
3. Turn the pre-commit gate on in each clone: `git config core.hooksPath .githooks`.
4. When `min-ios` was not `17.0`: set `IPHONEOS_DEPLOYMENT_TARGET` in `Config/Base.xcconfig` and
   `.iOS(...)` in `Packages/AppCore/Package.swift` to the answer.
5. The gates call tools the Mac must have: Xcode 27.0, SwiftLint 0.65.1 (the version
   `.swiftlint.yml` pins; another one exits 2) and Node 20 or newer. A person installs the pinned
   SwiftLint; setup installs nothing. Anthropic's `swift-lsp` plugin gives compile diagnostics
   after each edit.
6. Placeholders left to fill: the project name and the one-sentence purpose in `CLAUDE.md`, the
   Compliance Status table of `AGENTS.md` (fill it before relying on any rule), the project and
   scheme in `.periphery.yml`, `@your-github-handle` in `.github/CODEOWNERS`, and
   `AppProblem.typeBase` in
   `Packages/AppCore/Sources/APIClient/AppProblem.swift`, which must equal the backend's
   problem-type base before the first release.
7. Commit the new files together with `.claude/agent-config-kit.lock`: the lock is what turns the
   hooks on for everyone who clones the repo. Then run `bash scripts/check/gates.sh`.

The pull-request gate (`.github/workflows/quality-gate.yml`, when installed) runs on every pull
request once the repo is on GitHub; make its "Quality Gate (ios-swiftui)" check required.
