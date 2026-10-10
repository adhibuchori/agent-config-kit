// The HTTP server with every timeout set, and the export of the embedded spec.

package httpapi

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"

	"example.com/service/internal/config"
)

// NewServer returns the HTTP server with every timeout set: a zero timeout means none, and a client
// that sends its headers slowly would hold a connection forever.
func NewServer(cfg config.HTTP, handler http.Handler, logger *slog.Logger) *http.Server {
	return &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadHeaderTimeout: cfg.ReadHeaderTimeout,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
		MaxHeaderBytes:    64 << 10,
		ErrorLog:          slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
}

// IndentSpec turns the embedded spec (GetSpecJSON) into the api/openapi.json clients generate from.
func IndentSpec(raw []byte) ([]byte, error) {
	var out bytes.Buffer
	if err := json.Indent(&out, raw, "", "  "); err != nil {
		return nil, fmt.Errorf("httpapi: indent the spec: %w", err)
	}
	out.WriteByte('\n')
	return out.Bytes(), nil
}
