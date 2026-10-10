# setup

Command · agent-be-go · `/agent-be-go:setup [--answer id=value …]` · only you start it · writes only after you reply go · no network

## What it does

`/agent-be-go:setup` installs what a plugin cannot ship by itself into your Go service: the rule
index (`AGENTS.md`) and a short `CLAUDE.md`, the Go, PostgreSQL, testing, error-code and coverage
rules, the anti-patterns, a service skeleton with its tests at 100% (the closed error-code registry
and RFC 9457 writer, the router with spec validation and the 404/405 fallback, the pool, the
configuration and logging packages, `cmd/api`), `api/openapi.yaml` and its export, the database
roles, `.golangci.yml`, `sqlc.yaml`, the gate scripts with `gates.list`, the pre-commit hook, a
pull-request-only CI caller, an optional DeepSeek review, PR templates, a CODEOWNERS starter and,
when you ask for it, the payload contract that seals request and response bodies.

It explores your repo, asks one question at a time with a recommended answer, shows the exact draft,
and writes only when you reply **go**. It never overwrites or deletes a file, and never edits
`go.mod`: a repo without one gets the starter, and a repo with one gets a `by-hand` line naming the
lines to merge. The lock `.claude/agent-config-kit.lock` is written last: it turns the kit's hooks on
in this repo.

If agent-core is not set up in this repo yet, the same draft includes agent-core's layer first (its
questions come first). One setup, one lock.

It refuses (exit 3) a repo already set up with `agent-ai-fastapi`, `agent-be-axum`, `agent-be-hono`,
`agent-docs-nextra`, `agent-fe-nextjs`, `agent-fe-nextjs-static` or `agent-ios-swiftui`: one primary
stack per repo.

## When to reach for it

Once per repo, after you install the plugin:

```text
/agent-be-go:setup
/agent-be-go:setup --answer migrations=yes --answer ci-gate=yes
```

The questions (answer "ok" to take the recommended one):

| Question id | What it asks | Choices | Recommended |
| --- | --- | --- | --- |
| `migrations` | Does this service own its database schema, with goose migrations in db/migrations? | yes / no | `yes` |
| `ci-gate` | Run agent-config-kit's Go quality gate on every pull request (.github/workflows/quality-gate.yml)? | yes / no | `yes` |
| `deepseek-review` | Review each pull request with DeepSeek, a low-cost paid AI model (.github/workflows/deepseek-review.yml)? | yes / no | `no` |
| `pr-templates` | Add pull-request templates for work pull requests and dev → prod promotions (.github/PULL_REQUEST_TEMPLATE/)? | yes / no | `yes` |
| `analytics` | Does an agent need to read a self-hosted analytics API from this repo? | yes / no | `no` |
| `serena-workspace` | Do you open several repositories as one Serena workspace? | yes / no | `no` |
| `payload-encryption` | Seal request and response bodies between this service and its callers (the payload contract: encrypted envelopes, a registry generated from the spec, checked before merge)? | yes / no | `no` |

The draft lists every action: `create`, `same`, `keep`, `seed`, `merge`, `conflict`, `block`,
`alias`, `by-hand`, `warn` and `lock`, then a `digest`. `apply` is not pre-approved, so your
permission prompt is a second confirmation.

## Prerequisites

- python3 3.8 or newer for the engine. The gates it installs need Go 1.27, golangci-lint v2.14.0,
  gitleaks, Node 20 or newer and a PostgreSQL 18 for the tests; setup installs none of them.

## Common questions

**Will it overwrite my files?**
No. A file that exists is listed as `keep` and left alone, `go.mod` included. Only three existing
files are edited, each shown in the draft: an additive merge of `.claude/settings.json` (never its
`hooks`), and one managed block each in `.gitignore` and `CLAUDE.md`.

**The seeded code does not compile in my repo.**
It imports `example.com/service`. Replace that with your module path in `go.mod`, `.golangci.yml`
and the seeded `.go` files; setup's last step says so.

**What must I set before the first release?**
The problem-type base: `apperr.TypeBase` and `x-problem-type-base` in `api/openapi.yaml`, one https
URI under a domain you own. Production refuses to start while it is the placeholder.

**I answered `payload-encryption=yes`, and the gates are red.**
On purpose: a half-adopted contract never passes. Setup installs the Go code (`internal/payload`,
the middleware in `internal/httpapi`, the five `ENVELOPE_*` codes, the payload variables in
`internal/config`), `payload.config.json`, the shared vectors, the registry generator and check, and
the key script. Four steps stay yours, and `.claude/rules/backend/go-payload.md` shows each one:

1. Add the five codes to `Registered()` in `internal/apperr/codes.go` and to `Problem.code` in
   `api/openapi.yaml`.
2. When browsers or apps call the service, add `GET /api/payload/handshake`, and exempt it and the
   health probe as `none` in `payload.config.json`; otherwise drop `handshake` there. The check
   compares `handshake` with the operation ID as `api/openapi.json` spells it, and oapi-codegen's
   export capitalizes it (`GetPayloadHandshake`).
3. Wire `sealBodies` into `NewRouter` between the validator and the body limit, and build the edge
   in `main` from `config.LoadPayload`.
4. Regenerate: `bash scripts/check/generated.sh --write`, then
   `node scripts/generate/payload-registry.mjs`.

Keys never go through a chat: `node scripts/generate/payload-server-key.mjs` prints a new key pair
for `PAYLOAD_SERVER_JWK`, which you pipe into the env file yourself (`docs/unlock.md`); the
settings this setup merges refuse it to an agent.

**It says `command -v agent-setup` found nothing.**
agent-core is not enabled in this session, or you are on claude.ai or Cowork, which do not install
plugins with a `bin/` folder. Enable agent-core with `/plugin` and restart.

**Apply exited 3.**
The repo changed since the draft (the digest no longer matches). Run setup again to see a new draft.

## It's working if

- The draft ends with a `digest sha256:…` line, and after **go** the last line apply prints is
  `wrote    .claude/agent-config-kit.lock`.
- `/agent-be-go:sync --check` then ends with `result: in sync (0 findings; exit 0)`.
- A caller that still holds the all-zero release placeholder is not installed: the draft shows
  `warn     .github/workflows/quality-gate.yml  not installed: …`, and the next release installs it
  through sync.
- After the by-hand steps, `bash scripts/check/gates.sh` passes on the seeded skeleton.

## Where it fits

The first command you run from [agent-be-go](../../plugins/agent-be-go/README.md). Afterwards,
[/agent-be-go:sync](sync.md) keeps the repo in line with the plugin.
