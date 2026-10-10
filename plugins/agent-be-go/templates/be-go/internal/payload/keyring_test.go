// Tests for the key ring: blank slots, rotation, and refusals that name the variable, never the key.

package payload

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestKeyRingSkipsBlankSlotsAndSealsWithTheFirst(t *testing.T) {
	t.Parallel()
	if ring, err := newKeyRing(keySource{"PAYLOAD_KEY", ""}, keySource{"PAYLOAD_KEY_NEXT", "  "}); ring != nil || err != nil {
		t.Fatalf("blank sources: got %v, %v", ring, err)
	}
	ring, err := newKeyRing(
		keySource{"PAYLOAD_KEY", "k1:" + Encode(labelled("k1"))},
		keySource{"PAYLOAD_KEY_NEXT", " k2 :" + base64.StdEncoding.EncodeToString(labelled("k2"))},
	)
	if err != nil || ring.primary != "k1" {
		t.Fatalf("got %+v, %v", ring, err)
	}
	for _, kid := range []string{"k1", "k2"} {
		if _, err := ring.resolve(kid); err != nil {
			t.Errorf("%s: %v", kid, err)
		}
	}
	_, err = ring.resolve("k3")
	codeIs(t, err, KeyUnknown)
}

func TestKeyRingRefusesAMalformedValue(t *testing.T) {
	t.Parallel()
	key := Encode(labelled("k1"))
	for name, values := range map[string][]string{
		"no kid":        {key},
		"empty kid":     {":" + key},
		"reserved kid":  {"ecdh:" + key},
		"kid too odd":   {"k 1!:" + key},
		"not base64":    {"k1:*"},
		"16 bytes":      {"k1:" + Encode(make([]byte, 16))},
		"duplicate kid": {"k1:" + key, "k1:" + Encode(labelled("k2"))},
	} {
		sources := make([]keySource, 0, len(values))
		for i, v := range values {
			sources = append(sources, keySource{[]string{"PAYLOAD_KEY", "PAYLOAD_KEY_NEXT"}[i], v})
		}
		ring, err := newKeyRing(sources...)
		if err == nil || ring != nil || !strings.Contains(err.Error(), "PAYLOAD_KEY") || strings.Contains(err.Error(), key) {
			t.Errorf("%s: got %v, %v", name, ring, err)
		}
	}
}
