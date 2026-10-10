// Tests for the configuration reader: defaults, every variable, and the first bad one.

package config_test

import (
	"errors"
	"log/slog"
	"maps"
	"strings"
	"testing"
	"time"

	"example.com/service/internal/config"
)

func env(vars map[string]string) config.LookupFunc {
	return func(key string) (string, bool) {
		v, ok := vars[key]
		return v, ok
	}
}

func TestLoadDefaults(t *testing.T) {
	t.Parallel()
	cfg, err := config.Load(env(map[string]string{"DATABASE_URL": "postgres://app_rw@db/app"}))
	if err != nil {
		t.Fatal(err)
	}
	h := cfg.HTTP
	if h.Addr != ":8080" || h.MaxBodyBytes != 1<<20 || h.ReadHeaderTimeout != 5*time.Second ||
		h.ReadTimeout != 15*time.Second || h.WriteTimeout != 30*time.Second ||
		h.IdleTimeout != 120*time.Second || h.ShutdownTimeout != 20*time.Second {
		t.Fatalf("HTTP defaults: %+v", h)
	}
	if cfg.Database.MaxConns != 10 || cfg.LogLevel != slog.LevelInfo || cfg.Production {
		t.Fatalf("defaults: %+v", cfg)
	}
}

func TestLoadReadsEveryVariable(t *testing.T) {
	t.Parallel()
	cfg, err := config.Load(env(map[string]string{
		"DATABASE_URL": "postgres://app_rw@db/app", "DB_MAX_CONNS": "25", "HTTP_ADDR": ":9000",
		"HTTP_READ_TIMEOUT": "2s", "LOG_LEVEL": "debug", "APP_ENV": "production",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Database.MaxConns != 25 || cfg.HTTP.Addr != ":9000" || cfg.HTTP.ReadTimeout != 2*time.Second ||
		cfg.LogLevel != slog.LevelDebug || !cfg.Production {
		t.Fatalf("got %+v", cfg)
	}
}

func TestLoadRefusesTheFirstBadVariable(t *testing.T) {
	t.Parallel()
	base := map[string]string{"DATABASE_URL": "postgres://app_rw@db/app"}
	tests := []struct {
		key, value, want string
	}{
		{"DATABASE_URL", "", "DATABASE_URL: required environment variable is not set"},
		{"DB_MAX_CONNS", "2", "DB_MAX_CONNS: 2 is outside 3..1000"},
		{"DB_MAX_CONNS", "ten", "DB_MAX_CONNS: strconv.ParseInt"},
		{"HTTP_READ_TIMEOUT", "0s", "HTTP_READ_TIMEOUT: 0s is not positive"},
		{"HTTP_IDLE_TIMEOUT", "soon", "HTTP_IDLE_TIMEOUT: time: invalid duration"},
		{"LOG_LEVEL", "loud", "LOG_LEVEL: slog: level string"},
	}
	for _, tt := range tests {
		vars := map[string]string{"DB_MAX_CONNS": "4", "HTTP_READ_TIMEOUT": "1s"}
		maps.Copy(vars, base)
		vars[tt.key] = tt.value
		_, err := config.Load(env(vars))
		if err == nil || !strings.HasPrefix(err.Error(), tt.want) {
			t.Errorf("%s=%q: got %v, want %q", tt.key, tt.value, err, tt.want)
		}
	}
	_, err := config.Load(env(map[string]string{"HTTP_READ_TIMEOUT": "-1s", "LOG_LEVEL": "loud"}))
	if err == nil || !strings.HasPrefix(err.Error(), "HTTP_READ_TIMEOUT") || errors.Is(err, config.ErrMissing) {
		t.Fatalf("two bad variables and no DATABASE_URL: got %v, want the first one only", err)
	}
}
