# post-edit

Hook · agent-core · PostToolUse on the write tools · feedback only, never blocks · timeout 60 s · no network · fails open

## What it does

post-edit formats, then lints, the file Claude just wrote, with your project's own tools, and hands
Claude any finding.

`*.py` gets `ruff format` then `ruff check`; TypeScript and JavaScript get `oxfmt` then `oxlint`;
JSON, CSS and Markdown get `oxfmt`, and JSON is also checked for validity. A tool your project does
not have is skipped: nothing is downloaded.

| File | Format | Lint |
| --- | --- | --- |
| `*.go` | `golangci-lint fmt`, or `gofmt -w` without golangci-lint | `golangci-lint run` on the file's package (capped at 20 s), or `go vet` |
| `*.rs` | `rustfmt --edition 2024` through stdin, written back only when it differs | `cargo clippy --locked --all-targets` from a root `Cargo.toml` (capped at 10 s), this file's lines only |
| `*.swift` | `xcrun swift-format format --in-place`, or a `swift-format` on `PATH` | `swiftlint lint --quiet --force-exclude`, this file's lines only |
| `*.xcstrings` | none | valid JSON; every key in every locale the catalog itself uses, each `translated` |
| `*.pbxproj` | none | `plutil -lint` |

Go runs with `GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=readonly`, Rust with
`RUSTUP_AUTO_INSTALL=0 CARGO_NET_OFFLINE=true SQLX_OFFLINE=true`: the toolchain already installed,
no network, and `go.mod` never rewritten. A package-wide note stops after 40 lines.

## When to reach for it

It runs by itself after `Write`, `Edit`, `MultiEdit` and Serena's write tools. With `localePairs`
set in `.claude/agent-config.json`, it also tells Claude when one translation catalogue changed and
its partner did not.

**Not for:** keeping unformatted code out of a commit, since it never blocks; the pre-commit gate
(`bash scripts/check/gates.sh`) does that instead.

## Prerequisites

- Your project's own formatters and linters, installed as dev dependencies: `oxfmt` and `oxlint`
  for TypeScript and JavaScript (`oxfmt` also formats JSON, CSS and Markdown), `ruff` for Python.
  For Go, Rust and Swift, the tools on your `PATH`: golangci-lint (or Go's own `gofmt` and
  `go vet`), the toolchain's `rustfmt` and `cargo clippy`, Xcode's `swift-format` and SwiftLint.
  A tool the project lacks is skipped.

## What it blocks

Nothing: it only adds context. It always exits 0, so it can never stop a tool call or erase a prompt.

### How to disable

This hook never blocks, so there is nothing to turn off for a single command. To silence it with
the rest of agent-core:

- **This repo, for you only:** disable the plugins at local scope. A stack plugin depends on
  agent-core, so disable it first:

  ```bash
  claude plugin disable agent-fe-nextjs@agent-config-kit --scope local   # your stack plugin
  claude plugin disable agent-core@agent-config-kit --scope local
  ```

- **Everywhere:** the same two commands without `--scope local`.
- **This repo, for everyone:** the same commands with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
d=$(mktemp -d) && printf '{"a": }\n' >"$d/broken.json" \
  && printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$d/broken.json\"}}" \
  | CLAUDE_PROJECT_DIR="$d" bash plugins/agent-core/scripts/post-edit.sh; echo "exit=$?"
# expect: exit=0, and on stdout:
# {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"broken.json is not valid JSON."}}
```

## Common questions

**Where does it find the formatters?**
`node_modules/.bin`, then `.venv/bin`, then your `PATH`. Install them as dev dependencies of the project.

**It is slow on big files.**
Its timeout is 60 s; formatting runs once per write. A repo without oxfmt, oxlint or ruff pays only the hook's start-up time (about 70 ms measured).

**Clippy said nothing after a dependency change.**
A cold build takes longer than the 10 s cap, and a build lock another `cargo` holds makes clippy
wait: either way the hook stops it and says nothing. The next edit, or the gate, reports.

**Why does SwiftLint say nothing at all?**
A SwiftLint other than the version `.swiftlint.yml` pins (`swiftlint_version`) exits without
linting. Install the pinned version.

## It's working if

- `git diff` shows a file Claude wrote already in your formatter's style, with no separate format
  step.
- When a write leaves a lint error, Claude fixes it in its next edit without being asked.

## Where it fits

Feedback hook of [agent-core](../../plugins/agent-core/README.md). The same formatters run again
in the pre-commit gate (`bash scripts/check/gates.sh`) and in CI, so a skipped note is caught later.
