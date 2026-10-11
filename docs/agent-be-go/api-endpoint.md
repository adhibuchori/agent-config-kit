# api-endpoint

Skill · agent-be-go · `agent-be-go:api-endpoint` · edits the spec, handlers, services and tests · no network

## What it does

The `api-endpoint` skill adds or changes one HTTP endpoint contract first, as a tracer bullet: it
agrees on the test seam with you, writes the operation in `api/openapi.yaml`, regenerates the
server, writes one failing test through the router, then the handler and service code that turns
it green, one behaviour at a time, and ends on the gates.

## When to reach for it

Claude loads it when a task adds, removes or changes a route, its request or response, or the error
codes it returns:

```text
Add GET /api/invoices/{id}, returning 404 INVOICE_NOT_FOUND for an unknown id.
```

**Not for:** a change inside a service that leaves every route's contract as it is, or a schema
change; the [db-migration](db-migration.md) skill covers that.

## Prerequisites

- The files [/agent-be-go:setup](setup.md) installs: the spec, the generated server, the router
  tests, and `scripts/check/generated.sh`.

## Common questions

**Why does the build fail after the spec changes?**
On purpose: the generated interface gains a method, and the build stays red until `Handlers` has
it. That is the step's done line.

**Where do the expected values come from?**
From the spec: the status, the code and the field it names, written as literals in the test.

## It's working if

- The diff has the operation in `api/openapi.yaml`, the regenerated files, a handler of 15 lines or
  fewer, and one test per response the spec lists.
- `bash scripts/check/gates.sh` passes.

## Where it fits

One of the two procedure skills of [agent-be-go](../../plugins/agent-be-go/README.md); the
[reviewer](reviewer.md) checks the result against the rules.
