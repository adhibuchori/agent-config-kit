# setup

Command · agent-ios-swiftui · `/agent-ios-swiftui:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-ios-swiftui:setup` installs what a plugin cannot ship by itself into your SwiftUI app: a 28-rule `AGENTS.md` index and a short `CLAUDE.md`, rules for the app target, the logic package, strings, tests, error codes and coverage, 12 anti-patterns, `Config/{Base,Debug,Release}.xcconfig`, a strict `.swiftlint.yml` with the kit's custom rules, `.swift-format`, `.periphery.yml`, a `Packages/AppCore` starter with `AppProblem` (the RFC 9457 problem type the generated client decodes into) and its tests, the generator's settings, a privacy manifest, the check scripts with `gates.list`, `scripts/ios/app.sh` and `scripts/ios/api-client.sh`, `scripts/check/ci-env.sh` with a seeded `.env.ci.example`, `.githooks/pre-commit`, a pull-request-only CI caller, an optional DeepSeek review of each pull request, PR templates and a CODEOWNERS starter.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file, never creates or edits
the Xcode project, never builds and never signs. The lock `.claude/agent-config-kit.lock` is written
last: it turns the kit's hooks on in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its four questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-ai-fastapi`, `agent-be-axum`, `agent-be-go`, `agent-be-hono`, `agent-docs-nextra`, `agent-fe-nextjs` or `agent-fe-nextjs-static`: one primary stack per repo.

## When to reach for it

Once per repo, after you install the plugin and create the app in Xcode:

```text
/agent-ios-swiftui:setup
/agent-ios-swiftui:setup --answer locales=en,id --answer min-ios=18.0
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `ci-gate` | Run agent-config-kit's iOS quality gate on every pull request (.github/workflows/quality-gate.yml)? | yes / no | `yes` |
| `deepseek-review` | Review each pull request with DeepSeek, a low-cost paid AI model (.github/workflows/deepseek-review.yml)? | yes / no | `no` |
| `pr-templates` | Add pull-request templates for work pull requests and dev → prod promotions (.github/PULL_REQUEST_TEMPLATE/)? | yes / no | `yes` |
| `serena-workspace` | Do you open several repositories as one Serena workspace? | yes / no | `no` |
| `min-ios` | Which iOS version is the oldest the app supports? | 17.0 / 18.0 / 26.0 | `17.0` |
| `locales` | Which languages does the app ship (en, or en and id)? | en / en,id | `en` |
| `analytics` | Does an agent need to read a self-hosted analytics API from this repo? | yes / no | `no` |

`min-ios` writes no file: the seeds say 17.0, and for another answer the hand-over asks you to set
it in two places. `locales=en,id` installs `scripts/check/i18n-catalog.json`.

The draft lists every action: `create`, `same`, `keep`, `seed`, `merge`, `conflict`, `block`,
`note`, `warn` and `lock`, then a `digest`. `apply` is not pre-approved, so your permission prompt
is a second confirmation.

After **go**, the hand-over lists what only you do: base the project's configurations on
`Config/Debug.xcconfig` and `Config/Release.xcconfig`, link the `Packages/AppCore` products, commit
both `Package.resolved` files, `git config core.hooksPath .githooks`, install SwiftLint 0.65.1, and
fill the placeholders (`CLAUDE.md`, the Compliance Status of `AGENTS.md`, `.periphery.yml`,
`AppProblem.typeBase`, CODEOWNERS).

## Common questions

**Will it overwrite my files?**
No. A file that exists is listed as `keep` and left alone. Only three existing files are edited, each shown in the draft: an additive merge of `.claude/settings.json` (never its `hooks`), and one managed block each in `.gitignore` and `CLAUDE.md`.

**Why does it not create the Xcode project?**
The project file belongs to Xcode and to you. Setup installs the settings it should use (`Config/*.xcconfig`) and `scripts/check/xcode-settings.sh` checks that the project names them.

**It says `command -v agent-setup` found nothing.**
agent-core is not enabled in this session, or you are on claude.ai or Cowork, which do not install plugins with a `bin/` folder. Enable agent-core with `/plugin` and restart.

**Apply exited 3.**
The repo changed since the draft (the digest no longer matches). Run setup again to see a new draft.

## It's working if

- The draft ends with a `digest sha256:…` line, and after **go** the last line apply prints is
  `wrote    .claude/agent-config-kit.lock`.
- `/agent-ios-swiftui:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- After the hand-over steps, `bash scripts/check/gates.sh` passes on the seeded skeleton.
- A CI caller that still holds the all-zero release placeholder is not installed: the draft shows
  `warn     .github/workflows/quality-gate.yml  not installed: …`, and the next release installs it
  through sync.

## Where it fits

The first command you run from [agent-ios-swiftui](../../plugins/agent-ios-swiftui/README.md). Afterwards, [/agent-ios-swiftui:sync](sync.md) keeps the repo in line with the plugin.
