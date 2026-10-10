// Package httpapi is the HTTP layer: the server oapi-codegen generates from api/openapi.yaml, the
// handlers that implement it, and the middleware around them. Handlers decode nothing by hand and
// touch no database: they call a module's service and return its result or its error.
package httpapi

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/getkin/kin-openapi/openapi3"

	"example.com/service/internal/apperr"
)

// NewRouter returns the whole handler chain for the operations the spec declares. Outermost first:
// the request ID (so every later log line carries it), the access log, panic recovery, the body
// limit, validation against the spec, and the routes; a path or method no route takes is answered
// as a problem too.
func NewRouter(logger *slog.Logger, spec *openapi3.T, maxBody int64, handlers StrictServerInterface) (http.Handler, error) {
	validate, err := validateRequests(spec, logger)
	if err != nil {
		return nil, err
	}
	mux := http.NewServeMux()
	strict := NewStrictHandlerWithOptions(handlers, nil, StrictHTTPServerOptions{
		RequestErrorHandlerFunc:  unreadable(logger),
		ResponseErrorHandlerFunc: answer(logger),
	})
	HandlerWithOptions(strict, StdHTTPServerOptions{BaseRouter: mux, ErrorHandlerFunc: unreadable(logger)})

	chain := problemFallback(mux, logger)
	chain = validate(chain)
	chain = limitBody(chain, maxBody)
	chain = recoverer(chain, logger)
	chain = accessLog(chain, logger)
	chain = requestID(chain)
	return chain, nil
}

// answer hands an error a handler returned to the one problem writer.
func answer(logger *slog.Logger) func(http.ResponseWriter, *http.Request, error) {
	return func(w http.ResponseWriter, r *http.Request, err error) {
		apperr.Write(w, r, logger, err)
	}
}

// unreadable answers a request the generated code could not bind: a body that is not JSON, or a
// parameter it could not convert. Validation already refused what the spec forbids, so what is left
// is a request this route cannot read.
func unreadable(logger *slog.Logger) func(http.ResponseWriter, *http.Request, error) {
	return func(w http.ResponseWriter, r *http.Request, err error) {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			apperr.Write(w, r, logger, bodyTooLarge(err))
			return
		}
		apperr.Write(w, r, logger, apperr.Wrap(apperr.MalformedBody, "The request could not be read for this route.", err))
	}
}
