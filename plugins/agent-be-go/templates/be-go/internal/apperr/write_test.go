// Tests for the problem writer: codes, statuses, the request ID, and no internal detail.

package apperr_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"example.com/service/internal/apperr"
	"example.com/service/internal/logging"
)

func TestWriteAnswersEveryErrorAsAProblem(t *testing.T) {
	t.Parallel()
	cause := errors.New("pg: connection refused")
	tests := []struct {
		name   string
		err    error
		want   apperr.Code
		fields int
		level  string
	}{
		{"registered code", apperr.New(apperr.NotFound, "gone").WithInternal("id=%d", 7), apperr.NotFound, 0, "INFO"},
		{"wrapped twice", fmt.Errorf("svc: %w", apperr.Wrap(apperr.MalformedBody, "bad", cause)), apperr.MalformedBody, 0, "INFO"},
		{"plain error", cause, apperr.Internal, 0, "ERROR"},
		{"zero code", &apperr.Error{Detail: "minted outside the registry"}, apperr.Internal, 0, "ERROR"},
		{"fields", apperr.Invalid(apperr.FieldError{Pointer: "/name", Code: "minLength"}), apperr.ValidationFailed, 1, "INFO"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			var logs bytes.Buffer
			rec := httptest.NewRecorder()
			apperr.Write(rec, request(t), slog.New(slog.NewJSONHandler(&logs, nil)), tt.err)
			p := decodeProblem(t, rec)
			want := apperr.Problem{
				Type: apperr.TypeBase + tt.want.Name(), Title: tt.want.Title(), Status: tt.want.Status(),
				Code: tt.want.Name(), RequestID: "req-1",
			}
			if rec.Code != tt.want.Status() || p.Type != want.Type || p.Title != want.Title || p.Code != want.Code ||
				p.Status != want.Status || p.RequestID != want.RequestID || len(p.Fields) != tt.fields {
				t.Fatalf("got %d %+v, want %+v", rec.Code, p, want)
			}
			if !strings.Contains(logs.String(), `"level":"`+tt.level+`"`) || !strings.Contains(logs.String(), `"requestId":"req-1"`) {
				t.Fatalf("log line: %s", logs.String())
			}
			if body := rec.Body.String(); strings.Contains(body, "connection refused") || strings.Contains(body, "id=7") {
				t.Fatalf("internal detail leaked into the body: %s", body)
			}
		})
	}
}

func TestWithStatusAnswersAnotherErrorStatusOnly(t *testing.T) {
	t.Parallel()
	var logs bytes.Buffer
	rec := httptest.NewRecorder()
	err := apperr.New(apperr.MalformedBody, "").WithStatus(http.StatusInternalServerError).WithStatus(http.StatusOK)
	apperr.Write(rec, request(t), slog.New(slog.NewJSONHandler(&logs, nil)), err)
	p := decodeProblem(t, rec)
	if rec.Code != http.StatusInternalServerError || p.Status != http.StatusInternalServerError || p.Code != "MALFORMED_BODY" {
		t.Fatalf("got %d %+v", rec.Code, p)
	}
	if !strings.Contains(logs.String(), `"level":"ERROR"`) || !strings.Contains(logs.String(), `"status":500`) {
		t.Fatalf("log line: %s", logs.String())
	}
	if got := apperr.New(apperr.NotFound, "").Status(); got != http.StatusNotFound {
		t.Fatalf("without WithStatus the code's status: got %d", got)
	}
}

func TestWriteLogsABodyItCouldNotSend(t *testing.T) {
	t.Parallel()
	var logs bytes.Buffer
	apperr.Write(brokenWriter{httptest.NewRecorder()}, request(t), slog.New(slog.NewJSONHandler(&logs, nil)),
		apperr.New(apperr.NotFound, "gone"))
	if !strings.Contains(logs.String(), "problem body not written") {
		t.Fatalf("want the failed write logged, got %s", logs.String())
	}
}

func TestErrorKeepsItsCauseAndCode(t *testing.T) {
	t.Parallel()
	cause := errors.New("cause")
	err := apperr.Wrap(apperr.Internal, "x", cause)
	if !errors.Is(err, cause) || err.Error() != "INTERNAL: x: cause" {
		t.Fatalf("chain broken: %v", err)
	}
	if got := apperr.New(apperr.NotFound, "x").Error(); got != "NOT_FOUND: x" {
		t.Fatalf("got %q", got)
	}
	if apperr.As(cause) != nil || apperr.As(fmt.Errorf("w: %w", err)) != err {
		t.Fatal("As must find the *Error in the chain, and only there")
	}
}

func TestLookupAnswersOnlyRegisteredCodes(t *testing.T) {
	t.Parallel()
	if c, ok := apperr.Lookup("NOT_FOUND"); !ok || c != apperr.NotFound {
		t.Fatalf("got %v %v", c, ok)
	}
	if _, ok := apperr.Lookup("MADE_UP"); ok {
		t.Fatal("a code the registry does not hold was found")
	}
}

func request(t *testing.T) *http.Request {
	t.Helper()
	ctx := logging.WithRequestID(t.Context(), "req-1")
	return httptest.NewRequestWithContext(ctx, http.MethodGet, "/", nil)
}

func decodeProblem(t *testing.T, rec *httptest.ResponseRecorder) apperr.Problem {
	t.Helper()
	if ct := rec.Header().Get("Content-Type"); ct != "application/problem+json" {
		t.Fatalf("content type %q", ct)
	}
	var p apperr.Problem
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	return p
}

type brokenWriter struct{ *httptest.ResponseRecorder }

func (brokenWriter) Write([]byte) (int, error) { return 0, errors.New("connection closed") }
