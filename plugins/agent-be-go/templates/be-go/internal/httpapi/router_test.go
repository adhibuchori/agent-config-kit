// Tests through the whole router: routes, fallbacks, handler errors and panics.

package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"

	"example.com/service/internal/apperr"
	"example.com/service/internal/httpapi"
)

// serve sends one request through the whole chain NewRouter builds and returns the response and
// what was logged.
func serve(t *testing.T, spec *openapi3.T, handlers httpapi.StrictServerInterface, req *http.Request) (*httptest.ResponseRecorder, string) {
	t.Helper()
	var logs bytes.Buffer
	router, err := httpapi.NewRouter(slog.New(slog.NewJSONHandler(&logs, nil)), spec, 64, handlers)
	if err != nil {
		t.Fatal(err)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec, logs.String()
}

func embedded(t *testing.T) *openapi3.T {
	t.Helper()
	spec, err := httpapi.GetSpec()
	if err != nil {
		t.Fatal(err)
	}
	return spec
}

// problemOf decodes a problem body and checks the parts every problem shares: the content type,
// type = base + code, and the request ID equal to the response header.
func problemOf(t *testing.T, res *httptest.ResponseRecorder, wantStatus int, wantCode string) apperr.Problem {
	t.Helper()
	var p apperr.Problem
	if err := json.Unmarshal(res.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	if res.Code != wantStatus || p.Status != wantStatus || p.Code != wantCode ||
		p.Type != apperr.TypeBase+wantCode || res.Header().Get("Content-Type") != "application/problem+json" {
		t.Fatalf("got %d %s %+v", res.Code, res.Header().Get("Content-Type"), p)
	}
	if id := res.Header().Get(httpapi.HeaderRequestID); id == "" || p.RequestID != id {
		t.Fatalf("request ID: header %q, body %q", id, p.RequestID)
	}
	return p
}

func TestHealthAnswersThroughTheGeneratedRoute(t *testing.T) {
	t.Parallel()
	res, logs := serve(t, embedded(t), httpapi.Handlers{}, httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/health", nil))
	if body := strings.TrimSpace(res.Body.String()); res.Code != http.StatusOK || body != `{"status":"ok"}` {
		t.Fatalf("got %d %s", res.Code, body)
	}
	if !strings.Contains(logs, `"pattern":"GET /api/health"`) || !strings.Contains(logs, `"status":200`) {
		t.Fatalf("access log: %s", logs)
	}
}

func TestUnknownPathAndMethodAreProblems(t *testing.T) {
	t.Parallel()
	res, _ := serve(t, embedded(t), httpapi.Handlers{}, httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/nothing", nil))
	problemOf(t, res, http.StatusNotFound, "NOT_FOUND")
	res, _ = serve(t, embedded(t), httpapi.Handlers{}, httptest.NewRequestWithContext(t.Context(), http.MethodDelete, "/api/health", nil))
	problemOf(t, res, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED")
	if allow := res.Header().Get("Allow"); !strings.Contains(allow, http.MethodGet) {
		t.Fatalf("Allow: %q", allow)
	}
}

type failing struct{ err error }

func (f failing) GetHealth(context.Context, httpapi.GetHealthRequestObject) (httpapi.GetHealthResponseObject, error) {
	return nil, f.err
}

type panicking struct{ value any }

func (p panicking) GetHealth(context.Context, httpapi.GetHealthRequestObject) (httpapi.GetHealthResponseObject, error) {
	panic(p.value)
}

func TestHandlerErrorsBecomeProblems(t *testing.T) {
	t.Parallel()
	get := func() *http.Request {
		return httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/health", nil)
	}
	res, _ := serve(t, embedded(t), failing{apperr.New(apperr.NotFound, "gone")}, get())
	problemOf(t, res, http.StatusNotFound, "NOT_FOUND")
	res, logs := serve(t, embedded(t), failing{errors.New("pg: down")}, get())
	if p := problemOf(t, res, http.StatusInternalServerError, "INTERNAL"); p.Detail != "" {
		t.Fatalf("an internal error leaked its message: %+v", p)
	}
	if !strings.Contains(logs, "pg: down") {
		t.Fatalf("the cause belongs in the log: %s", logs)
	}
	res, logs = serve(t, embedded(t), panicking{"boom"}, get())
	problemOf(t, res, http.StatusInternalServerError, "INTERNAL")
	if !strings.Contains(logs, `"msg":"panic"`) {
		t.Fatalf("the panic was not logged: %s", logs)
	}
}

func TestAnAbortedHandlerIsLetThrough(t *testing.T) {
	t.Parallel()
	defer func() {
		if v := recover(); v != http.ErrAbortHandler { //nolint:errorlint // the recovered value itself, never wrapped.
			t.Fatalf("recovered %v, want http.ErrAbortHandler", v)
		}
	}()
	serve(t, embedded(t), panicking{http.ErrAbortHandler}, httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/health", nil))
	t.Fatal("http.ErrAbortHandler was swallowed")
}

func TestNewRouterRefusesASpecItCannotRoute(t *testing.T) {
	t.Parallel()
	if _, err := httpapi.NewRouter(slog.New(slog.DiscardHandler), &openapi3.T{}, 64, httpapi.Handlers{}); err == nil {
		t.Fatal("an empty spec was accepted")
	}
}
