// Test material: keys from fixed labels (placeholder bytes, never a real key) and a fixed clock.

package payload

import (
	"crypto/ecdh"
	"crypto/sha256"
	"encoding/json"
	"testing"
	"time"
)

// at is the instant every test seals and opens at, unless it moves the clock on purpose.
var at = time.UnixMilli(1_767_225_600_000)

func clock() time.Time { return at }

// labelled is 32 bytes of test material named by label.
func labelled(label string) []byte {
	sum := sha256.Sum256([]byte(label))
	return sum[:]
}

func mustKey(t *testing.T, label string) Key {
	t.Helper()
	key, err := NewKey(labelled(label))
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func constKey(key Key) KeyFor { return func(string) (Key, error) { return key, nil } }

// p256 is the P-256 key pair whose scalar is labelled(label).
func p256(t *testing.T, label string) *ecdh.PrivateKey {
	t.Helper()
	priv, err := ecdh.P256().NewPrivateKey(labelled(label))
	if err != nil {
		t.Fatal(err)
	}
	return priv
}

// jwkOf is PAYLOAD_SERVER_JWK for priv: base64url of the JWK text {kty, crv, d, x, y}, with x and y
// taken from pub (priv's own public key, unless a test passes another).
func jwkOf(t *testing.T, priv *ecdh.PrivateKey, pub *ecdh.PublicKey) string {
	t.Helper()
	point := pub.Bytes()
	text, err := json.Marshal(map[string]string{
		"kty": "EC", "crv": "P-256", "d": Encode(priv.Bytes()), "x": Encode(point[1:33]), "y": Encode(point[33:]),
	})
	if err != nil {
		t.Fatal(err)
	}
	return Encode(text)
}

// clientKey is the session key a client holding priv agrees with the server whose point is server.
func clientKey(t *testing.T, priv *ecdh.PrivateKey, server string) Key {
	t.Helper()
	raw, err := Decode(server)
	if err != nil {
		t.Fatal(err)
	}
	pub, err := ecdh.P256().NewPublicKey(raw)
	if err != nil {
		t.Fatal(err)
	}
	secret, err := priv.ECDH(pub)
	if err != nil {
		t.Fatal(err)
	}
	key, err := DeriveKey(secret)
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func envelopeJSON(t *testing.T, e envelope) []byte {
	t.Helper()
	raw, err := json.Marshal(e)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// codeIs fails the test unless err is a payload failure with the code want.
func codeIs(t *testing.T, err error, want Code) {
	t.Helper()
	if err == nil || CodeOf(err) != want {
		t.Fatalf("got %v, want %s", err, want)
	}
}
