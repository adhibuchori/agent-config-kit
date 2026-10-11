// Tests for the edge as internal/httpapi uses it: the settings it refuses, the handshake, and an
// exchange with a client key and with the key ring.

package payload

import (
	"testing"
	"time"
)

func TestNewEdgeRefusesWhatCannotRun(t *testing.T) {
	t.Parallel()
	for name, s := range map[string]Settings{
		"a typo":                 {Mode: "strcit"},
		"off in production":      {Mode: "off", Production: true},
		"a malformed server key": {ServerJWK: "*"},
		"a malformed ring key":   {Key: "no-kid"},
		"strict with no key":     {Mode: "strict"},
	} {
		if e, err := NewEdge(s); err == nil || e != nil {
			t.Errorf("%s: got %v, %v", name, e, err)
		}
	}
}

func TestAnEdgeSwitchedOffNeedsNoKey(t *testing.T) {
	t.Parallel()
	e, err := NewEdge(Settings{Mode: "off"})
	if err != nil || !e.Off() || e.Handshake() != (Handshake{Mode: "off"}) {
		t.Fatalf("got %+v, %v", e, err)
	}
	if now := e.clock(); time.Since(now) > time.Minute {
		t.Fatalf("the default clock is not the wall clock: %v", now)
	}
}

func TestExchangeWithAClientKey(t *testing.T) {
	t.Parallel()
	server := p256(t, "edge server")
	e, err := NewEdge(Settings{ServerJWK: jwkOf(t, server, server.PublicKey()), Clock: clock})
	if err != nil || e.Off() {
		t.Fatalf("got %+v, %v", e, err)
	}
	h := e.Handshake()
	if h.Mode != "strict" || h.PublicKey != Encode(server.PublicKey().Bytes()) {
		t.Fatalf("handshake %+v", h)
	}
	client := p256(t, "edge client")
	key := clientKey(t, client, h.PublicKey)
	body, err := Seal([]byte(`{"title":"x"}`), key, ECDHKid, RequestAAD("POST", "/api/notes"), at)
	if err != nil {
		t.Fatal(err)
	}
	x, err := e.Exchange(Encode(client.PublicKey().Bytes()), "k1")
	if err != nil {
		t.Fatal(err)
	}
	plain, err := x.OpenRequest(body, MediaType+"; charset=utf-8", "POST", "/api/notes")
	if err != nil || string(plain) != `{"title":"x"}` {
		t.Fatalf("opened %q, %v", plain, err)
	}
	answer, err := x.SealResponse([]byte(`{"id":1}`), 201, "/api/notes")
	if err != nil {
		t.Fatal(err)
	}
	if got, err := Open(answer, constKey(key), ResponseAAD(201, "/api/notes"), at); err != nil || string(got) != `{"id":1}` {
		t.Fatalf("answer %q, %v", got, err)
	}
	if plain, err := x.OpenRequest(nil, "", "POST", "/api/notes"); plain != nil || err != nil {
		t.Fatalf("an empty body: %q, %v", plain, err)
	}
	_, err = x.OpenRequest([]byte(`{"title":"x"}`), "application/json", "POST", "/api/notes")
	codeIs(t, err, Required)
	_, err = e.Exchange("*", "")
	codeIs(t, err, Malformed)
	_, err = e.Exchange("", "")
	codeIs(t, err, Required)
}

func TestExchangeWithTheKeyRing(t *testing.T) {
	t.Parallel()
	e, err := NewEdge(Settings{Key: "k1:" + Encode(labelled("k1")), KeyNext: "k2:" + Encode(labelled("k2")), Clock: clock})
	if err != nil || e.Handshake().PublicKey != "" {
		t.Fatalf("got %+v, %v", e, err)
	}
	x, err := e.Exchange("", "")
	if err != nil || x.kid != "k1" {
		t.Fatalf("got %+v, %v", x, err)
	}
	// Mid-rotation: the caller already seals with k2, and the answer goes out under its primary.
	body, err := Seal([]byte(`[1]`), mustKey(t, "k2"), "k2", RequestAAD("PUT", "/api/notes/:id"), at)
	if err != nil {
		t.Fatal(err)
	}
	if plain, err := x.OpenRequest(body, MediaType, "PUT", "/api/notes/:id"); err != nil || string(plain) != `[1]` {
		t.Fatalf("opened %q, %v", plain, err)
	}
	if x, err := e.Exchange("", "k2"); err != nil || x.kid != "k2" {
		t.Fatalf("x-payload-kid k2: %+v, %v", x, err)
	}
	_, err = e.Exchange("", "k3")
	codeIs(t, err, KeyUnknown)
	_, err = e.Exchange(Encode(p256(t, "edge client").PublicKey().Bytes()), "")
	codeIs(t, err, KeyUnknown)
}
