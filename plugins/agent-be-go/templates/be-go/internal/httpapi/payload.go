// The payload contract around the routes (.claude/PAYLOAD-CONTRACT.md): a sealed request body is opened
// before the validator reads it, and the answer is sealed after the handler wrote it, so no handler,
// service or schema ever sees an envelope.

package httpapi

import (
	"bytes"
	"errors"
	"io"
	"log/slog"
	"net/http"

	"example.com/service/internal/apperr"
	"example.com/service/internal/payload"
)

// sealedVary keys a shared cache on the request headers that chose a sealed answer's key, so it never
// serves one caller's envelope to another.
const sealedVary = payload.EPKHeader + ", " + payload.KIDHeader

// envelopeCodes answers each payload failure with the registered code of the same name.
var envelopeCodes = map[payload.Code]apperr.Code{
	payload.Required:   apperr.EnvelopeRequired,
	payload.Malformed:  apperr.EnvelopeMalformed,
	payload.Expired:    apperr.EnvelopeExpired,
	payload.KeyUnknown: apperr.EnvelopeKeyUnknown,
	payload.Rejected:   apperr.EnvelopeRejected,
}

// sealBodies holds the contract for the endpoints given (payload.Registry() in production). A route
// they do not list passes through, because the router answers it with a 404 and there is no body to
// protect; so does every route while the mode is off. NewRouter places it between the validator and
// the body limit, so the limit applies to the envelope and the validator reads plaintext:
//
//	chain = validate(chain)
//	chain = sealBodies(chain, edge, payload.Registry(), logger)
//	chain = limitBody(chain, maxBody)
//
// A refusal leaves as a plaintext problem with its ENVELOPE_* code, never the internal message.
func sealBodies(next http.Handler, edge *payload.Edge, endpoints []payload.Endpoint, logger *slog.Logger) http.Handler {
	return sealer{next: next, edge: edge, routes: matcher(endpoints), logger: logger}
}

type sealer struct {
	next   http.Handler
	edge   *payload.Edge
	routes *http.ServeMux
	logger *slog.Logger
}

func (s sealer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ep, ok := match(s.routes, r)
	opens := ok && ep.Policy.SealsRequest() && r.Method != http.MethodGet && r.Method != http.MethodHead
	seals := ok && ep.Policy.SealsResponse()
	if s.edge.Off() || (!opens && !seals) {
		s.next.ServeHTTP(w, r)
		return
	}
	x, err := s.edge.Exchange(r.Header.Get(payload.EPKHeader), r.Header.Get(payload.KIDHeader))
	if err != nil {
		apperr.Write(w, r, s.logger, envelopeRefusal(err))
		return
	}
	if opens {
		opened, err := openRequest(r, ep, x)
		if err != nil {
			apperr.Write(w, r, s.logger, err)
			return
		}
		r = opened
	}
	if !seals {
		s.next.ServeHTTP(w, r)
		return
	}
	held := &sealingWriter{header: http.Header{}}
	s.next.ServeHTTP(held, r)
	held.send(w, r, s.logger, func(body []byte, status int) ([]byte, error) {
		return x.SealResponse(body, status, ep.Pattern)
	})
}

// route is the matcher's handler for one endpoint. It is found, never served.
type route struct{ payload.Endpoint }

func (route) ServeHTTP(http.ResponseWriter, *http.Request) {}

// matcher is a private ServeMux holding each endpoint's spec path, so a request matches the endpoint
// the real router sends it to, by the router's own precedence.
func matcher(endpoints []payload.Endpoint) *http.ServeMux {
	mux := http.NewServeMux()
	for _, ep := range endpoints {
		mux.Handle(ep.Method+" "+ep.Route, route{ep})
	}
	return mux
}

// match is the endpoint r is for. A HEAD only a GET route takes, a redirect to a cleaned path, a 404
// and a 405 are none.
func match(routes *http.ServeMux, r *http.Request) (payload.Endpoint, bool) {
	h, _ := routes.Handler(r)
	rt, ok := h.(route)
	return rt.Endpoint, ok && rt.Method == r.Method
}

// openRequest reads the body once and hands on a request that holds the opened JSON. A body over the
// limit is BODY_TOO_LARGE, and one the client stopped sending is MALFORMED_BODY.
func openRequest(r *http.Request, ep payload.Endpoint, x payload.Exchange) (*http.Request, error) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
			return nil, bodyTooLarge(err)
		}
		return nil, apperr.Wrap(apperr.MalformedBody, "The request body could not be read.", err)
	}
	plain, err := x.OpenRequest(body, r.Header.Get("Content-Type"), ep.Method, ep.Pattern)
	if err != nil {
		return nil, envelopeRefusal(err)
	}
	opened := r.Clone(r.Context())
	opened.Body = io.NopCloser(bytes.NewReader(plain))
	opened.ContentLength = int64(len(plain))
	opened.Header.Del("Content-Length")
	if len(plain) > 0 {
		opened.Header.Set("Content-Type", "application/json")
	}
	return opened, nil
}

// envelopeRefusal is a payload failure as the client receives it: the code, the message for the log.
func envelopeRefusal(err error) *apperr.Error {
	return apperr.New(envelopeCodes[payload.CodeOf(err)], "").WithInternal("%v", err)
}
