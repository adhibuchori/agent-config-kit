// Test helpers for the payload middleware: a service edge, a client that seals as a browser or an app
// would, and the chain the middleware sits in. Keys come from fixed labels: placeholder material.

package httpapi

import (
	"bytes"
	"crypto/ecdh"
	"crypto/sha256"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"example.com/service/internal/apperr"
	"example.com/service/internal/payload"
)

var payloadNow = time.UnixMilli(1_767_225_600_000)

var payloadEndpoints = []payload.Endpoint{
	{Method: http.MethodPost, Route: "/api/notes", Pattern: "/api/notes", Policy: payload.PolicyStrict},
	{Method: http.MethodGet, Route: "/api/notes/{id}", Pattern: "/api/notes/:id", Policy: payload.PolicyStrict},
	{Method: http.MethodPost, Route: "/api/uploads", Pattern: "/api/uploads", Policy: payload.PolicyResponseOnly, Reason: "multipart"},
	{Method: http.MethodPost, Route: "/api/events", Pattern: "/api/events", Policy: payload.PolicyRequestOnly, Reason: "a stream"},
	{Method: http.MethodGet, Route: "/api/health", Pattern: "/api/health", Policy: payload.PolicyNone, Reason: "a probe"},
}

func material(label string) []byte {
	sum := sha256.Sum256([]byte("httpapi payload test: " + label))
	return sum[:]
}

func party(t *testing.T, label string) *ecdh.PrivateKey {
	t.Helper()
	priv, err := ecdh.P256().NewPrivateKey(material(label))
	if err != nil {
		t.Fatal(err)
	}
	return priv
}

// payloadEdge is a service that agrees keys with clients and holds the ring key k1 for server callers.
func payloadEdge(t *testing.T, mode string) *payload.Edge {
	t.Helper()
	server := party(t, "server")
	point := server.PublicKey().Bytes()
	jwk, err := json.Marshal(map[string]string{
		"kty": "EC", "crv": "P-256", "d": payload.Encode(server.Bytes()),
		"x": payload.Encode(point[1:33]), "y": payload.Encode(point[33:]),
	})
	if err != nil {
		t.Fatal(err)
	}
	e, err := payload.NewEdge(payload.Settings{
		Mode: mode, ServerJWK: payload.Encode(jwk), Key: "k1:" + payload.Encode(material("k1")),
		Clock: func() time.Time { return payloadNow },
	})
	if err != nil {
		t.Fatal(err)
	}
	return e
}

// through sends req through the request ID, a 256-byte body limit and the middleware to next.
func through(t *testing.T, edge *payload.Edge, next http.Handler, req *http.Request) *httptest.ResponseRecorder {
	t.Helper()
	logger := slog.New(slog.DiscardHandler)
	rec := httptest.NewRecorder()
	requestID(limitBody(sealBodies(next, edge, payloadEndpoints, logger), 256)).ServeHTTP(rec, req)
	return rec
}

// seen is what the handler behind the middleware received.
type seen struct{ body, contentType string }

// echo records what it receives and answers 201 {"echo":true}, with a Content-Length of its own.
func echo(got *seen) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, err := io.ReadAll(r.Body)
		got.body, got.contentType = string(b), r.Header.Get("Content-Type")
		if err != nil {
			got.body = "unreadable"
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Content-Length", "13")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"echo":true}`))
	})
}

// client is a browser or an app: an ephemeral key, agreed with the key the handshake serves.
type client struct {
	key payload.Key
	epk string
}

func newClient(t *testing.T, edge *payload.Edge) client {
	t.Helper()
	priv := party(t, "client")
	point, err := payload.Decode(edge.Handshake().PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	pub, err := ecdh.P256().NewPublicKey(point)
	if err != nil {
		t.Fatal(err)
	}
	secret, err := priv.ECDH(pub)
	if err != nil {
		t.Fatal(err)
	}
	key, err := payload.DeriveKey(secret)
	if err != nil {
		t.Fatal(err)
	}
	return client{key: key, epk: payload.Encode(priv.PublicKey().Bytes())}
}

// seal is body sealed for a POST to pattern at when.
func (c client) seal(t *testing.T, body, pattern string, when time.Time) []byte {
	t.Helper()
	sealed, err := payload.Seal([]byte(body), c.key, payload.ECDHKid, payload.RequestAAD(http.MethodPost, pattern), when)
	if err != nil {
		t.Fatal(err)
	}
	return sealed
}

// request is a request carrying the client's key and, when body is not nil, that body as an envelope.
func (c client) request(t *testing.T, method, target string, body []byte) *http.Request {
	t.Helper()
	req := httptest.NewRequestWithContext(t.Context(), method, target, bytes.NewReader(body))
	req.Header.Set(payload.EPKHeader, c.epk)
	req.Header.Set("Content-Type", payload.MediaType)
	return req
}

// opened checks that rec is a sealed answer and opens it under key.
func opened(t *testing.T, rec *httptest.ResponseRecorder, key payload.Key, pattern string) string {
	t.Helper()
	ct, vary := rec.Header().Get("Content-Type"), rec.Header().Get("Vary")
	if ct != payload.MediaType || vary != "x-payload-epk, x-payload-kid" {
		t.Fatalf("a sealed answer: Content-Type %q, Vary %q", ct, vary)
	}
	if n := rec.Header().Get("Content-Length"); n != "" {
		t.Fatalf("the handler's Content-Length %s went out with the envelope", n)
	}
	plain, err := payload.Open(rec.Body.Bytes(), func(string) (payload.Key, error) { return key, nil },
		payload.ResponseAAD(rec.Code, pattern), payloadNow)
	if err != nil {
		t.Fatalf("%v: %s", err, rec.Body.String())
	}
	return string(plain)
}

// refused checks a plaintext problem: the status, type = base + code, the request ID, and for an
// ENVELOPE_* code no detail, since the internal message stays in the log.
func refused(t *testing.T, rec *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	var p map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil {
		t.Fatalf("%v: %s", err, rec.Body.String())
	}
	_, detail := p["detail"]
	leaked := detail && strings.HasPrefix(code, "ENVELOPE_")
	problemJSON := strings.HasPrefix(rec.Header().Get("Content-Type"), "application/problem+json")
	if rec.Code != status || p["code"] != code || p["type"] != apperr.TypeBase+code || leaked ||
		p["requestId"] != rec.Header().Get(HeaderRequestID) || !problemJSON {
		t.Fatalf("got %d %v, want %d %s", rec.Code, p, status, code)
	}
}
