// Tests that api/openapi.yaml publishes the registry: the code enum and the problem-type base.

package apperr_test

import (
	"path/filepath"
	"slices"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"

	"example.com/service/internal/apperr"
)

// TestSpecPublishesTheRegistry holds api/openapi.yaml's Problem schema to the registry: the inline
// code enum lists exactly the registered codes (the web and iOS clients read it), and Problem.type
// is a required URI whose x-problem-type-base equals TypeBase.
func TestSpecPublishesTheRegistry(t *testing.T) {
	t.Parallel()
	doc, err := openapi3.NewLoader().LoadFromFile(filepath.Join(root, "api", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	ref := doc.Components.Schemas["Problem"]
	if ref == nil || ref.Value == nil {
		t.Fatal("api/openapi.yaml has no components.schemas.Problem")
	}
	problem := ref.Value
	for _, member := range []string{"type", "title", "status", "code", "requestId"} {
		if !slices.Contains(problem.Required, member) {
			t.Errorf("Problem.%s is not required", member)
		}
	}
	code := problem.Properties["code"]
	if code == nil || code.Ref != "" || code.Value == nil {
		t.Fatal("Problem.code must be an inline schema: the clients read its enum in place")
	}
	var spec []string
	for _, v := range code.Value.Enum {
		if s, ok := v.(string); ok {
			spec = append(spec, s)
		}
	}
	if slices.Sort(spec); !slices.Equal(spec, registeredNames()) {
		t.Errorf("Problem.code enum is %v; the registry holds %v", spec, registeredNames())
	}
	typ := problem.Properties["type"]
	if typ == nil || typ.Value == nil || typ.Value.Format != "uri" {
		t.Fatal(`Problem.type must be an inline string schema with format: uri`)
	}
	if base := typ.Value.Extensions["x-problem-type-base"]; base != apperr.TypeBase {
		t.Errorf("x-problem-type-base is %v; apperr.TypeBase is %q", base, apperr.TypeBase)
	}
}
