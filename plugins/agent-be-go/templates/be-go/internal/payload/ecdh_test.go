// Tests for key agreement: the server key's import, the client point's checks, and both sides
// deriving one key.

package payload

import (
	"bytes"
	"encoding/json"
	"errors"
	"testing"
)

func TestImportServerKeyServesItsOwnUncompressedPoint(t *testing.T) {
	t.Parallel()
	priv := p256(t, "ecdh server")
	server, err := importServerKey(jwkOf(t, priv, priv.PublicKey()))
	if err != nil {
		t.Fatal(err)
	}
	point, err := Decode(server.publicKey())
	if err != nil || len(point) != 65 || point[0] != 4 || !bytes.Equal(point, priv.PublicKey().Bytes()) {
		t.Fatalf("public key %x, %v", point, err)
	}
}

func TestImportServerKeyRefusesWhatIsNotItsOwnKeyPair(t *testing.T) {
	t.Parallel()
	priv := p256(t, "ecdh server")
	jwk := func(edit func(map[string]string)) string {
		point := priv.PublicKey().Bytes()
		m := map[string]string{"kty": "EC", "crv": "P-256", "d": Encode(priv.Bytes()), "x": Encode(point[1:33]), "y": Encode(point[33:])}
		edit(m)
		text, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		return Encode(text)
	}
	for name, encoded := range map[string]string{
		"not base64":        "*",
		"not JSON":          Encode([]byte("kty=EC")),
		"no d":              jwk(func(m map[string]string) { delete(m, "d") }),
		"d not base64":      jwk(func(m map[string]string) { m["d"] = "*" }),
		"another kty":       jwk(func(m map[string]string) { m["kty"] = "OKP" }),
		"another curve":     jwk(func(m map[string]string) { m["crv"] = "P-384" }),
		"d out of range":    jwk(func(m map[string]string) { m["d"] = Encode(make([]byte, 32)) }),
		"another key's x y": jwkOf(t, priv, p256(t, "someone else").PublicKey()),
	} {
		if _, err := importServerKey(encoded); !errors.Is(err, errServerJWK) {
			t.Errorf("%s: got %v", name, err)
		}
	}
}

func TestSecretTakesOnlyAnUncompressedP256Point(t *testing.T) {
	t.Parallel()
	priv := p256(t, "ecdh server")
	server := &serverKey{priv: priv}
	client := p256(t, "ecdh client")
	want, err := client.ECDH(priv.PublicKey())
	if err != nil {
		t.Fatal(err)
	}
	if got, err := server.secret(Encode(client.PublicKey().Bytes())); err != nil || !bytes.Equal(got, want) {
		t.Fatalf("secret %x, %v", got, err)
	}
	point := client.PublicKey().Bytes()
	offCurve := bytes.Clone(point)
	offCurve[64] ^= 1
	compressed := append([]byte{2 + point[64]&1}, point[1:33]...)
	for name, epk := range map[string]string{
		"not base64": "*", "infinity": Encode([]byte{0}), "64 bytes": Encode(point[1:]),
		"compressed": Encode(compressed), "off the curve": Encode(offCurve),
	} {
		_, err := server.secret(epk)
		codeIs(t, err, Malformed)
		if _, err := server.agree(epk); CodeOf(err) != Malformed || err == nil {
			t.Errorf("%s: agree accepted it", name)
		}
	}
}

func TestBothSidesDeriveOneKey(t *testing.T) {
	t.Parallel()
	priv := p256(t, "ecdh server")
	server := &serverKey{priv: priv}
	client := p256(t, "ecdh client")
	fromServer, err := server.agree(Encode(client.PublicKey().Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	sealed, err := Seal([]byte(`{"ok":true}`), clientKey(t, client, server.publicKey()), ECDHKid, RequestAAD("GET", "/api/x"), at)
	if err != nil {
		t.Fatal(err)
	}
	if plain, err := Open(sealed, constKey(fromServer), RequestAAD("GET", "/api/x"), at); err != nil || string(plain) != `{"ok":true}` {
		t.Fatalf("got %q, %v", plain, err)
	}
}
