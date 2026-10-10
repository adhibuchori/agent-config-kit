// The one writer of error responses: RFC 9457 bodies with the request ID.

package apperr

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"example.com/service/internal/logging"
)

// Problem is the RFC 9457 body of every error response.
type Problem struct {
	Type      string       `json:"type"`
	Title     string       `json:"title"`
	Status    int          `json:"status"`
	Code      string       `json:"code"`
	Detail    string       `json:"detail,omitempty"`
	RequestID string       `json:"requestId"`
	Fields    []FieldError `json:"fields,omitempty"`
}

// Write answers err as application/problem+json, and logs it with the same request ID. It is the
// only place an error becomes a response: a handler returns its error, and the router hands it here.
// An error without a registered code is answered as Internal; its message reaches the log only.
func Write(w http.ResponseWriter, r *http.Request, logger *slog.Logger, err error) {
	ctx := r.Context()
	requestID := logging.RequestID(ctx)
	e := As(err)
	if e == nil || e.Code.name == "" {
		e = Wrap(Internal, "", err)
	}
	status := e.Status()
	attrs := []slog.Attr{
		slog.String("requestId", requestID),
		slog.String("code", e.Code.name),
		slog.Int("status", status),
	}
	if e.internal != "" {
		attrs = append(attrs, slog.String("internal", e.internal))
	}
	level := slog.LevelInfo
	if status >= http.StatusInternalServerError {
		level = slog.LevelError
		attrs = append(attrs, slog.Any("error", err))
	}
	logger.LogAttrs(ctx, level, "request refused", attrs...)

	body := Problem{
		Type:      e.Code.Type(),
		Title:     e.Code.title,
		Status:    status,
		Code:      e.Code.name,
		Detail:    e.Detail,
		RequestID: requestID,
		Fields:    e.fields,
	}
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(status)
	if encErr := json.NewEncoder(w).Encode(body); encErr != nil {
		logger.LogAttrs(ctx, slog.LevelError, "problem body not written",
			slog.String("requestId", requestID), slog.Any("error", encErr))
	}
}
