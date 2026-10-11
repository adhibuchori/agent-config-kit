# api-endpoint

Skill · agent-be-axum · `agent-be-axum:api-endpoint` · edits handlers, services and tests, regenerates the spec · no network

## What it does

The `api-endpoint` skill adds or changes one HTTP endpoint code first, as a tracer bullet: agree the
request, the response and the error codes, register the path and the annotated handler, write one
failing request test, make it pass, repeat per behaviour, then regenerate `openapi.json` and run
the gates. Every step ends on a "Done when" line, so the work never stops half way.

## When to reach for it

Claude loads it when a task adds, removes or changes a route, its request or response shape, or the
error codes it can return:

```text
Add GET /api/orders/{id}, answering 404 ORDER_NOT_FOUND when there is none.
```

**Not for:** a schema change on its own; use [db-migration](db-migration.md) instead.

## Prerequisites

- The skeleton and rules [/agent-be-axum:setup](setup.md) installs: the route registry, the error
  module, the request-test tier and the spec drift test.

## Common questions

**Why does it stop before the first test?**
The test seam (the request, the expected response, the codes) is agreed with you first, so the
test pins what you asked for rather than what the code happens to do.

**The build fails with "this lint expectation is unfulfilled".**
The first route that reads a JSON body makes the extractor live: delete the `expect(dead_code)`
attribute on `mod extract;`, as the skill's steps say.

## It's working if

- The new path is a constant in the route registry, the handler is at most 15 lines, and every
  status it returns is declared with a description.
- `openapi.json` changed in the same commit, and `bash scripts/check/gates.sh` passes.

## Where it fits

One of the two skills of [agent-be-axum](../../plugins/agent-be-axum/README.md), next to
[db-migration](db-migration.md).
