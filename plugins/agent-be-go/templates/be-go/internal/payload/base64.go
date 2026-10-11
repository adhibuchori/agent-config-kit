// Bytes on the wire: unpadded base64url out; base64url or standard base64 in, as every copy reads it.

package payload

import (
	"encoding/base64"
	"strings"
)

var (
	// unspaced drops the ASCII whitespace a pasted value may carry, as a browser's atob does.
	unspaced = strings.NewReplacer(" ", "", "\t", "", "\n", "", "\f", "", "\r", "")
	// standard turns the URL alphabet into the standard one.
	standard = strings.NewReplacer("-", "+", "_", "/")
)

// Encode is unpadded base64url, the form every binary field of an envelope and x-payload-epk take.
func Encode(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// Decode reads base64url, and standard base64 as a person pastes it: padded or not, with whitespace.
// It accepts exactly what the TypeScript copy's atob accepts, so a value one copy reads the others do.
func Decode(s string) ([]byte, error) {
	s = standard.Replace(unspaced.Replace(s))
	if len(s)%4 == 0 {
		s = strings.TrimSuffix(strings.TrimSuffix(s, "="), "=")
	}
	return base64.RawStdEncoding.DecodeString(s)
}
