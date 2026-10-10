// Command api serves the HTTP API: configuration from the environment, the problem-type check, one
// pool, one server with every timeout set, and a graceful shutdown on SIGINT or SIGTERM. It wires
// the packages together and holds no logic of its own, which is why it is exempt from coverage.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"example.com/service/internal/apperr"
	"example.com/service/internal/config"
	"example.com/service/internal/httpapi"
	"example.com/service/internal/logging"
	"example.com/service/internal/postgres"
)

func main() {
	if err := run(); err != nil {
		slog.Error("api stopped", slog.Any("error", err))
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load(os.LookupEnv)
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}
	logger := logging.New(os.Stdout, cfg.LogLevel)
	if err := apperr.CheckTypeBase(apperr.TypeBase, cfg.Production); err != nil {
		return err
	}
	spec, err := httpapi.GetSpec()
	if err != nil {
		return fmt.Errorf("spec: %w", err)
	}
	pc, err := postgres.Config(cfg.Database.URL, cfg.Database.MaxConns)
	if err != nil {
		return err
	}
	pool, err := postgres.NewPool(ctx, pc)
	if err != nil {
		return err
	}
	defer pool.Close() // the stores take it: Handlers{Things: thing.NewService(postgres.NewThingStore(pool))}

	router, err := httpapi.NewRouter(logger, spec, cfg.HTTP.MaxBodyBytes, httpapi.Handlers{})
	if err != nil {
		return err
	}
	return serve(ctx, stop, httpapi.NewServer(cfg.HTTP, router, logger), cfg.HTTP, logger)
}

// serve runs srv until it fails or ctx ends, then shuts it down within the configured budget.
func serve(ctx context.Context, stop context.CancelFunc, srv *http.Server, cfg config.HTTP, logger *slog.Logger) error {
	failed := make(chan error, 1)
	go func() { failed <- srv.ListenAndServe() }()
	logger.LogAttrs(ctx, slog.LevelInfo, "listening", slog.String("addr", cfg.Addr))

	select {
	case err := <-failed:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
	}
	stop()
	logger.LogAttrs(ctx, slog.LevelInfo, "shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), cfg.ShutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	return nil
}
