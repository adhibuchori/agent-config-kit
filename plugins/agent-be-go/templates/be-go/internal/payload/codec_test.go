// Tests for sealing and opening: the round trip, and each refusal in the order the checks run.

package payload

import (
	"encoding/json"
	"testing"
	"time"
)

func TestSealThenOpenRoundTrips(t *testing.T) {
	t.Parallel()
	key := mustKey(t, "codec")
	body := `{"text":"café, 東京","n":[1,2]}`
	raw, err := Seal([]byte(body), key, "k1", RequestAAD("POST", "/api/notes"), at)
	if err != nil {
		t.Fatal(err)
	}
	var e envelope
	if err := json.Unmarshal(raw, &e); err != nil || e.V != 1 || e.Alg != "A256GCM" || e.Kid != "k1" || e.TS != at.UnixMilli() {
		t.Fatalf("envelope %s: %v", raw, err)
	}
	plain, err := Open(raw, constKey(key), RequestAAD("POST", "/api/notes"), at.Add(MaxSkew))
	if err != nil || string(plain) != body {
		t.Fatalf("got %q, %v", plain, err)
	}
}

func TestSealRefusesABodyThatIsNotJSON(t *testing.T) {
	t.Parallel()
	_, err := Seal([]byte("<html>"), mustKey(t, "codec"), "k1", ResponseAAD(200, "/api/notes"), at)
	codeIs(t, err, Malformed)
}

func TestOpenRefusesInOrder(t *testing.T) {
	t.Parallel()
	key := mustKey(t, "codec")
	aad := RequestAAD("POST", "/api/notes")
	good, err := Seal([]byte(`{}`), key, "k1", aad, at)
	if err != nil {
		t.Fatal(err)
	}
	var e envelope
	if err := json.Unmarshal(good, &e); err != nil {
		t.Fatal(err)
	}
	unknown := func(kid string) (Key, error) { return Key{}, fail(KeyUnknown, "no %s", kid) }
	notBase64 := func(edit func(*envelope)) []byte { c := e; edit(&c); return envelopeJSON(t, c) }
	nonce, sealed := key.seal([]byte("not json"), aad("k1", e.TS))
	notJSON := envelopeJSON(t, envelope{V: 1, Alg: alg, Kid: "k1", IV: Encode(nonce), CT: Encode(sealed), TS: e.TS})
	tests := []struct {
		name   string
		raw    []byte
		keyFor KeyFor
		aad    AAD
		now    time.Time
		want   Code
	}{
		{"not an envelope", []byte(`{"title":"plain"}`), constKey(key), aad, at, Required},
		{"stale", good, constKey(key), aad, at.Add(MaxSkew + time.Millisecond), Expired},
		{"unknown kid", good, unknown, aad, at, KeyUnknown},
		{"iv not base64", notBase64(func(c *envelope) { c.IV = "*" }), constKey(key), aad, at, Rejected},
		{"ct not base64", notBase64(func(c *envelope) { c.CT = "*" }), constKey(key), aad, at, Rejected},
		{"another route", good, constKey(key), RequestAAD("POST", "/api/notes/:id/share"), at, Rejected},
		{"plaintext not JSON", notJSON, constKey(key), aad, at, Malformed},
	}
	for _, tt := range tests {
		_, err := Open(tt.raw, tt.keyFor, tt.aad, tt.now)
		if CodeOf(err) != tt.want || err == nil {
			t.Errorf("%s: got %v, want %s", tt.name, err, tt.want)
		}
	}
}
