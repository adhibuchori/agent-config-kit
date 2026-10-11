// The 404 and 405 answers as problems, instead of ServeMux's plain text.

package httpapi

import (
	"log/slog"
	"net/http"

	"example.com/service/internal/apperr"
)

// problemFallback answers what ServeMux would answer in plain text, a path no route takes (404) or a
// method the path does not take (405, with its Allow header), as a problem with a registered code.
// Everything else goes to the mux as usual.
func problemFallback(mux *http.ServeMux, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h, pattern := mux.Handler(r)
		if pattern != "" {
			mux.ServeHTTP(w, r)
			return
		}
		probe := &headerProbe{header: http.Header{}}
		h.ServeHTTP(probe, r)
		if probe.status == http.StatusMethodNotAllowed {
			w.Header().Set("Allow", probe.header.Get("Allow"))
			apperr.Write(w, r, logger, apperr.New(apperr.MethodNotAllowed, "This route does not take that method."))
			return
		}
		apperr.Write(w, r, logger, apperr.New(apperr.NotFound, "No route matches this path."))
	})
}

// headerProbe keeps the status and headers a handler writes and drops its body.
type headerProbe struct {
	header http.Header
	status int
}

func (p *headerProbe) Header() http.Header { return p.header }

func (p *headerProbe) Write(b []byte) (int, error) { return len(b), nil }

func (p *headerProbe) WriteHeader(status int) { p.status = status }
