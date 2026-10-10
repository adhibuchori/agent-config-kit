// Tests this copy against the shared known answers, scripts/check/payload-vectors.json: the AAD
// strings byte for byte, every ciphertext opened, every replay refused, and the key agreement derived
// from both sides. The file is identical in every repo that speaks the format; never regenerate it to
// make this test pass.

package payload

import (
	"bytes"
	"crypto/ecdh"
	"encoding/json"
	"os"
	"reflect"
	"testing"
	"time"
)

type vector struct {
	Name, Kind, Method, Pattern, Kid, AAD, IV, CT string
	Status                                        int
	TS                                            int64
	Plaintext                                     json.RawMessage
}

type agreement struct {
	Info, ServerJWK, ServerPublic, ClientPrivate, ClientPublic, SharedBytes, SessionBytes string
	Vector                                                                  vector
}

type vectorFile struct {
	TestBytes    string
	Vectors      []vector
	Rejects      []struct{ Name, Vector, AAD string }
	Agreements   []agreement
	PointRejects []struct{ Name, Point, Code string }
}

func readVectors(t *testing.T) vectorFile {
	t.Helper()
	raw, err := os.ReadFile("../../scripts/check/payload-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var f vectorFile
	if err := json.Unmarshal(raw, &f); err != nil {
		t.Fatal(err)
	}
	if len(f.Vectors) == 0 || len(f.Rejects) == 0 || len(f.Agreements) == 0 || len(f.PointRejects) == 0 {
		t.Fatal("the vectors file lacks vectors, rejects, agreements or pointRejects: the test would pass having read nothing")
	}
	return f
}

func (v vector) aad() AAD {
	if v.Kind == "response" {
		return ResponseAAD(v.Status, v.Pattern)
	}
	return RequestAAD(v.Method, v.Pattern)
}

// openVector checks v's AAD string and opens it under key, returning the plaintext.
func openVector(t *testing.T, v vector, key Key, aad AAD) []byte {
	t.Helper()
	if got := string(v.aad()(v.Kid, v.TS)); got != v.AAD {
		t.Errorf("%s: AAD %q, the vectors say %q", v.Name, got, v.AAD)
	}
	raw := envelopeJSON(t, envelope{V: 1, Alg: alg, Kid: v.Kid, IV: v.IV, CT: v.CT, TS: v.TS})
	plain, err := Open(raw, constKey(key), aad, time.UnixMilli(v.TS))
	if err != nil {
		t.Errorf("%s: %v", v.Name, err)
	}
	return plain
}

func sameJSON(t *testing.T, name string, got, want []byte) {
	t.Helper()
	var g, w any
	if json.Unmarshal(got, &g) != nil || json.Unmarshal(want, &w) != nil || !reflect.DeepEqual(g, w) {
		t.Errorf("%s: opened %s, want %s", name, got, want)
	}
}

func TestVectorsOpenAndRejects(t *testing.T) {
	t.Parallel()
	f := readVectors(t)
	raw, err := Decode(f.TestBytes)
	if err != nil {
		t.Fatal(err)
	}
	key, err := NewKey(raw)
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]vector{}
	for _, v := range f.Vectors {
		byName[v.Name] = v
		sameJSON(t, v.Name, openVector(t, v, key, v.aad()), v.Plaintext)
	}
	for _, r := range f.Rejects {
		v := byName[r.Vector]
		sealed := envelopeJSON(t, envelope{V: 1, Alg: alg, Kid: v.Kid, IV: v.IV, CT: v.CT, TS: v.TS})
		_, err := Open(sealed, constKey(key), func(string, int64) []byte { return []byte(r.AAD) }, time.UnixMilli(v.TS))
		if CodeOf(err) != Rejected || err == nil {
			t.Errorf("reject %q: got %v, want %s", r.Name, err, Rejected)
		}
	}
}

func TestVectorsAgreeFromBothSides(t *testing.T) {
	t.Parallel()
	for _, a := range readVectors(t).Agreements {
		if a.Info != hkdfInfo {
			t.Errorf("HKDF info %q, the vectors say %q", hkdfInfo, a.Info)
		}
		server := vectorServer(t, a)
		fromServer, err := server.secret(a.ClientPublic)
		if err != nil || Encode(fromServer) != a.SharedBytes || Encode(clientSecret(t, a)) != a.SharedBytes {
			t.Fatalf("secret: %v", err)
		}
		derived, err := deriveBytes(fromServer)
		if err != nil || Encode(derived) != a.SessionBytes {
			t.Fatalf("key %s, the vectors say %s (%v)", Encode(derived), a.SessionBytes, err)
		}
		key, err := DeriveKey(clientSecret(t, a))
		if err != nil {
			t.Fatal(err)
		}
		sameJSON(t, "agreement", openVector(t, a.Vector, key, a.Vector.aad()), a.Vector.Plaintext)
	}
}

func TestVectorsPointRejects(t *testing.T) {
	t.Parallel()
	f := readVectors(t)
	server := vectorServer(t, f.Agreements[0])
	for _, p := range f.PointRejects {
		if _, err := server.secret(p.Point); string(CodeOf(err)) != p.Code || err == nil {
			t.Errorf("point %q: got %v, want %s", p.Name, err, p.Code)
		}
	}
}

// vectorServer is the agreement's server key, which must serve the agreement's public point.
func vectorServer(t *testing.T, a agreement) *serverKey {
	t.Helper()
	server, err := importServerKey(a.ServerJWK)
	if err != nil || server.publicKey() != a.ServerPublic {
		t.Fatalf("server key: %v", err)
	}
	return server
}

// clientSecret is the secret from the client's side: its private scalar and the server's point.
func clientSecret(t *testing.T, a agreement) []byte {
	t.Helper()
	d, errD := Decode(a.ClientPrivate)
	point, errP := Decode(a.ServerPublic)
	priv, errK := ecdh.P256().NewPrivateKey(d)
	if errD != nil || errP != nil || errK != nil {
		t.Fatal("the agreement's client key or server point is unreadable")
	}
	pub, err := ecdh.P256().NewPublicKey(point)
	if err != nil {
		t.Fatal(err)
	}
	secret, err := priv.ECDH(pub)
	if err != nil || !bytes.Equal(priv.PublicKey().Bytes(), mustDecode(t, a.ClientPublic)) {
		t.Fatalf("client side: %v", err)
	}
	return secret
}

func mustDecode(t *testing.T, s string) []byte {
	t.Helper()
	b, err := Decode(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}
