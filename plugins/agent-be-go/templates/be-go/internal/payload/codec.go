// A JSON body into an envelope and back: the one place that decides the order of the checks.

package payload

import (
	"encoding/json"
	"time"
)

// KeyFor finds the key an envelope's kid names, or fails with KeyUnknown.
type KeyFor func(kid string) (Key, error)

// Seal puts a JSON body in an envelope under key, naming kid, bound to what aad builds for the new
// ts. The body is sealed byte for byte; one that is not JSON is refused, because the other side
// parses what it opens. Both sides of an exchange call it: a service for its answer, a client for its
// request.
func Seal(body []byte, key Key, kid string, aad AAD, now time.Time) ([]byte, error) {
	if !json.Valid(body) {
		return nil, fail(Malformed, "the body to seal is not JSON")
	}
	ts := now.UnixMilli()
	nonce, sealed := key.seal(body, aad(kid, ts))
	return json.Marshal(envelope{V: version, Alg: alg, Kid: kid, IV: Encode(nonce), CT: Encode(sealed), TS: ts})
}

// Open reads an envelope and returns the JSON it holds. The checks run cheapest first: the shape,
// then freshness (a replay costs a subtraction, not a cipher pass), then the key its kid names, then
// the tag over aad, then the JSON inside.
func Open(raw []byte, keyFor KeyFor, aad AAD, now time.Time) ([]byte, error) {
	e, err := parseEnvelope(raw)
	if err != nil {
		return nil, err
	}
	if !fresh(e.TS, now) {
		return nil, fail(Expired, "ts %d is more than %s from now", e.TS, MaxSkew)
	}
	key, err := keyFor(e.Kid)
	if err != nil {
		return nil, err
	}
	nonce, errNonce := Decode(e.IV)
	sealed, errSealed := Decode(e.CT)
	if errNonce != nil || errSealed != nil {
		return nil, fail(Rejected, "iv or ct is not base64url")
	}
	plain, err := key.open(nonce, sealed, aad(e.Kid, e.TS))
	if err != nil {
		return nil, err
	}
	if !json.Valid(plain) {
		return nil, fail(Malformed, "the opened body is not JSON")
	}
	return plain, nil
}
