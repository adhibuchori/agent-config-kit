// Request validation against the spec, before any handler reads the request.

package httpapi

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"strings"

	"github.com/getkin/kin-openapi/openapi3"
	"github.com/getkin/kin-openapi/openapi3filter"
	"github.com/getkin/kin-openapi/routers/legacy"

	"example.com/service/internal/apperr"
)

// validateRequests checks each request against the operation the spec declares for it before any
// handler reads it: unknown and missing fields, types, formats and bounds, in the body and in the
// parameters. The generated code decodes with plain encoding/json, which accepts unknown keys and
// matches names without regard to case; this is what refuses them. A request no operation matches
// passes on, so the router answers it as NOT_FOUND or METHOD_NOT_ALLOWED.
func validateRequests(spec *openapi3.T, logger *slog.Logger) (func(http.Handler) http.Handler, error) {
	doc := *spec
	// Paths only: with a servers list the router would also compare the request's Host header.
	doc.Servers = nil
	router, err := legacy.NewRouter(&doc)
	if err != nil {
		return nil, fmt.Errorf("httpapi: route the spec: %w", err)
	}
	options := &openapi3filter.Options{MultiError: true, AuthenticationFunc: openapi3filter.NoopAuthenticationFunc}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			route, params, err := router.FindRoute(r)
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}
			input := &openapi3filter.RequestValidationInput{Request: r, PathParams: params, Route: route, Options: options}
			if err := openapi3filter.ValidateRequest(r.Context(), input); err != nil {
				apperr.Write(w, r, logger, refusal(err))
				return
			}
			next.ServeHTTP(w, r)
		})
	}, nil
}

// refusal turns a validation error into the client's answer: BODY_TOO_LARGE, MALFORMED_BODY for a
// body that is not JSON, or VALIDATION_FAILED naming each field and the rule it broke, never its
// value.
func refusal(err error) error {
	if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
		return bodyTooLarge(err)
	}
	if _, ok := errors.AsType[*openapi3filter.ParseError](err); ok {
		return apperr.Wrap(apperr.MalformedBody, "The request body is not valid JSON.", err)
	}
	return apperr.Invalid(collect(err, nil)...)
}

func bodyTooLarge(err error) *apperr.Error {
	return apperr.Wrap(apperr.BodyTooLarge, "The request body is larger than this service accepts.", err)
}

var (
	pointerEscape = strings.NewReplacer("~", "~0", "/", "~1")
	unsupported   = regexp.MustCompile(`^property "(.*)" is unsupported$`)
)

// collect walks the validator's error tree node by node: a MultiError holds one error per problem, a
// RequestError names the parameter, a SchemaError the field and the rule it broke. A field is a JSON
// pointer into the body, or /<in>/<name> for a parameter.
func collect(err error, param *openapi3.Parameter) []apperr.FieldError {
	switch e := err.(type) { //nolint:errorlint // the validator's own tree, read node by node, not through errors.As.
	case openapi3.MultiError:
		out := make([]apperr.FieldError, 0, len(e))
		for _, inner := range e {
			out = append(out, collect(inner, param)...)
		}
		return out
	case *openapi3filter.RequestError:
		if e.Parameter != nil {
			param = e.Parameter
		}
		return collect(e.Err, param)
	case *openapi3.SchemaError:
		f := apperr.FieldError{Pointer: pointerOf(param), Code: e.SchemaField}
		for _, part := range e.JSONPointer() {
			f.Pointer += "/" + pointerEscape.Replace(part)
		}
		if m := unsupported.FindStringSubmatch(e.Reason); e.SchemaField == "properties" && m != nil {
			f.Pointer += "/" + pointerEscape.Replace(m[1])
			f.Code = "additionalProperties"
		}
		return []apperr.FieldError{f}
	}
	return []apperr.FieldError{{Pointer: pointerOf(param), Code: "invalid"}}
}

func pointerOf(param *openapi3.Parameter) string {
	if param == nil {
		return ""
	}
	return "/" + param.In + "/" + pointerEscape.Replace(param.Name)
}
