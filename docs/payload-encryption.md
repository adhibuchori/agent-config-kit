# Payload encryption

An opt-in module of agent-fe-nextjs, agent-be-hono and agent-ai-fastapi, and of the experimental
agent-be-go, agent-be-axum and agent-ios-swiftui. Every request and response body that crosses a service boundary travels sealed, every endpoint sits in one registry with its
policy, and two checks keep both true before anything merges. The contract itself ships into your
repo as `.claude/PAYLOAD-CONTRACT.md`; this page is the adopter's guide.

## What you get

| Piece | Where it lands | What it does |
| --- | --- | --- |
| The cipher | `src/lib/payload/` (TypeScript), `src/app/core/payload/` (Python), `internal/payload/` (Go), `src/payload/` (Rust), `Payload*.swift` in the app's `APIClient` target | AES-256-GCM envelopes bound to method, route pattern, status, key id and time; key rings with rotation; browser key agreement (ECDH P-256 + HKDF); the strict/off switch |
| The boundary | a Hono middleware; a browser transport and a server bridge; an ASGI middleware; a `net/http` middleware (Go); an axum `route_layer` (Rust); the last client middleware of the generated Swift client | Opens sealed requests before any validator, seals responses (with `Vary: x-payload-epk, x-payload-kid`), refuses plaintext on sealed routes in plaintext problem+json whose `type` is your API's problem-type base plus the code, never with the internal message |
| The registry | `src/lib/endpoints/` or `src/lib/api/endpoints/`, generated from `openapi.json`; in Go, Rust and Swift one file written by `scripts/generate/payload-registry.mjs` | Every route with its policy: `strict`, `response-only`, `request-only`, `none` (with a reason) |
| The checks | `check:endpoints`, `check:crypto-interop` (TypeScript); the seeded tests (Python, Go, Rust, Swift); `scripts/check/payload-registry.mjs` (Go, Rust, Swift) | Drift, reasons, route literals, raw `fetch`, the committed switch, peer parity; the shared test vectors |
| The contract | `.claude/PAYLOAD-CONTRACT.md`, `.claude/rules/common/payload-contract.md`, `payload.config.json` | The rules (P1–P10), the threat model, the wiring; the switch and the exemptions, committed |

All of it is seeded once and then yours, except the checks, the vectors and the contract, which
`sync` keeps current. The TypeScript cipher files are the same files in the frontend and the
backend; the kit's own tests prove that, and prove every check both ways. The Go, Rust and Swift
ports speak the same wire format and pass the same vectors, including a key-agreement answer: a
server also refuses a peer key that is not an uncompressed P-256 point.

## Turn it on

1. Run your stack's setup and answer `payload-encryption=yes`. Python services also run
   `uv add cryptography`.
2. Backend: `bun run spec:export`, then `bun run generate:endpoints`. Frontend: copy the backend's
   `openapi.json`, then `bun run generate:endpoints`. The gates now include `check:endpoints` and
   `check:crypto-interop`. Go, Rust and iOS: follow the steps setup prints (the module is wired in
   by hand, and the spec gains the `ENVELOPE_*` codes and the handshake), then
   `node scripts/generate/payload-registry.mjs`; the gate's `node scripts/check/payload-registry.mjs`
   stays red until the spec lists them.
3. Create the keys on your own machine, straight into the env file (after `bun unlock env`, see
   [unlocking](unlock.md)), never into a chat:

   ```bash
   printf 'k1:%s' "$(openssl rand -base64 32)" | bash scripts/env/set.sh .env.development PAYLOAD_KEY
   ```

   The same value goes on both sides of one hop; each hop gets its own variable. The frontend
   server's ECDH keypair (`PAYLOAD_SERVER_JWK`) comes from `generateServerKeyJwk()`, piped the same
   way; a Go or Rust server's comes from `node scripts/generate/payload-server-key.mjs`. An iOS app
   holds no key: it agrees one per session through the handshake.
4. Wire the boundary (the contract's § Wiring it in): mount the middleware after the body limit and
   rate limit, call `seal` and `read` around each request in the frontend's API transport, answer the
   handshake route, and bridge the proxy route. Register any route that cannot be sealed in
   `payload.config.json` `exemptions` with its reason, and regenerate.
5. Give the middleware your API's problem-type base, the one its error mapper mints every other
   problem's `type` from (`problemTypeBase` in TypeScript, `problem_type_base` in Python; Go and
   Rust refusals go through `apperr.TypeBase` and `PROBLEM_TYPE_BASE`). It must
   be an absolute https URI ending in `/`; the middleware refuses to start otherwise. The kit's
   placeholder, `https://example.invalid/problems/`, is for tests and local runs only.
6. Name the other repos in `peers` (`{ "name": "api", "root": "../api" }`) so the checks compare the
   spec copy, the exemptions and the cipher itself whenever both are checked out side by side.

## What it does not protect

The browser hop is not end-to-end encryption: the person using the browser holds the key. The module
buys integrity, route binding, replay resistance inside a two-minute window, and ciphertext in logs,
proxies and HAR files. Confidentiality still comes from TLS, httpOnly session cookies, a
server-side proxy and a tight `connect-src`. Server-to-server hops, whose keys never reach a
browser, are real defence in depth. Replays inside the window across ids of one route are possible
by design: preventing them needs a nonce store and shared state.

## Turning it off

For local debugging only: `PAYLOAD_MODE=off` in your own shell. The committed `payload.config.json`
stays `strict` (`check:endpoints` fails otherwise), and every service refuses to start with `off`
in production; an iOS Release build seals whatever the switch says. To remove the module, delete
`payload.config.json`: the checks then say the repo has not adopted the contract and pass, and you
can delete the seeded code.
