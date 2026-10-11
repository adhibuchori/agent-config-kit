// Package logging builds the process logger and carries the request ID through a context.
package logging

import (
	"context"
	"io"
	"log/slog"
)

type requestIDKey struct{}

// New returns a JSON logger at the given level: JSON is what a log pipeline parses.
func New(w io.Writer, level slog.Level) *slog.Logger {
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{Level: level}))
}

// WithRequestID returns a context that carries id.
func WithRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, requestIDKey{}, id)
}

// RequestID returns the request ID ctx carries, or "" outside a request.
func RequestID(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey{}).(string)
	return id
}
