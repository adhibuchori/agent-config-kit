// The middleware around the routes: request ID, access log, panic recovery, body limit.

package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"time"
	"uuid"

	"example.com/service/internal/apperr"
	"example.com/service/internal/logging"
)

// HeaderRequestID carries the request ID on every response; every problem body and log line of
// the request carries the same value.
const HeaderRequestID = "X-Request-Id"

// requestID gives every request a new ID, in its context and on the response. A client's own
// X-Request-Id is not trusted: logs are searched by this value.
func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := uuid.NewV7().String()
		w.Header().Set(HeaderRequestID, id)
		next.ServeHTTP(w, r.WithContext(logging.WithRequestID(r.Context(), id)))
	})
}

type statusRecorder struct {
	http.ResponseWriter

	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// accessLog writes one line per request: the matched route pattern, never the raw path.
func accessLog(next http.Handler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		logger.LogAttrs(r.Context(), slog.LevelInfo, "request",
			slog.String("requestId", logging.RequestID(r.Context())),
			slog.String("method", r.Method),
			slog.String("pattern", r.Pattern),
			slog.Int("status", rec.status),
			slog.Duration("duration", time.Since(start)))
	})
}

var errPanic = errors.New("a handler panicked")

// recoverer turns a panic into an INTERNAL problem instead of a dropped connection. An aborted
// handler (http.ErrAbortHandler) is let through: net/http expects to see it.
func recoverer(next http.Handler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			v := recover()
			if v == nil {
				return
			}
			if v == http.ErrAbortHandler { //nolint:errorlint // recover returns the value that was thrown, never a wrapped error.
				panic(v)
			}
			logger.LogAttrs(r.Context(), slog.LevelError, "panic",
				slog.String("requestId", logging.RequestID(r.Context())), slog.Any("value", v))
			apperr.Write(w, r, logger, errPanic)
		}()
		next.ServeHTTP(w, r)
	})
}

// limitBody caps every request body before anything reads it.
func limitBody(next http.Handler, maxBytes int64) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		next.ServeHTTP(w, r)
	})
}
