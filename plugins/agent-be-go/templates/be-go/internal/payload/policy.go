// The registry's types. Every operation of the spec is one Endpoint carrying both halves of the
// contract, where it lives and what happens to its bodies, so no route exists without a decision.
// registry.gen.go holds them, written from api/openapi.json and payload.config.json by
// scripts/generate/payload-registry.mjs; a policy is decided in the config, never in the output.

package payload

import "slices"

// Policy says which sides of an exchange are sealed. A half-policy names the side that cannot be
// sealed, for a property of its body, never for how sensitive the body looks.
type Policy string

// The four policies (.claude/PAYLOAD-CONTRACT.md § Policies).
const (
	// PolicyStrict seals both sides: every route unless payload.config.json exempts it.
	PolicyStrict Policy = "strict"
	// PolicyResponseOnly seals the answer only: a multipart upload, whose boundary must reach the parser.
	PolicyResponseOnly Policy = "response-only"
	// PolicyRequestOnly seals the request only: an event stream, or a file a browser saves or draws.
	PolicyRequestOnly Policy = "request-only"
	// PolicyNone seals neither: health probes, the spec, the handshake, a third party's webhook.
	PolicyNone Policy = "none"
)

// SealsRequest says whether the policy seals the request body. Transports ask this, never compare
// policy strings.
func (p Policy) SealsRequest() bool { return p == PolicyStrict || p == PolicyRequestOnly }

// SealsResponse says whether the policy seals the response body.
func (p Policy) SealsResponse() bool { return p == PolicyStrict || p == PolicyResponseOnly }

// Endpoint is one operation of the spec and its policy. Route is the spec's path (/api/things/{id}),
// which the router matches; Pattern is the same path as /api/things/:id, which both sides put in the
// AAD. Reason says why a policy is not strict.
type Endpoint struct {
	Method, Route, Pattern string
	Policy                 Policy
	Reason                 string
}

// Registry is every operation of the spec, as registry.gen.go lists it.
func Registry() []Endpoint { return slices.Clone(registry) }
