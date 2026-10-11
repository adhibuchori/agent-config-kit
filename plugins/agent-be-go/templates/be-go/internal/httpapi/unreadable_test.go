// Tests for the answer to a request the generated code cannot bind.

package httpapi

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"example.com/service/internal/apperr"
)

// The generated code calls unreadable when it cannot bind a request; the routes this repo starts
// with take no body or parameter, so the call is made here directly.
func TestUnreadableRequests(t *testing.T) {
	t.Parallel()
	tests := []struct {
		err  error
		want apperr.Code
	}{
		{fmt.Errorf("can't decode JSON body: %w", &json.SyntaxError{}), apperr.MalformedBody},
		{fmt.Errorf("can't decode JSON body: %w", &http.MaxBytesError{Limit: 1}), apperr.BodyTooLarge},
	}
	for _, tt := range tests {
		rec := httptest.NewRecorder()
		req := httptest.NewRequestWithContext(t.Context(), http.MethodPost, "/", nil)
		unreadable(slog.New(slog.DiscardHandler))(rec, req, tt.err)
		var p apperr.Problem
		if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil || rec.Code != tt.want.Status() || p.Code != tt.want.Name() {
			t.Errorf("%v: got %d %+v (%v), want %s", tt.err, rec.Code, p, err, tt.want.Name())
		}
	}
}
