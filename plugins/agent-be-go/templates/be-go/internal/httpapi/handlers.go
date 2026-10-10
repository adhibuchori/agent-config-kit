// The handlers: one method per operation in api/openapi.yaml.

package httpapi

import "context"

// Handlers implements StrictServerInterface, one method per operation in api/openapi.yaml. A
// handler stays at 15 lines or fewer (handler_size_test.go): it calls a module's service and
// returns its result, or its error for the router to answer. The services it needs are its fields.
type Handlers struct{}

// GetHealth answers that the process serves requests.
func (Handlers) GetHealth(context.Context, GetHealthRequestObject) (GetHealthResponseObject, error) {
	return GetHealth200JSONResponse{Status: Ok}, nil
}
