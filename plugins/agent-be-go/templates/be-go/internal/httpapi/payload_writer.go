// The writer that holds an answer on a sealed route until it is whole, then seals or refuses it. It has
// no Flush and no Unwrap on purpose: nothing reaches the client unsealed. A stream belongs on a
// request-only route.

package httpapi

import (
	"bytes"
	"cmp"
	"log/slog"
	"maps"
	"net/http"

	"example.com/service/internal/apperr"
	"example.com/service/internal/logging"
	"example.com/service/internal/payload"
)

// sealingWriter holds the status, headers and body a handler writes.
type sealingWriter struct {
	header http.Header
	status int
	body   bytes.Buffer
}

// Header is the header the handler sets; it reaches the client only with a sealed answer.
func (s *sealingWriter) Header() http.Header { return s.header }

// WriteHeader keeps the first status, as net/http does.
func (s *sealingWriter) WriteHeader(status int) {
	if s.status == 0 {
		s.status = status
	}
}

// Write holds the body. A body written before any status is a 200's, as net/http answers it.
func (s *sealingWriter) Write(b []byte) (int, error) {
	s.WriteHeader(http.StatusOK)
	return s.body.Write(b)
}

// send answers w. A body is sealed for its status, with the envelope's media type and Vary; a 204, a
// 304 and an empty body go out as they are; a body that cannot be sealed, because it is not JSON,
// becomes a plaintext 500 ENVELOPE_MALFORMED and is never sent.
func (s *sealingWriter) send(w http.ResponseWriter, r *http.Request, logger *slog.Logger,
	seal func(body []byte, status int) ([]byte, error),
) {
	status := cmp.Or(s.status, http.StatusOK)
	body := s.body.Bytes()
	if status != http.StatusNoContent && status != http.StatusNotModified && len(body) > 0 {
		sealed, err := seal(body, status)
		if err != nil {
			apperr.Write(w, r, logger, envelopeRefusal(err).WithStatus(http.StatusInternalServerError))
			return
		}
		body = sealed
		s.header.Set("Content-Type", payload.MediaType)
		s.header.Add("Vary", sealedVary)
		s.header.Del("Content-Length")
	}
	maps.Copy(w.Header(), s.header)
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		logger.LogAttrs(r.Context(), slog.LevelError, "answer not written",
			slog.String("requestId", logging.RequestID(r.Context())), slog.Any("error", err))
	}
}
