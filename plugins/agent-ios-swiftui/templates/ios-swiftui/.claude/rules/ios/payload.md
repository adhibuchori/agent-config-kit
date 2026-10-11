---
paths:
  - 'Packages/AppCore/Sources/APIClient/**'
  - 'Packages/AppCore/Tests/APIClientTests/Payload*'
  - 'payload.config.json'
  - 'scripts/check/payload-vectors.json'
---

# Sealed bodies: the app's half of the payload contract

How to follow AGENTS.md Rules 29 to 33, which apply because setup answered
`payload-encryption=yes`. The contract itself, its threat model and the wire format are in
`.claude/PAYLOAD-CONTRACT.md`; this file is how the app takes part.

## The pieces (Rules 29 and 30)

| File in `Sources/APIClient/` | Holds |
| --- | --- |
| `PayloadEndpoints.generated.swift` | every operation of the spec copy by operation ID, with its pattern and policy; generated |
| `PayloadRegistry.swift` | the policies and what each seals; `honoursOff`, the build's rule for `off` |
| `PayloadSession.swift` | the handshake and the session's agreed key |
| `PayloadMiddleware.swift` | the only place a body is sealed or opened |
| `PayloadProblem.swift` | `AppProblem(failure:)`, the one error mapper |
| `PayloadEnvelope`, `PayloadCipher`, `PayloadKeyAgreement`, `PayloadCodec`, `PayloadBase64URL`, `PayloadError` | the wire format, AES-256-GCM, ECDH P-256 with HKDF-SHA-256, and the five codes |

Every payload type is `internal`: only `PayloadSession`'s and `PayloadMiddleware`'s initialisers
are `package`, so a screen cannot seal, open or log a body even by accident.

- After `bash scripts/ios/api-client.sh`, run `node scripts/generate/payload-registry.mjs`;
  `node scripts/check/payload-registry.mjs` fails a stale registry and an operation the client has
  that the registry lacks. The middleware refuses an unregistered operation with
  `ENVELOPE_REQUIRED` rather than send it in plaintext.
- An operation leaves `strict` only through `payload.config.json` `exemptions`, keyed
  `"METHOD /pattern"` with the spec's `:param` pattern and a reason. Choose by the body: a multipart
  upload is `response-only`, an event stream or a file the app saves is `request-only`.

## Wiring (Rule 30)

Build one session per server in the composition root and hand it to every API for that server.
Each API sends through the session's transport, with `PayloadMiddleware` last in its middlewares,
so it runs innermost and every other middleware sees plaintext:

```swift
package struct OrdersAPI: Sendable {
    private let client: Client

    package init(serverURL: URL, payload: PayloadSession) {
        // Another middleware (auth, logging) goes before PayloadMiddleware, never after it.
        client = Client(
            serverURL: serverURL, transport: payload.transport, middlewares: [PayloadMiddleware(session: payload)])
    }

    package func orders() async throws -> [Order] {
        do {
            return try await client.listOrders().orders()
        } catch {
            throw AppProblem(failure: error)
        }
    }
}
```

The handshake goes to the transport directly, never through the client, so it is not sealed and
cannot recurse. A test builds the session and the middleware with their internal initialisers and
a canned transport, and a fake server that seals with the real cipher (`PayloadTestServer.swift`).

## Keys and the switch (Rule 31)

- The app holds no payload secret: a bundle is readable. Each session mints an ephemeral P-256
  key, agrees an AES-256 key with the server's public key from the handshake, and keeps it in
  memory only, never in the Keychain or on disk. `ENVELOPE_REJECTED`, from either side, drops it,
  and the next request agrees again: that is what a server with a new key pair looks like.
- The server's payload key is not pinned: pinning it would strand every installed app when the
  server rotates. Where an active interceptor matters, pin TLS with `NSPinnedDomains`.
- `PayloadSession(serverURL:)` sends through a URLSession with no `URLCache`: a sealed answer is
  bound to one session's key, and URLCache does not honour `Vary`. A transport of your own needs
  the same.
- `off`, from the committed switch or the handshake, is honoured only by a debug build
  (`PayloadRegistry.honoursOff`); a Release build seals regardless.

## Errors (Rule 32)

Every `package` call of the APIClient ends in `catch { throw AppProblem(failure: error) }`. It turns
a payload failure, which the client hands over inside a `ClientError`, into the problem of its
`ENVELOPE_*` code under `AppProblem.typeBase`, the same problem a refusal from the server names.
Once the backend's spec lists the five codes, `scripts/check/error-codes.sh` makes `ProblemCode`
list them too and asks for their messages, and every screen's switch over `knownCode` maps them.

## Vectors (Rule 33)

`PayloadVectorsTests` reads `scripts/check/payload-vectors.json`, the file every implementation of
the contract shares: the AAD strings byte for byte, the ciphertexts to open, the replays to refuse,
a key agreement from both sides and the points to refuse. A failure there means this copy drifted;
never regenerate the vectors to pass.

## Adopting it

1. The backend adds `GET /api/payload/handshake` (`200 {publicKey, mode}`, exempted `none`) and the
   five `ENVELOPE_*` codes to its `Problem.code`.
2. Copy its spec, and set `handshake` in `payload.config.json` to the operationId the spec gives the
   handshake, copied as written (`getPayloadHandshake` is the seed; a Go backend exports
   `GetPayloadHandshake`). Run `bash scripts/ios/api-client.sh`, then
   `node scripts/generate/payload-registry.mjs`.
3. Add the five `ProblemCode` cases and their `problem.ENVELOPE_*` messages
   (`bash scripts/check/error-codes.sh` names what is missing), then map them in each screen.
4. Wire each API as above, then run `bash scripts/check/gates.sh`. The gates stay red until steps
   1 to 3 are done, on purpose: half an adoption never passes quietly.
