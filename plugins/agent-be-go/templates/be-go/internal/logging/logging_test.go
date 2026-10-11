// Tests for the logger and the request ID in a context.

package logging_test

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"testing"

	"example.com/service/internal/logging"
)

func TestNewWritesJSONAtTheLevel(t *testing.T) {
	t.Parallel()
	var out bytes.Buffer
	logger := logging.New(&out, slog.LevelWarn)
	logger.LogAttrs(t.Context(), slog.LevelInfo, "dropped")
	logger.LogAttrs(t.Context(), slog.LevelWarn, "kept", slog.String("requestId", "r-1"))
	var line map[string]any
	if err := json.Unmarshal(out.Bytes(), &line); err != nil {
		t.Fatalf("want one JSON line, got %q: %v", out.String(), err)
	}
	if line["msg"] != "kept" || line["requestId"] != "r-1" {
		t.Fatalf("got %v", line)
	}
}

func TestRequestIDTravelsInTheContext(t *testing.T) {
	t.Parallel()
	if got := logging.RequestID(t.Context()); got != "" {
		t.Fatalf("outside a request: got %q, want empty", got)
	}
	ctx := logging.WithRequestID(t.Context(), "r-2")
	if got := logging.RequestID(ctx); got != "r-2" {
		t.Fatalf("got %q, want r-2", got)
	}
}
