// Package config reads the process configuration from the environment, once, at startup. It is the
// only package that reads environment variables; main passes it os.LookupEnv.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"time"
)

// LookupFunc is os.LookupEnv's signature, so a test passes a map instead of the real environment.
type LookupFunc func(key string) (string, bool)

// HTTP is the server's address, body limit and timeouts. None is left at zero, which would mean none.
type HTTP struct {
	Addr              string
	MaxBodyBytes      int64
	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	ShutdownTimeout   time.Duration
}

// Database is the pool's address and size. The server-side timeouts belong to the database role
// (db/roles.sql), not to this process.
type Database struct {
	URL      string
	MaxConns int32
}

// Config is everything the process reads from its environment.
type Config struct {
	HTTP       HTTP
	Database   Database
	LogLevel   slog.Level
	Production bool
}

// ErrMissing is returned when a required variable is unset or empty.
var ErrMissing = errors.New("required environment variable is not set")

// The pool bounds: below 3 every request queues behind one or two connections; above 1000 the pool
// alone would exhaust a database's connection slots.
const (
	minConns = 3
	maxConns = 1000
)

// Load reads and checks the configuration, and fails on the first invalid variable.
func Load(lookup LookupFunc) (Config, error) {
	r := reader{lookup: lookup}
	cfg := Config{
		HTTP: HTTP{
			Addr:              r.str("HTTP_ADDR", ":8080"),
			MaxBodyBytes:      r.integer("HTTP_MAX_BODY_BYTES", 1<<20, 1, 1<<30),
			ReadHeaderTimeout: r.duration("HTTP_READ_HEADER_TIMEOUT", 5*time.Second),
			ReadTimeout:       r.duration("HTTP_READ_TIMEOUT", 15*time.Second),
			WriteTimeout:      r.duration("HTTP_WRITE_TIMEOUT", 30*time.Second),
			IdleTimeout:       r.duration("HTTP_IDLE_TIMEOUT", 120*time.Second),
			ShutdownTimeout:   r.duration("HTTP_SHUTDOWN_TIMEOUT", 20*time.Second),
		},
		Database: Database{
			URL:      r.required("DATABASE_URL"),
			MaxConns: int32(r.integer("DB_MAX_CONNS", 10, minConns, maxConns)), //nolint:gosec // G115: integer() keeps it within minConns..maxConns.
		},
		LogLevel:   r.level("LOG_LEVEL", slog.LevelInfo),
		Production: r.str("APP_ENV", "development") == "production",
	}
	return cfg, r.err
}

// reader keeps the first error, so Load reads on and reports one variable.
type reader struct {
	lookup LookupFunc
	err    error
}

func (r *reader) raw(key string) (string, bool) {
	v, ok := r.lookup(key)
	return v, ok && v != ""
}

func (r *reader) fail(key string, err error) {
	if r.err == nil {
		r.err = fmt.Errorf("%s: %w", key, err)
	}
}

func (r *reader) str(key, fallback string) string {
	if v, ok := r.raw(key); ok {
		return v
	}
	return fallback
}

func (r *reader) required(key string) string {
	v, ok := r.raw(key)
	if !ok {
		r.fail(key, ErrMissing)
	}
	return v
}

func (r *reader) integer(key string, fallback, lowest, highest int64) int64 {
	v, ok := r.raw(key)
	if !ok {
		return fallback
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		r.fail(key, err)
		return fallback
	}
	if n < lowest || n > highest {
		r.fail(key, fmt.Errorf("%d is outside %d..%d", n, lowest, highest))
		return fallback
	}
	return n
}

func (r *reader) duration(key string, fallback time.Duration) time.Duration {
	v, ok := r.raw(key)
	if !ok {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err == nil && d <= 0 {
		err = fmt.Errorf("%s is not positive", v)
	}
	if err != nil {
		r.fail(key, err)
		return fallback
	}
	return d
}

func (r *reader) level(key string, fallback slog.Level) slog.Level {
	v, ok := r.raw(key)
	if !ok {
		return fallback
	}
	var l slog.Level
	if err := l.UnmarshalText([]byte(v)); err != nil {
		r.fail(key, err)
		return fallback
	}
	return l
}
