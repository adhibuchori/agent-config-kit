# plan-fullstack

Command · agent-fe-nextjs · `/agent-fe-nextjs:plan-fullstack [feature]` · reads only · no network

## What it does

`/agent-fe-nextjs:plan-fullstack` plans a feature that spans the frontend and its API. It checks the
backend's endpoints, the OpenAPI contract, the generated client and existing components first, then
lists scope, ordered tasks, risks and open questions. It writes nothing.

## When to reach for it

Before a feature that needs a new endpoint or a contract change:

```text
/agent-fe-nextjs:plan-fullstack team invitations
```

**Not for:** a change inside the frontend alone; use [/agent-core:plan](../agent-core/plan.md)
instead.

## Prerequisites

- A local checkout of the backend repo, and of its content service if it has one. `SSOT.md` §2
  names the path; otherwise it asks for it.

## Common questions

**Why does the frontend never call the database directly?**
All data flows through the backend; the frontend only knows the backend's endpoints.

## It's working if

- You get a plan that names the endpoint, the contract change, the regeneration step and the UI tasks, in order.

## Where it fits

The stack planner behind [/agent-core:plan](../agent-core/plan.md).
