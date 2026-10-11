// Pre-shared keys for server callers, which never reach a browser or an app. One variable holds
// kid:base64key, because a key and the id naming it are one fact: split across two variables, one is
// rotated without the other. Rotation adds PAYLOAD_KEY_NEXT: deploy both sides with it, then swap,
// and no request falls into the gap. Only the first configured key seals; every one opens.

package payload

import (
	"fmt"
	"regexp"
	"strings"
)

// kidPattern is a key id: short and printable. A kid is public; it selects a key and is not one.
var kidPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,32}$`)

// keySource is one configured key: the variable it came from, for messages, and its value.
type keySource struct{ name, value string }

// keyRing is the keys a service opens with, and the one it seals with when nothing else decides.
type keyRing struct {
	primary string
	keys    map[string]Key
}

// newKeyRing builds a ring from the sources in priority order, skipping blank ones, so a rotation slot
// needs no branch. It is nil when every source is blank, and fails at startup on a malformed value or
// a kid two sources share.
func newKeyRing(sources ...keySource) (*keyRing, error) {
	var ring *keyRing
	for _, src := range sources {
		if strings.TrimSpace(src.value) == "" {
			continue
		}
		kid, key, err := parseKey(src)
		if err != nil {
			return nil, err
		}
		if ring == nil {
			ring = &keyRing{primary: kid, keys: map[string]Key{}}
		}
		if _, dup := ring.keys[kid]; dup {
			return nil, fmt.Errorf("payload: %s repeats the kid %q", src.name, kid)
		}
		ring.keys[kid] = key
	}
	return ring, nil
}

// parseKey reads kid:base64key. The message names the variable and never repeats the value.
func parseKey(src keySource) (string, Key, error) {
	kid, encoded, found := strings.Cut(src.value, ":")
	kid = strings.TrimSpace(kid)
	if !found || !kidPattern.MatchString(kid) || kid == ECDHKid {
		return "", Key{}, fmt.Errorf("payload: %s must be kid:base64key with a kid of 1 to 32 letters, "+
			"digits, '.', '_' or '-', other than %q", src.name, ECDHKid)
	}
	raw, err := Decode(encoded)
	if err != nil {
		return "", Key{}, fmt.Errorf("payload: %s holds a key that is not base64", src.name)
	}
	key, err := NewKey(raw)
	if err != nil {
		return "", Key{}, fmt.Errorf("payload: %s must decode to %d bytes, not %d", src.name, keySize, len(raw))
	}
	return kid, key, nil
}

// resolve is the key kid names, or KeyUnknown: mid-rotation, or a mismatched deployment.
func (r *keyRing) resolve(kid string) (Key, error) {
	key, ok := r.keys[kid]
	if !ok {
		return Key{}, fail(KeyUnknown, "no payload key has the kid %q", kid)
	}
	return key, nil
}
