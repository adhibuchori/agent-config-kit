---
paths:
  - 'internal/payload/**'
  - 'internal/httpapi/payload*.go'
  - 'internal/httpapi/router.go'
  - 'internal/apperr/payload_codes.go'
  - 'internal/config/payload*.go'
  - 'cmd/api/main.go'
  - 'payload.config.json'
  - 'scripts/check/payload-vectors.json'
  - 'scripts/generate/payload-*.mjs'
---

# Payload contract (Go)

How this service holds the payload contract. The rules are `AGENTS.md` 28–32, which apply where
setup answered `payload-encryption=yes`. The wire format, the threat model and the policies are in
`.claude/PAYLOAD-CONTRACT.md`; the short form is `.claude/rules/common/payload-contract.md`.

## Sealed unless exempted (Rule 28)

- `internal/payload/registry.gen.go` lists every operation of `api/openapi.json` with its policy.
  `node scripts/generate/payload-registry.mjs` writes it from the spec and `payload.config.json`;
  generated-guard refuses a hand edit. Run it after every spec change, after
  `bash scripts/check/generated.sh --write`.
- A route leaves `strict` only through `exemptions` in `payload.config.json`, keyed
  `"METHOD /pattern"` with the `:param` form, with a reason that names a property of the body:
  `"GET /api/health": {"encryption": "none", "reason": "a load balancer's probe holds no key"}`.
  `node scripts/check/payload-registry.mjs` fails on drift, a reason missing or stale, and a spec
  whose `Problem.code` lacks the five `ENVELOPE_*` codes.

## At the transport only (Rule 29)

- `sealBodies` (`internal/httpapi/payload.go`) sits in `NewRouter` between the validator and the
  body limit: the limit applies to the envelope, the validator and the handlers read plaintext.
  oapi-codegen's strict middlewares run after the body is decoded, so they would be too late.
- It matches a request with a private `ServeMux` holding the registry's spec paths, so it follows
  the real router's precedence; the AAD takes the registry's `:param` pattern. A route the registry
  lacks passes through, and the router answers it.
- Only `internal/httpapi` and `cmd/` import `internal/payload` (`boundary_test.go`), and the core
  imports no `net/http`. A handler, service or store never sees an envelope, a key or the mode.
- The answer on a sealed route is held whole, then sealed with `Vary: x-payload-epk,
  x-payload-kid`. The writer has no `Flush`: a stream goes on a `request-only` route.

## Keys (Rule 30)

- `config.LoadPayload` reads `PAYLOAD_MODE`, `PAYLOAD_KEY`, `PAYLOAD_KEY_NEXT` and
  `PAYLOAD_SERVER_JWK`; `main` hands them to `payload.NewEdge`, which refuses a malformed key and
  names the variable, never the value. `config.Payload` logs as presence flags only.
- Make keys on your own machine and pipe them into the env file (`docs/unlock.md`):
  `printf 'k1:%s' "$(openssl rand -base64 32)" | bash scripts/env/set.sh .env.development PAYLOAD_KEY`
  for a server caller's key, set on both sides of the hop, and
  `node scripts/generate/payload-server-key.mjs | bash scripts/env/set.sh .env.development PAYLOAD_SERVER_JWK`
  for the key browsers and apps agree with. An agent never runs the key script:
  `.claude/settings.json` denies it, because its output is a private key.
- Rotation adds `PAYLOAD_KEY_NEXT`: deploy both sides with it, then swap the two values.

## The switch (Rule 31)

`payload.config.json` says `strict`, committed, and the generator copies it into
`registry.gen.go`. `PAYLOAD_MODE=off` in your own shell turns the edge off to bisect a transport
problem; `NewEdge` refuses `off` when `APP_ENV=production`, and refuses `strict` with no key at all.

## Refusals and vectors (Rule 32)

- A refusal is `apperr.Write` with the `ENVELOPE_*` code: a plaintext RFC 9457 problem whose `type`
  is the base plus the code, with the request ID and never the internal message. An answer the
  service cannot seal (not JSON) is `ENVELOPE_MALFORMED` as a 500, through `WithStatus`.
- `internal/payload/vectors_test.go` opens every vector of `scripts/check/payload-vectors.json`,
  refuses every replay and derives the agreement's key from both sides. The file is the same in
  every repo that speaks the format; never regenerate it to make a test pass.

## Wiring it in (once, by hand)

1. `internal/apperr/codes.go`: add `EnvelopeRequired, EnvelopeMalformed, EnvelopeExpired,
   EnvelopeKeyUnknown, EnvelopeRejected` to `Registered()`.
2. `api/openapi.yaml`: add the five names to `Problem.code`'s enum. When browsers or apps call the
   service, add the handshake (below) and exempt it, and the health probe, as `none`; otherwise
   drop `handshake` from `payload.config.json`. Then `bash scripts/check/generated.sh --write` and
   `node scripts/generate/payload-registry.mjs`. `handshake` names the operation as
   `api/openapi.json` spells it, and oapi-codegen's export capitalizes the first letter
   (`GetPayloadHandshake`); the check compares the two exactly.
3. `internal/httpapi/router.go`: `NewRouter` takes the edge, and the chain gains one line:

   ```go
   chain = validate(chain)
   chain = sealBodies(chain, edge, payload.Registry(), logger)
   chain = limitBody(chain, maxBody)
   ```

4. `cmd/api/main.go`: build the edge once and pass it to `NewRouter` and to `Handlers`:

   ```go
   pe := config.LoadPayload(os.LookupEnv)
   edge, err := payload.NewEdge(payload.Settings{
   	Mode: pe.Mode, Production: cfg.Production, ServerJWK: pe.ServerJWK, Key: pe.Key, KeyNext: pe.KeyNext,
   })
   ```

The handshake operation, in `api/openapi.yaml` under `paths`:

```yaml
/api/payload/handshake:
  get:
    operationId: getPayloadHandshake
    summary: Serve the public key a client agrees its payload key with
    responses:
      "200":
        description: The key and the mode; never cached.
        headers:
          Cache-Control:
            required: true
            schema:
              type: string
              enum: [no-store]
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/PayloadHandshake"
      "500":
        $ref: "#/components/responses/Problem"
```

with `PayloadHandshake` under `components.schemas`:

```yaml
PayloadHandshake:
  type: object
  additionalProperties: false
  required: [publicKey, mode]
  properties:
    publicKey:
      type: string
      description: The service's P-256 public key, base64url of the uncompressed point.
    mode:
      type: string
      enum: [strict, "off"] # quoted: YAML 1.1 reads a bare off as false
```

and its handler on `Handlers` (which gains a `Payload *payload.Edge` field):

```go
// GetPayloadHandshake serves the public key a client agrees its payload key with, and the mode.
func (h Handlers) GetPayloadHandshake(context.Context, GetPayloadHandshakeRequestObject) (GetPayloadHandshakeResponseObject, error) {
	hs := h.Payload.Handshake()
	body := PayloadHandshake{PublicKey: hs.PublicKey, Mode: PayloadHandshakeMode(hs.Mode)}
	return GetPayloadHandshake200JSONResponse{Body: body, Headers: GetPayloadHandshake200ResponseHeaders{CacheControl: "no-store"}}, nil
}
```
