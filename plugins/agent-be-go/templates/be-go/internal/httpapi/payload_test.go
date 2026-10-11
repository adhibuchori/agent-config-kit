// Tests for the payload middleware in the chain it sits in: sealed both ways for a client and for a
// server caller, what passes through, and every refusal as a plaintext problem.

package httpapi

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/iotest"
	"time"

	"example.com/service/internal/payload"
)

func TestAClientsSealedRequestIsOpenedAndTheAnswerSealed(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	var got seen
	rec := through(t, edge, echo(&got), c.request(t, http.MethodPost, "/api/notes", c.seal(t, `{"title":"x"}`, "/api/notes", payloadNow)))
	if got.body != `{"title":"x"}` || got.contentType != "application/json" {
		t.Fatalf("the handler saw %+v", got)
	}
	if rec.Code != http.StatusCreated || opened(t, rec, c.key, "/api/notes") != `{"echo":true}` {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestAServerCallerIsAnsweredUnderItsRingKey(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/notes/7", nil)
	req.Header.Set(payload.KIDHeader, "k1")
	var got seen
	rec := through(t, edge, echo(&got), req)
	key, err := payload.NewKey(material("k1"))
	if err != nil {
		t.Fatal(err)
	}
	if opened(t, rec, key, "/api/notes/:id") != `{"echo":true}` || !strings.Contains(rec.Body.String(), `"kid":"k1"`) {
		t.Fatalf("got %s", rec.Body.String())
	}
}

func TestWhatTheContractDoesNotCoverPassesThrough(t *testing.T) {
	t.Parallel()
	strict, off := payloadEdge(t, ""), payloadEdge(t, "off")
	for name, tt := range map[string]struct {
		edge   *payload.Edge
		method string
		target string
	}{
		"unregistered":        {strict, http.MethodGet, "/api/nothing"},
		"a HEAD on a GET":     {strict, http.MethodHead, "/api/notes/7"},
		"exempt":              {strict, http.MethodGet, "/api/health"},
		"an unclean path":     {strict, http.MethodGet, "/api//notes/7"},
		"mode off":            {off, http.MethodPost, "/api/notes"},
		"request-only answer": {strict, http.MethodPost, "/api/events"},
	} {
		var got seen
		body := `{"plain":true}`
		req := httptest.NewRequestWithContext(t.Context(), tt.method, tt.target, strings.NewReader(body))
		if name == "request-only answer" {
			c := newClient(t, strict)
			body = `{"sealed":true}`
			req = c.request(t, tt.method, tt.target, c.seal(t, body, "/api/events", payloadNow))
		}
		rec := through(t, tt.edge, echo(&got), req)
		if got.body != body || rec.Code != http.StatusCreated || rec.Body.String() != `{"echo":true}` || rec.Header().Get("Vary") != "" {
			t.Errorf("%s: the handler saw %+v and answered %d %s", name, got, rec.Code, rec.Body.String())
		}
	}
}

func TestAResponseOnlyRouteTakesAPlainBodyAndSealsTheAnswer(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	req := c.request(t, http.MethodPost, "/api/uploads", []byte("--boundary"))
	req.Header.Set("Content-Type", "multipart/form-data; boundary=boundary")
	var got seen
	rec := through(t, edge, echo(&got), req)
	if got.body != "--boundary" || opened(t, rec, c.key, "/api/uploads") != `{"echo":true}` {
		t.Fatalf("the handler saw %+v", got)
	}
}

func TestEveryEnvelopeFailureIsAPlaintextProblem(t *testing.T) {
	t.Parallel()
	edge := payloadEdge(t, "")
	c := newClient(t, edge)
	good := c.seal(t, `{"title":"x"}`, "/api/notes", payloadNow)
	tampered := bytes.Replace(good, []byte(`"ct":"`), []byte(`"ct":"AA`), 1)
	plain := c.request(t, http.MethodPost, "/api/notes", []byte(`{"title":"x"}`))
	plain.Header.Set("Content-Type", "application/json")
	badPoint := c.request(t, http.MethodPost, "/api/notes", good)
	badPoint.Header.Set(payload.EPKHeader, "*")
	unknownKid := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/notes/7", nil)
	unknownKid.Header.Set(payload.KIDHeader, "k9")
	stale := c.request(t, http.MethodPost, "/api/notes", c.seal(t, `{}`, "/api/notes", payloadNow.Add(-3*time.Minute)))
	elsewhere := c.request(t, http.MethodPost, "/api/notes", c.seal(t, `{}`, "/api/events", payloadNow))
	tooLarge := c.request(t, http.MethodPost, "/api/notes", bytes.Repeat([]byte("x"), 300))
	for name, tt := range map[string]struct {
		req    *http.Request
		status int
		code   string
	}{
		"plaintext":        {plain, http.StatusBadRequest, "ENVELOPE_REQUIRED"},
		"not a P-256 key":  {badPoint, http.StatusBadRequest, "ENVELOPE_MALFORMED"},
		"an unknown kid":   {unknownKid, http.StatusBadRequest, "ENVELOPE_KEY_UNKNOWN"},
		"tampered":         {c.request(t, http.MethodPost, "/api/notes", tampered), http.StatusBadRequest, "ENVELOPE_REJECTED"},
		"stale":            {stale, http.StatusBadRequest, "ENVELOPE_EXPIRED"},
		"another route's":  {elsewhere, http.StatusBadRequest, "ENVELOPE_REJECTED"},
		"over the limit":   {tooLarge, http.StatusRequestEntityTooLarge, "BODY_TOO_LARGE"},
		"a body cut short": {c.request(t, http.MethodPost, "/api/notes", nil), http.StatusBadRequest, "MALFORMED_BODY"},
	} {
		if name == "a body cut short" {
			tt.req.Body = io.NopCloser(iotest.ErrReader(errors.New("connection reset")))
		}
		var got seen
		rec := through(t, edge, echo(&got), tt.req)
		if got != (seen{}) {
			t.Errorf("%s: the handler ran: %+v", name, got)
		}
		refused(t, rec, tt.status, tt.code)
	}
}
