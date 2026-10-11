// Key agreement for clients that can hold no shared secret: a browser, an installed app. The service
// keeps one long-lived P-256 key pair; a client mints an ephemeral one and sends its public half in
// x-payload-epk on every request; both derive the same AES-256 key, which never travels, and the
// service stores nothing per client. This buys integrity and resistance to passive capture, not
// secrecy from the person running the client (.claude/PAYLOAD-CONTRACT.md § Threat model).

package payload

import (
	"bytes"
	"cmp"
	"crypto/ecdh"
	"crypto/hkdf"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"slices"
)

// hkdfInfo separates this key schedule from any other derived from the same secret. The version is
// in the label, so a v2 schedule cannot collide with it; an app reuses the browser label because it
// speaks the same wire format.
const hkdfInfo = "payload-envelope/v1/browser"

var errServerJWK = errors.New("payload: PAYLOAD_SERVER_JWK must be base64url JWK text of a P-256 " +
	"private key whose x and y are its own public key")

// serverKey is the service's long-lived key pair for key agreement.
type serverKey struct{ priv *ecdh.PrivateKey }

// importServerKey reads PAYLOAD_SERVER_JWK: base64url of the UTF-8 JWK text {kty, crv, d, x, y}.
// x and y must be d's own public key, so the key the handshake serves cannot drift from the one that
// agrees. The message never repeats the value.
func importServerKey(encoded string) (*serverKey, error) {
	text, err := Decode(encoded)
	var jwk map[string]json.RawMessage
	if err != nil || json.Unmarshal(text, &jwk) != nil {
		return nil, errServerJWK
	}
	var kty, crv string
	parts, ok := jwkBytes(jwk, "d", "x", "y")
	if !ok || !member(jwk, "kty", &kty) || kty != "EC" || !member(jwk, "crv", &crv) || crv != "P-256" {
		return nil, errServerJWK
	}
	priv, err := ecdh.P256().NewPrivateKey(parts[0])
	if err != nil || !bytes.Equal(priv.PublicKey().Bytes(), slices.Concat([]byte{4}, parts[1], parts[2])) {
		return nil, errServerJWK
	}
	return &serverKey{priv: priv}, nil
}

// jwkBytes decodes the named JWK members in order; false when one is missing or not base64url.
func jwkBytes(jwk map[string]json.RawMessage, names ...string) ([][]byte, bool) {
	out := make([][]byte, 0, len(names))
	for _, name := range names {
		var s string
		if !member(jwk, name, &s) {
			return nil, false
		}
		b, err := Decode(s)
		if err != nil {
			return nil, false
		}
		out = append(out, b)
	}
	return out, true
}

// publicKey is the uncompressed point 04||X||Y as base64url: what the handshake serves.
func (s *serverKey) publicKey() string { return Encode(s.priv.PublicKey().Bytes()) }

// secret is the ECDH x-coordinate shared with the client whose x-payload-epk is epk. Anything but an
// uncompressed P-256 point is Malformed: crypto/ecdh refuses compressed points, the point at infinity
// and points off the curve, which is what defeats an invalid-curve attack.
func (s *serverKey) secret(epk string) ([]byte, error) {
	raw, err := Decode(epk)
	var pub *ecdh.PublicKey
	if err == nil {
		pub, err = ecdh.P256().NewPublicKey(raw)
	}
	if err != nil {
		return nil, fail(Malformed, "x-payload-epk is not an uncompressed P-256 point")
	}
	// Two P-256 keys always agree; the error is for keys on two different curves.
	return s.priv.ECDH(pub)
}

// agree is the session key shared with the client whose public key is epk.
func (s *serverKey) agree(epk string) (Key, error) {
	secret, err := s.secret(epk)
	if err != nil {
		return Key{}, err
	}
	return DeriveKey(secret)
}

// DeriveKey turns an ECDH shared secret (the 32-byte x-coordinate) into the session key: HKDF-SHA-256
// with an empty salt and the contract's label as info, 32 bytes out. A client calls it with the
// secret its own private key and the handshake's public key give.
func DeriveKey(secret []byte) (Key, error) {
	raw, err := deriveBytes(secret)
	// HKDF fails only past 255 hash lengths of output; NewKey would then refuse the nil it returned.
	key, keyErr := NewKey(raw)
	return key, cmp.Or(err, keyErr)
}

func deriveBytes(secret []byte) ([]byte, error) {
	return hkdf.Key(sha256.New, secret, nil, hkdfInfo, keySize)
}
