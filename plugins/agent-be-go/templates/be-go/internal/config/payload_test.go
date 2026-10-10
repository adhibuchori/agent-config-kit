// Tests for the payload contract's variables: read as they are, and never logged.

package config_test

import (
	"bytes"
	"log/slog"
	"strings"
	"testing"

	"example.com/service/internal/config"
)

func TestLoadPayloadReadsTheFourVariables(t *testing.T) {
	t.Parallel()
	if got := config.LoadPayload(env(map[string]string{})); got != (config.Payload{}) {
		t.Fatalf("unset: %+v", got)
	}
	got := config.LoadPayload(env(map[string]string{
		"PAYLOAD_MODE": "off", "PAYLOAD_KEY": "k1:placeholder", "PAYLOAD_KEY_NEXT": "k2:placeholder", "PAYLOAD_SERVER_JWK": "e30",
	}))
	want := config.Payload{Mode: "off", Key: "k1:placeholder", KeyNext: "k2:placeholder", ServerJWK: "e30"}
	if got != want {
		t.Fatalf("got %+v", got)
	}
}

func TestPayloadNeverLogsAKey(t *testing.T) {
	t.Parallel()
	var logs bytes.Buffer
	p := config.Payload{Mode: "strict", Key: "k1:placeholder", ServerJWK: "e30"}
	slog.New(slog.NewJSONHandler(&logs, nil)).LogAttrs(t.Context(), slog.LevelInfo, "settings", slog.Any("payload", p))
	line := logs.String()
	if strings.Contains(line, "placeholder") || strings.Contains(line, "e30") || !strings.Contains(line, `"key":true`) ||
		!strings.Contains(line, `"keyNext":false`) {
		t.Fatalf("log line: %s", line)
	}
}
