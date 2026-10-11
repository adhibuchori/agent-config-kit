// The payload contract's refusals (.claude/PAYLOAD-CONTRACT.md § Refusals and error codes): the codes
// internal/httpapi answers a failed envelope with. Add each to Registered() in codes.go and to
// Problem.code in api/openapi.yaml; registry_test.go and contract_test.go fail until both list them.

package apperr

import "net/http"

// The five payload codes. ENVELOPE_MALFORMED goes out as a 500 through WithStatus when the answer
// this service wrote cannot be sealed.
var (
	EnvelopeRequired   = Code{"ENVELOPE_REQUIRED", http.StatusBadRequest, "Sealed body required"}
	EnvelopeMalformed  = Code{"ENVELOPE_MALFORMED", http.StatusBadRequest, "Malformed envelope"}
	EnvelopeExpired    = Code{"ENVELOPE_EXPIRED", http.StatusBadRequest, "Envelope expired"}
	EnvelopeKeyUnknown = Code{"ENVELOPE_KEY_UNKNOWN", http.StatusBadRequest, "Unknown payload key"}
	EnvelopeRejected   = Code{"ENVELOPE_REJECTED", http.StatusBadRequest, "Envelope rejected"}
)
