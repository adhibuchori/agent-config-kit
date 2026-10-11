// Tests for request validation: fields, rules, unreadable and oversized bodies.

package httpapi_test

import (
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"

	"example.com/service/internal/apperr"
	"example.com/service/internal/httpapi"
)

// A spec with one operation that takes a body and a parameter, so validation runs on both. Its
// servers list must not matter: the validator matches paths only.
const bodySpec = `
openapi: 3.0.3
info: {title: test, version: "1"}
servers: [{url: "https://api.example.com"}]
paths:
  /api/notes:
    post:
      operationId: postNote
      parameters:
        - {name: limit, in: query, schema: {type: integer, maximum: 10}}
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              additionalProperties: false
              required: [title]
              properties:
                title: {type: string, minLength: 1}
      responses:
        "201": {description: created}
`

func notesSpec(t *testing.T) *openapi3.T {
	t.Helper()
	spec, err := openapi3.NewLoader().LoadFromData([]byte(bodySpec))
	if err != nil {
		t.Fatal(err)
	}
	return spec
}

func post(t *testing.T, target, body string) *http.Request {
	t.Helper()
	req := httptest.NewRequestWithContext(t.Context(), http.MethodPost, target, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	return req
}

func TestValidationNamesEachFieldAndRule(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, target, body string
		want               []apperr.FieldError
	}{
		{"missing field", "/api/notes", `{}`, []apperr.FieldError{{Pointer: "/title", Code: "required"}}},
		{"unknown and wrong-case keys", "/api/notes", `{"title":"a","Title":"b"}`, []apperr.FieldError{{Pointer: "/Title", Code: "additionalProperties"}}},
		{"too short", "/api/notes", `{"title":""}`, []apperr.FieldError{{Pointer: "/title", Code: "minLength"}}},
		{"parameter", "/api/notes?limit=50", `{"title":"a"}`, []apperr.FieldError{{Pointer: "/query/limit", Code: "maximum"}}},
		{"no body", "/api/notes", ``, []apperr.FieldError{{Pointer: "", Code: "invalid"}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			res, _ := serve(t, notesSpec(t), httpapi.Handlers{}, post(t, tt.target, tt.body))
			p := problemOf(t, res, http.StatusUnprocessableEntity, "VALIDATION_FAILED")
			if !slices.Equal(p.Fields, tt.want) {
				t.Fatalf("fields %+v, want %+v", p.Fields, tt.want)
			}
			if strings.Contains(p.Detail, `"b"`) {
				t.Fatalf("a value leaked into the problem: %+v", p)
			}
		})
	}
}

func TestValidationRefusesUnreadableBodies(t *testing.T) {
	t.Parallel()
	res, _ := serve(t, notesSpec(t), httpapi.Handlers{}, post(t, "/api/notes", `{"title":`))
	problemOf(t, res, http.StatusBadRequest, "MALFORMED_BODY")
	res, _ = serve(t, notesSpec(t), httpapi.Handlers{}, post(t, "/api/notes", `{"title":"`+strings.Repeat("a", 100)+`"}`))
	problemOf(t, res, http.StatusRequestEntityTooLarge, "BODY_TOO_LARGE")
}

func TestAValidRequestReachesTheRoutes(t *testing.T) {
	t.Parallel()
	// The spec declares the operation but no handler serves it here, so the router answers.
	res, _ := serve(t, notesSpec(t), httpapi.Handlers{}, post(t, "/api/notes?limit=3", `{"title":"a"}`))
	problemOf(t, res, http.StatusNotFound, "NOT_FOUND")
}
