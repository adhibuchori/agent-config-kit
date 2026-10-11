---
paths:
  - 'src/payload/**'
  - 'src/routes/payload*.rs'
  - 'src/lib.rs'
  - 'payload.config.json'
  - 'scripts/check/payload-vectors.json'
---

# Payload contract in Rust (Rules 30 to 34)

Where setup answered `payload-encryption=yes`. The contract and its threat model:
`.claude/PAYLOAD-CONTRACT.md`; the short form every stack shares:
`.claude/rules/common/payload-contract.md`. This file is how the contract looks in this crate.

## Layout (Rules 30, 31)

```text
src/payload/              the core, no HTTP type: envelope, cipher, codec, ecdh, keyring, mode,
                          policy, the boundary, code (PayloadCode), setup (the startup errors)
src/payload/endpoints_generated.rs   the registry: node scripts/generate/payload-registry.mjs
src/routes/payload.rs     the handshake, the ENVELOPE_* codes in the spec, the settings check, seal()
src/routes/payload_layer.rs          the route_layer: open the request, run, seal the answer
```

- Setup installs these files unwired. `src/payload/mod.rs` lists the by-hand steps: the four
  crates, the `PAYLOAD_*` fields in `Config`, the handshake path, the module declarations,
  `routes::payload::seal` in `lib.rs` and `check_payload_settings` in `main.rs`.
- The layer is a `route_layer` that `lib.rs` adds after every route is merged, so it sees
  `MatchedPath` and runs before any extractor: `ValidJson` and the handlers see plaintext. A route
  merged after it would go unsealed.
- Only `src/routes/` and `src/lib.rs` name `crate::payload`. A handler, a service or a repo never
  sees an envelope, a key or a policy.

## Routes and policies (Rule 30)

- Every operation in `openapi.json` is in the registry, `strict` unless `payload.config.json`
  exempts it (`"METHOD /pattern": { "encryption", "reason" }`, the `:param` pattern). The reason is
  a property of the body (a multipart upload, an event stream, a probe), never how sensitive it is.
- After a route or an exemption changes: `cargo run --locked --quiet --bin openapi`, then
  `node scripts/generate/payload-registry.mjs`. Never edit `endpoints_generated.rs` by hand; the
  service refuses to start on an entry whose pattern or reason breaks the registry's rules.
- A sealed answer carries `Vary: x-payload-epk, x-payload-kid`. A browser that calls this API from
  another origin also needs `x-payload-epk` in the CORS allow-list (`platform/middleware.rs`).

## Keys and the switch (Rules 32, 33)

- `PAYLOAD_SERVER_JWK` is the key pair public clients (an app, a browser) agree keys with; make it
  with `node scripts/generate/payload-server-key.mjs | bash scripts/env/set.sh <file> PAYLOAD_SERVER_JWK`.
  `PAYLOAD_KEY` (`kid:base64key`) and `PAYLOAD_KEY_NEXT` serve server callers; rotation adds the
  next key on both sides, then swaps. Only `Config` reads them, and no log line holds one.
- `payload.config.json` says `strict`. `PAYLOAD_MODE=off` in your own shell bisects a transport
  problem; the service refuses to start with `off` in production.

## Refusals and tests (Rule 34)

- A refusal is a `PayloadCode` through `problem()`: plaintext problem+json, `type` = base + code,
  never the internal reason, which goes to the log with the code and the route pattern.
- The spec's `Problem.code` lists the five `ENVELOPE_*` codes (`payload::document`), and every
  operation that can refuse declares a 400.
- Tests go through the real cipher; `vectors_tests.rs` proves this copy against the shared
  `scripts/check/payload-vectors.json`, which is never regenerated to make a test pass.
