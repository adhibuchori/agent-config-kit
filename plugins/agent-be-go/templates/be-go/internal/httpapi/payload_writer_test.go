// Tests for the answer on a sealed route: what is sealed, what goes out as it is, and what is refused.

package httpapi

import (
	"bytes"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func answering(f func(w http.ResponseWriter)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { f(w) })
}

func TestAnAnswerWithNoBodyGoesOutAsItIs(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	for name, tt := range map[string]struct {
		handler http.Handler
		status  int
	}{
		"204":     {answering(func(w http.ResponseWriter) { w.WriteHeader(http.StatusNoContent) }), http.StatusNoContent},
		"304":     {answering(func(w http.ResponseWriter) { w.WriteHeader(http.StatusNotModified) }), http.StatusNotModified},
		"nothing": {answering(func(http.ResponseWriter) {}), http.StatusOK},
	} {
		rec := through(t, edge, tt.handler, c.request(t, http.MethodGet, "/api/notes/7", nil))
		if rec.Code != tt.status || rec.Body.Len() != 0 || rec.Header().Get("Vary") != "" {
			t.Errorf("%s: got %d %q, Vary %q", name, rec.Code, rec.Body.String(), rec.Header().Get("Vary"))
		}
	}
}

func TestABodyWithoutAStatusIsASealed200AndTheFirstStatusWins(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	rec := through(t, edge, answering(func(w http.ResponseWriter) { _, _ = w.Write([]byte(`[1,2]`)) }),
		c.request(t, http.MethodGet, "/api/notes/7", nil))
	if rec.Code != http.StatusOK || opened(t, rec, c.key, "/api/notes/:id") != `[1,2]` {
		t.Fatalf("got %d", rec.Code)
	}
	rec = through(t, edge, answering(func(w http.ResponseWriter) {
		w.WriteHeader(http.StatusAccepted)
		w.WriteHeader(http.StatusTeapot)
		_, _ = w.Write([]byte(`{}`))
	}), c.request(t, http.MethodGet, "/api/notes/7", nil))
	if rec.Code != http.StatusAccepted || opened(t, rec, c.key, "/api/notes/:id") != `{}` {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestAnAnswerThatIsNotJSONIsRefusedAndNeverSent(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	rec := through(t, edge, answering(func(w http.ResponseWriter) {
		w.Header().Set("X-Secret-Hint", "set by the handler")
		_, _ = w.Write([]byte("<html>internal page</html>"))
	}), c.request(t, http.MethodGet, "/api/notes/7", nil))
	refused(t, rec, http.StatusInternalServerError, "ENVELOPE_MALFORMED")
	if strings.Contains(rec.Body.String(), "internal page") || rec.Header().Get("X-Secret-Hint") != "" {
		t.Fatalf("the unsealed answer leaked: %v %s", rec.Header(), rec.Body.String())
	}
}

type brokenWriter struct{ *httptest.ResponseRecorder }

func (brokenWriter) Write([]byte) (int, error) { return 0, errors.New("connection closed") }

func TestAnAnswerTheClientStoppedReadingIsLogged(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	var got seen
	h := sealBodies(echo(&got), edge, payloadEndpoints, logger)
	h.ServeHTTP(brokenWriter{httptest.NewRecorder()}, c.request(t, http.MethodGet, "/api/notes/7", nil))
	if !strings.Contains(logs.String(), `"msg":"answer not written"`) {
		t.Fatalf("logs: %s", logs.String())
	}
}
