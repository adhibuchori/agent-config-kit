---
name: api-endpoint
description: Adds or changes an HTTP endpoint of this Go service contract first, as one tracer bullet - spec, generated interface, a failing test at the handler seam, then the code that turns it green. Use when the task adds, removes or changes a route, its request or response shape, or the error codes it can return. Not for a change inside a service that leaves every route's contract as it is, and not for a schema change, which the db-migration skill covers.
---

# API endpoint, contract first

One endpoint at a time, end to end. Each step ends on its done line; the next starts only then.
The repo's paths and commands for each step are in [references/steps.md](references/steps.md).

1. **Seam.** Name the operation, the behaviours its first test will prove, and where the test
   enters (the router, with a real request). Agree on them with the user before any code.
   Done when the user has confirmed the seam and the first behaviour.
2. **Contract.** Write the operation in the OpenAPI document: path, method, request, the success
   response, and every error code the service can return for it, with the error statuses the
   router can answer.
   Done when the spec's own tests pass and the diff shows only the spec.
3. **Generate.** Regenerate the server interface and the exported contract.
   Done when the build fails only because the new operation has no handler yet.
4. **Red.** Write one test through the router for the first behaviour, with its expected values
   taken from the spec, never recomputed.
   Done when that test fails for the reason the missing behaviour predicts.
5. **Green.** Write the handler (15 lines at most) and the service code that makes the test pass.
   Errors leave as registered codes.
   Done when the test passes and nothing else changed.
6. **Next behaviour.** Repeat steps 4 and 5 for each further behaviour the spec states, one test at
   a time.
   Done when every response the spec lists, errors included, has its test.
7. **Gates.** Run the gates.
   Done when they pass, coverage included.
