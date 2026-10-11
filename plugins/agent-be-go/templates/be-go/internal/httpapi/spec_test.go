// Tests that every operation in the spec declares the errors the router can answer.

package httpapi_test

import (
	"strconv"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
)

// TestEveryOperationDeclaresItsErrors holds api/openapi.yaml to what the router can answer: every
// operation may fail with INTERNAL (500); one that takes a body or parameters can also get
// MALFORMED_BODY (400), BODY_TOO_LARGE (413) and VALIDATION_FAILED (422). Every error response is a
// Problem, and every request body object refuses unknown fields, because the generated decoder
// accepts them.
func TestEveryOperationDeclaresItsErrors(t *testing.T) {
	t.Parallel()
	spec := embedded(t)
	problem := spec.Components.Schemas["Problem"]
	if problem == nil {
		t.Fatal("api/openapi.yaml has no components.schemas.Problem")
	}
	for path, item := range spec.Paths.Map() {
		for method, op := range item.Operations() {
			checkOperation(t, method+" "+path, op, len(item.Parameters) > 0, problem.Value)
		}
	}
}

func checkOperation(t *testing.T, where string, op *openapi3.Operation, pathParams bool, problem *openapi3.Schema) {
	t.Helper()
	want := []int{500}
	if op.RequestBody != nil || len(op.Parameters) > 0 || pathParams {
		want = append(want, 400, 413, 422)
	}
	for _, status := range want {
		if op.Responses.Value(strconv.Itoa(status)) == nil {
			t.Errorf("%s does not declare %d", where, status)
		}
	}
	for code, res := range op.Responses.Map() {
		if status, err := strconv.Atoi(code); err == nil && status >= 400 {
			checkProblem(t, where+" "+code, res, problem)
		}
	}
	if op.RequestBody != nil {
		checkBody(t, where, op.RequestBody.Value)
	}
}

func checkBody(t *testing.T, where string, body *openapi3.RequestBody) {
	t.Helper()
	for mediaType, content := range body.Content {
		s := content.Schema.Value
		if s.Type.Is("object") && (s.AdditionalProperties.Has == nil || *s.AdditionalProperties.Has) {
			t.Errorf("%s %s body: set additionalProperties: false", where, mediaType)
		}
	}
}

func checkProblem(t *testing.T, where string, res *openapi3.ResponseRef, problem *openapi3.Schema) {
	t.Helper()
	content := res.Value.Content.Get("application/problem+json")
	if content == nil || content.Schema == nil || content.Schema.Value != problem {
		t.Errorf("%s: an error response that is not an application/problem+json Problem", where)
	}
}
