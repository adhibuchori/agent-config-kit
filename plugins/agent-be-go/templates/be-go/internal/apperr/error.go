// The domain error: a registered code, a detail a client may see, and what only the logs see.

package apperr

import (
	"errors"
	"fmt"
)

// FieldError is one invalid request field: a JSON pointer and a problem code, never the value.
type FieldError struct {
	Pointer string `json:"pointer"`
	Code    string `json:"code"`
}

// Error is a domain error: a registered code, a detail that is safe to show a client, and what
// only the logs may see (the internal note and the cause).
type Error struct {
	Code     Code
	Detail   string
	internal string
	status   int
	fields   []FieldError
	cause    error
}

// New returns an error with a registered code and a client-safe detail.
func New(code Code, detail string) *Error {
	return &Error{Code: code, Detail: detail}
}

// Wrap returns an error that keeps cause for errors.Is and errors.As, and for the logs.
func Wrap(code Code, detail string, cause error) *Error {
	return &Error{Code: code, Detail: detail, cause: cause}
}

// Invalid returns a ValidationFailed error that names each invalid field.
func Invalid(fields ...FieldError) *Error {
	return &Error{Code: ValidationFailed, Detail: "The request does not match the contract.", fields: fields}
}

// WithInternal attaches a note for the logs; the response never carries it.
func (e *Error) WithInternal(format string, args ...any) *Error {
	e.internal = fmt.Sprintf(format, args...)
	return e
}

// WithStatus answers the error with status instead of its code's own, for the one code the contract
// gives two statuses: ENVELOPE_MALFORMED is a 400 for a caller's envelope and a 500 for an answer this
// service could not seal. A status outside 400..599 is ignored.
func (e *Error) WithStatus(status int) *Error {
	if status >= 400 && status <= 599 {
		e.status = status
	}
	return e
}

// Status is the HTTP status the error is answered with: WithStatus's, or else its code's.
func (e *Error) Status() int {
	if e.status != 0 {
		return e.status
	}
	return e.Code.status
}

func (e *Error) Error() string {
	if e.cause != nil {
		return e.Code.name + ": " + e.Detail + ": " + e.cause.Error()
	}
	return e.Code.name + ": " + e.Detail
}

func (e *Error) Unwrap() error { return e.cause }

// As returns the *Error in err's chain, or nil.
func As(err error) *Error {
	if e, ok := errors.AsType[*Error](err); ok {
		return e
	}
	return nil
}
