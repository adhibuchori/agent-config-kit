// Package payload is the payload contract's core (.claude/PAYLOAD-CONTRACT.md): the envelope and its
// cipher, key agreement with browsers and apps, key rings for server callers, the strict/off switch
// and the endpoint registry generated from the spec. It never sees HTTP. internal/httpapi wraps it
// around the router, and only that package and cmd/ import it (boundary_test.go). Every constant here
// has a twin in each other copy of the contract; scripts/check/payload-vectors.json holds them to it.
package payload

import (
	"encoding/json"
	"strconv"
	"strings"
	"time"
)

// The wire, the same in every copy of the contract.
const (
	// MediaType is a sealed body's Content-Type. It is not application/json, so a proxy, a log
	// filter or a middleware tells an envelope from plaintext without parsing it.
	MediaType = "application/vnd.payload-envelope+json"
	// EPKHeader carries a client's ephemeral P-256 public key on every request, body or not: a GET
	// has no envelope, and the answer still needs the key.
	EPKHeader = "x-payload-epk"
	// KIDHeader names the pre-shared key a server caller holds, so even a bodiless request is
	// answered under the right key.
	KIDHeader = "x-payload-kid"
	// ECDHKid is the kid of an envelope sealed under an agreed key; never a pre-shared key's id.
	ECDHKid = "ecdh"
	// MaxSkew is how far a sender's clock may be from this one, either way, before an envelope is
	// refused. It is not replay protection on its own; that would need a nonce store.
	MaxSkew = 120 * time.Second

	version = 1
	alg     = "A256GCM"
	// maxSafe is the largest integer a JavaScript peer reads exactly: the bound of ts.
	maxSafe = 1<<53 - 1
)

// AAD builds the additional authenticated data of one envelope from its kid and ts. It is never sent.
type AAD func(kid string, ts int64) []byte

// RequestAAD binds a request envelope to its method and registry pattern (/api/notes/:id, not the
// URL): 1.<METHOD>.<pattern>.<kid>.<ts>.
func RequestAAD(method, pattern string) AAD {
	return func(kid string, ts int64) []byte {
		return aad(strings.ToUpper(method), pattern, kid, ts)
	}
}

// ResponseAAD binds a response envelope to its status and pattern, so a 200's body cannot be replayed
// as a 403's: 1.<status>.<pattern>.<kid>.<ts>.
func ResponseAAD(status int, pattern string) AAD {
	return func(kid string, ts int64) []byte {
		return aad(strconv.Itoa(status), pattern, kid, ts)
	}
}

func aad(head, pattern, kid string, ts int64) []byte {
	return []byte(strconv.Itoa(version) + "." + head + "." + pattern + "." + kid + "." + strconv.FormatInt(ts, 10))
}

// envelope is a sealed body as it travels: {v, alg, kid, iv, ct, ts}, ts in epoch milliseconds.
type envelope struct {
	V   int    `json:"v"`
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	IV  string `json:"iv"`
	CT  string `json:"ct"`
	TS  int64  `json:"ts"`
}

// parseEnvelope reads an envelope by its exact member names (Go's decoder would also take "V" or
// "KID") and refuses anything else as not sealed: an unknown version or algorithm, a missing or null
// member, a ts that is not a whole number a JavaScript peer could have written.
func parseEnvelope(raw []byte) (envelope, error) {
	var members map[string]json.RawMessage
	var e envelope
	ok := json.Unmarshal(raw, &members) == nil &&
		member(members, "v", &e.V) && e.V == version &&
		member(members, "alg", &e.Alg) && e.Alg == alg &&
		member(members, "kid", &e.Kid) && member(members, "iv", &e.IV) && member(members, "ct", &e.CT) &&
		member(members, "ts", &e.TS) && e.TS >= -maxSafe && e.TS <= maxSafe
	if !ok {
		return envelope{}, fail(Required, "the body is not a version %d payload envelope", version)
	}
	return e, nil
}

// member decodes members[name] into into; false when it is missing, null or of another type.
func member[T any](members map[string]json.RawMessage, name string, into *T) bool {
	raw, ok := members[name]
	return ok && string(raw) != "null" && json.Unmarshal(raw, into) == nil
}

// fresh says whether ts sits within MaxSkew of now, either way. A future ts is refused too, or a
// sender could post-date an envelope for as long as it liked.
func fresh(ts int64, now time.Time) bool {
	d, limit := now.UnixMilli()-ts, MaxSkew.Milliseconds()
	return d >= -limit && d <= limit
}
