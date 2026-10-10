// Package apperr holds the closed set of error codes a client can receive and the one writer that
// turns an error into an RFC 9457 problem response.
package apperr

import "net/http"

// Code is one registered error code. Its fields are unexported, so no other package can name a new
// code: the variables below are the registry. The zero Code is not registered, and Write answers it
// as Internal.
type Code struct {
	name   string
	status int
	title  string
}

// Name is the stable machine-readable code, for example "NOT_FOUND".
func (c Code) Name() string { return c.name }

// Status is the HTTP status the code is answered with.
func (c Code) Status() int { return c.status }

// Title is the short summary of the problem type, the same for every occurrence.
func (c Code) Title() string { return c.title }

// The registry: every code a client can receive, declared once, with its status and title.
// api/openapi.yaml lists the same names in Problem.code; registry_test.go fails when the two differ
// or when a code is never raised.
var (
	Internal         = Code{"INTERNAL", http.StatusInternalServerError, "Internal error"}
	NotFound         = Code{"NOT_FOUND", http.StatusNotFound, "No such route"}
	MethodNotAllowed = Code{"METHOD_NOT_ALLOWED", http.StatusMethodNotAllowed, "Method not allowed on this route"}
	MalformedBody    = Code{"MALFORMED_BODY", http.StatusBadRequest, "Request not readable"}
	BodyTooLarge     = Code{"BODY_TOO_LARGE", http.StatusRequestEntityTooLarge, "Request body too large"}
	ValidationFailed = Code{"VALIDATION_FAILED", http.StatusUnprocessableEntity, "Request failed validation"}
)

// Registered lists every code, in declaration order.
func Registered() []Code {
	return []Code{Internal, NotFound, MethodNotAllowed, MalformedBody, BodyTooLarge, ValidationFailed}
}

// Lookup returns the registered code with this name. A refusal relayed from an upstream service
// keeps its code and status only when this registry holds that code too.
func Lookup(name string) (Code, bool) {
	for _, c := range Registered() {
		if c.name == name {
			return c, true
		}
	}
	return Code{}, false
}
