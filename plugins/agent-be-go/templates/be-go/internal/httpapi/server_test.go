// Tests for the server constructor and the spec export.

package httpapi_test

import (
	"log/slog"
	"net/http"
	"testing"
	"time"

	"example.com/service/internal/config"
	"example.com/service/internal/httpapi"
)

func TestNewServerSetsEveryTimeout(t *testing.T) {
	t.Parallel()
	cfg := config.HTTP{
		Addr: ":0", ReadHeaderTimeout: time.Second, ReadTimeout: 2 * time.Second,
		WriteTimeout: 3 * time.Second, IdleTimeout: 4 * time.Second,
	}
	srv := httpapi.NewServer(cfg, http.NotFoundHandler(), slog.New(slog.DiscardHandler))
	if srv.ReadHeaderTimeout != time.Second || srv.ReadTimeout != 2*time.Second || srv.WriteTimeout != 3*time.Second ||
		srv.IdleTimeout != 4*time.Second || srv.MaxHeaderBytes <= 0 || srv.ErrorLog == nil || srv.Addr != ":0" {
		t.Fatalf("got %+v", srv)
	}
}

func TestIndentSpecWritesTheEmbeddedSpec(t *testing.T) {
	t.Parallel()
	raw, err := httpapi.GetSpecJSON()
	if err != nil {
		t.Fatal(err)
	}
	out, err := httpapi.IndentSpec(raw)
	if err != nil || len(out) <= len(raw) || out[len(out)-1] != '\n' {
		t.Fatalf("got %d bytes from %d, err %v", len(out), len(raw), err)
	}
	if _, err := httpapi.IndentSpec([]byte("{")); err == nil {
		t.Fatal("broken JSON was indented")
	}
}
