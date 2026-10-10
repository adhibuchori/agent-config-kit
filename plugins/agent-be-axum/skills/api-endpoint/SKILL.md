---
name: api-endpoint
description: Adds or changes an HTTP endpoint of this Rust + Axum service code first, as one tracer bullet - path constant, annotated handler, a failing request test, then the code that turns it green and the regenerated spec. Use when the task adds, removes or changes a route, its request or response shape, or the error codes it can return. Not for a schema change alone (db-migration) or a change inside one service function that no route sees.
---

# API endpoint, code first

One endpoint at a time, end to end. Each step ends on its done line; the next starts only then.
The repo's paths and commands for each step are in [references/steps.md](references/steps.md).

1. **Agree the seam.** Name the request the test will send, the response it expects, and every
   error code the endpoint can return, taken from the task's spec. Wait for the user to agree.
   Done when the user has confirmed the request, the response and the codes.
2. **Register the path.** Add the path constant to the route registry and the handler's signature
   with its annotation: method, path, request body, the success response and every error status,
   each with a description. Add the handler to its domain's routes.
   Done when the crate compiles and the new operation appears in the generated document.
3. **Red.** Write one request test through the real router for the behaviour the seam states,
   with expected values copied from the spec, never recomputed.
   Done when that test fails for the reason the missing behaviour predicts.
4. **Green.** Write the handler (15 lines at most) and the service and repo code that make the
   test pass. Errors leave as registered codes; a new code is added to the registry with its title.
   Done when the test passes and nothing else changed.
5. **Next behaviour.** Repeat steps 3 and 4 for each further response the seam named, one test at a
   time, errors included.
   Done when every response the operation declares has its test.
6. **Contract and gates.** Regenerate the exported spec, then run the gates.
   Done when the spec drift test and every gate pass, coverage included.
