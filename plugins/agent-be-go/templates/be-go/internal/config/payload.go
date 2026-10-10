// The payload contract's variables (.claude/PAYLOAD-CONTRACT.md § Keys): read here, the only reader of
// the environment, and parsed by internal/payload's NewEdge. They hold secrets: never log them.

package config

import "log/slog"

// Payload is what the payload contract reads from the environment, as the variables hold it.
type Payload struct {
	Mode      string // PAYLOAD_MODE: strict or off; empty lets payload.config.json decide
	Key       string // PAYLOAD_KEY: kid:base64key, the key server callers share with this service
	KeyNext   string // PAYLOAD_KEY_NEXT: the next key, during a rotation
	ServerJWK string // PAYLOAD_SERVER_JWK: base64url JWK text of the P-256 key browsers and apps agree with
}

// LoadPayload reads the payload contract's variables. Each is optional here; NewEdge refuses a
// combination the service cannot run with, naming the variable.
func LoadPayload(lookup LookupFunc) Payload {
	r := reader{lookup: lookup}
	return Payload{
		Mode:      r.str("PAYLOAD_MODE", ""),
		Key:       r.str("PAYLOAD_KEY", ""),
		KeyNext:   r.str("PAYLOAD_KEY_NEXT", ""),
		ServerJWK: r.str("PAYLOAD_SERVER_JWK", ""),
	}
}

// LogValue keeps the keys out of a log line that names the whole value by mistake.
func (p Payload) LogValue() slog.Value {
	return slog.GroupValue(slog.String("mode", p.Mode), slog.Bool("key", p.Key != ""),
		slog.Bool("keyNext", p.KeyNext != ""), slog.Bool("serverJwk", p.ServerJWK != ""))
}
