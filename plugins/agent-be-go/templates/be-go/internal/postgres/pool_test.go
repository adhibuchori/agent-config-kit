// Tests for the pool: its bounds, its refusals, and the role it runs as.

package postgres_test

import (
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"example.com/service/internal/postgres"
)

// testURL is the test database as the service's own role, from .env.ci.example through
// scripts/check/ci-env.sh. The tests run against a real PostgreSQL with db/roles.sql applied.
func testURL(t *testing.T, key string) string {
	t.Helper()
	url := os.Getenv(key)
	if url == "" {
		t.Fatalf("%s is not set: run the tests through `bash scripts/check/gates.sh` (or "+
			"`bash scripts/check/ci-env.sh bash scripts/check/coverage.sh`), with PostgreSQL 18 up and "+
			"db/roles.sql applied (.claude/rules/backend/testing.md)", key)
	}
	return url
}

func TestConfigSetsEveryBound(t *testing.T) {
	t.Parallel()
	pc, err := postgres.Config("postgres://app_rw@db.example.invalid/app", 12)
	if err != nil {
		t.Fatal(err)
	}
	if pc.MaxConns != 12 || pc.MinConns != 0 || pc.MaxConnLifetime != time.Hour || pc.MaxConnIdleTime != 10*time.Minute ||
		pc.HealthCheckPeriod != time.Minute || pc.ConnConfig.ConnectTimeout != 5*time.Second {
		t.Fatalf("got %+v", pc)
	}
}

func TestConfigRefuses(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, url string
		conns     int32
		want      error
	}{
		{"a pool of two", "postgres://app_rw@db.example.invalid/app", 2, nil},
		{"an unreadable string", "postgres://app_rw@db.example.invalid:port/app", 10, nil},
		{"a startup timeout", "postgres://app_rw@db.example.invalid/app?statement_timeout=5000", 10, postgres.ErrStartupTimeout},
		{"describe_exec", "postgres://app_rw@db.example.invalid/app?default_query_exec_mode=describe_exec", 10, postgres.ErrDescribeExec},
	}
	for _, tt := range tests {
		_, err := postgres.Config(tt.url, tt.conns)
		if err == nil || (tt.want != nil && !errors.Is(err, tt.want)) {
			t.Errorf("%s: got %v, want an error (%v)", tt.name, err, tt.want)
		}
	}
}

func TestThePoolRunsAsTheServiceRole(t *testing.T) {
	t.Parallel()
	pc, err := postgres.Config(testURL(t, "TEST_DATABASE_URL"), postgres.MinConns)
	if err != nil {
		t.Fatal(err)
	}
	pool, err := postgres.NewPool(t.Context(), pc)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	for _, name := range []string{"statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout", "transaction_timeout"} {
		var value string
		if err := pool.QueryRow(t.Context(), "select current_setting($1)", name).Scan(&value); err != nil {
			t.Fatal(err)
		}
		if value == "0" || value == "" {
			t.Errorf("%s is %q for the service role: set it in db/roles.sql", name, value)
		}
	}
	_, err = pool.Exec(t.Context(), "create table pool_probe (id int)")
	if pgErr, ok := errors.AsType[*pgconn.PgError](err); !ok || pgErr.Code != "42501" {
		t.Fatalf("the service role created a table (err %v): it must hold DML rights only", err)
	}
}

func TestNewPoolFailsFastWithoutADatabase(t *testing.T) {
	t.Parallel()
	pc, err := postgres.Config("postgres://app_rw@127.0.0.1:1/none?sslmode=disable", postgres.MinConns)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := postgres.NewPool(t.Context(), pc); err == nil {
		t.Fatal("a pool with nothing behind it opened")
	}
	pc.MaxConns = 0
	if _, err := postgres.NewPool(t.Context(), pc); err == nil {
		t.Fatal("a pool of zero connections opened")
	}
}
