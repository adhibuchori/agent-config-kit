// The switch: whether this service enforces the contract. PAYLOAD_MODE wins, then the committed
// payload.config.json (configMode, generated into registry.gen.go), then strict. off exists to bisect
// a transport problem on your own machine; production refuses it at startup, so a branch merged with
// the switch flipped fails to boot instead of serving plaintext.

package payload

import (
	"fmt"
	"strings"
)

type mode string

const (
	strict mode = "strict"
	off    mode = "off"
)

// resolveMode settles the mode from the environment's value and the committed one, and refuses a
// value that is neither strict nor off, and off in production.
func resolveMode(env, committed string, production bool) (mode, error) {
	raw, source := strings.TrimSpace(env), "PAYLOAD_MODE"
	if raw == "" {
		raw, source = strings.TrimSpace(committed), "payload.config.json encryption"
	}
	if raw == "" {
		raw = string(strict)
	}
	m := mode(strings.ToLower(raw))
	if m != strict && m != off {
		return "", fmt.Errorf("payload: %s must be %q or %q, not %q", source, strict, off, raw)
	}
	if m == off && production {
		return "", fmt.Errorf("payload: %s is %q, which production refuses", source, off)
	}
	return m, nil
}
