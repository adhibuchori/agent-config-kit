// The contract at this service's edge: the key one exchange uses, opening what a caller sealed and
// sealing what this service answers. internal/httpapi asks it once per request on a registered route.

package payload

import (
	"errors"
	"mime"
	"strings"
	"time"
)

// Settings is what NewEdge reads, as internal/config read it from the environment. Never log it.
type Settings struct {
	Mode       string           // PAYLOAD_MODE: strict or off; empty lets payload.config.json decide
	Production bool             // APP_ENV=production, where off is refused
	ServerJWK  string           // PAYLOAD_SERVER_JWK: browsers and apps agree with it; empty if none calls
	Key        string           // PAYLOAD_KEY: kid:base64key for server callers; empty when none calls
	KeyNext    string           // PAYLOAD_KEY_NEXT: the next key during a rotation
	Clock      func() time.Time // nil means time.Now; a test passes a fixed clock
}

// Edge holds the contract for one service. Build it once, at startup, with NewEdge.
type Edge struct {
	mode   mode
	server *serverKey
	ring   *keyRing
	clock  func() time.Time
}

// NewEdge settles the mode and loads the keys. It fails, naming the variable and never its value, on
// a malformed key, on off in production, and on strict with no key at all, which would refuse every
// sealed request.
func NewEdge(s Settings) (*Edge, error) {
	m, err := resolveMode(s.Mode, configMode, s.Production)
	if err != nil {
		return nil, err
	}
	e := &Edge{mode: m, clock: s.Clock}
	if e.clock == nil {
		e.clock = time.Now
	}
	if strings.TrimSpace(s.ServerJWK) != "" {
		if e.server, err = importServerKey(s.ServerJWK); err != nil {
			return nil, err
		}
	}
	e.ring, err = newKeyRing(keySource{"PAYLOAD_KEY", s.Key}, keySource{"PAYLOAD_KEY_NEXT", s.KeyNext})
	if err != nil {
		return nil, err
	}
	if m == strict && e.server == nil && e.ring == nil {
		return nil, errors.New("payload: strict needs PAYLOAD_SERVER_JWK (browsers and apps), " +
			"PAYLOAD_KEY (server callers) or both")
	}
	return e, nil
}

// Off says whether the contract is switched off; every route then passes through.
func (e *Edge) Off() bool { return e.mode == off }

// Handshake is the answer of GET /api/payload/handshake: the public key a client agrees its session
// key with (empty when this service agrees none) and the mode. A client treats anything but off as
// strict. Serve it with Cache-Control: no-store.
type Handshake struct {
	PublicKey string `json:"publicKey"`
	Mode      string `json:"mode"`
}

// Handshake answers the handshake.
func (e *Edge) Handshake() Handshake {
	h := Handshake{Mode: string(e.mode)}
	if e.server != nil {
		h.PublicKey = e.server.publicKey()
	}
	return h
}

// Exchange is the key one request and its answer use, and the kid the answer carries.
type Exchange struct {
	keyFor  KeyFor
	sealKey Key
	kid     string
	clock   func() time.Time
}

// Exchange picks the key for one request from its headers. With x-payload-epk it is the key agreed
// with that client, answered under kid ecdh; without, the key ring's, answered under x-payload-kid or
// the primary key; with neither, the request is refused as Required.
func (e *Edge) Exchange(epk, kid string) (Exchange, error) {
	if epk != "" {
		if e.server == nil {
			return Exchange{}, fail(KeyUnknown, "this service agrees no keys, and the request sent %s", EPKHeader)
		}
		key, err := e.server.agree(epk)
		if err != nil {
			return Exchange{}, err
		}
		agreed := func(string) (Key, error) { return key, nil }
		return Exchange{keyFor: agreed, sealKey: key, kid: ECDHKid, clock: e.clock}, nil
	}
	if e.ring == nil {
		return Exchange{}, fail(Required, "a sealed route needs the %s header", EPKHeader)
	}
	if kid == "" {
		kid = e.ring.primary
	}
	key, err := e.ring.resolve(kid)
	if err != nil {
		return Exchange{}, err
	}
	return Exchange{keyFor: e.ring.resolve, sealKey: key, kid: kid, clock: e.clock}, nil
}

// OpenRequest opens a request body sealed for method and pattern. An empty body stays empty (a POST
// may carry none); a body of another media type than MediaType is refused as Required.
func (x Exchange) OpenRequest(body []byte, contentType, method, pattern string) ([]byte, error) {
	if len(body) == 0 {
		return nil, nil
	}
	if media, _, err := mime.ParseMediaType(contentType); err != nil || media != MediaType {
		return nil, fail(Required, "%s %s takes a sealed body, not %q", method, pattern, contentType)
	}
	return Open(body, x.keyFor, RequestAAD(method, pattern), x.clock())
}

// SealResponse seals an answer for the status and pattern it goes out with.
func (x Exchange) SealResponse(body []byte, status int, pattern string) ([]byte, error) {
	return Seal(body, x.sealKey, x.kid, ResponseAAD(status, pattern), x.clock())
}
