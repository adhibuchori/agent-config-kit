// The closed set of ways an envelope fails to become a body: a code for the wire, a message for the log.

package payload

import (
	"errors"
	"fmt"
)

// Code names one payload failure. internal/httpapi answers each with the apperr code of the same
// name, as a plaintext problem: the caller may hold no working key.
type Code string

// The five payload failures (.claude/PAYLOAD-CONTRACT.md § Refusals and error codes).
const (
	// Required: a sealed route received plaintext or a body that is not an envelope of a version this
	// build reads, or a request carried neither x-payload-epk nor a key ring to answer under.
	Required Code = "ENVELOPE_REQUIRED"
	// Malformed: the opened plaintext is not JSON, or x-payload-epk is not a P-256 point; as a 500,
	// an answer this service cannot seal because it is not JSON.
	Malformed Code = "ENVELOPE_MALFORMED"
	// Expired: the envelope's ts is outside the freshness window, a replay or two drifted clocks.
	Expired Code = "ENVELOPE_EXPIRED"
	// KeyUnknown: the kid names a key this side does not hold, or a client sent x-payload-epk to a
	// service that agrees no keys.
	KeyUnknown Code = "ENVELOPE_KEY_UNKNOWN"
	// Rejected: the tag did not verify (tampering, the wrong key, another route), or the nonce or a
	// base64 field is unreadable.
	Rejected Code = "ENVELOPE_REJECTED"
)

// Error is a payload failure. Its code crosses the wire; its message names routes and server state,
// so it goes to the log only.
type Error struct {
	Code Code
	msg  string
}

// Error is the code and the message, for the log.
func (e *Error) Error() string { return string(e.Code) + ": " + e.msg }

// CodeOf is the code of the payload failure in err's chain. Any other error is Malformed: the
// exchange could not complete, for a reason the contract does not name.
func CodeOf(err error) Code {
	if e, ok := errors.AsType[*Error](err); ok {
		return e.Code
	}
	return Malformed
}

func fail(code Code, format string, args ...any) *Error {
	return &Error{Code: code, msg: fmt.Sprintf(format, args...)}
}
