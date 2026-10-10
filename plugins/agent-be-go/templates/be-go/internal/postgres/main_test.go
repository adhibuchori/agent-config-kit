// The test database follows the branch's migrations before any test of this package runs.

package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib" // registers the "pgx" database/sql driver goose runs on
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"
)

// TestMain applies every migration in db/migrations to the test database as the migrator role
// (TEST_MIGRATIONS_URL), then runs the tests, which connect as the service's role. The quality gate
// runs the tests before it migrates a database of its own, and a developer's test database follows
// the branch the same way. A session lock keeps two test binaries from migrating at once.
func TestMain(m *testing.M) {
	if err := migrate(); err != nil {
		fmt.Fprintln(os.Stderr, "postgres tests:", err)
		os.Exit(1)
	}
	os.Exit(m.Run())
}

func migrate() (err error) {
	url := os.Getenv("TEST_MIGRATIONS_URL")
	if url == "" {
		return errors.New("TEST_MIGRATIONS_URL is not set: run the tests through scripts/check/ci-env.sh " +
			"(.env.ci.example sets it), with PostgreSQL 18 up and db/roles.sql applied")
	}
	db, err := sql.Open("pgx", url)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, db.Close()) }()
	locker, err := lock.NewPostgresSessionLocker()
	if err != nil {
		return err
	}
	provider, err := goose.NewProvider(goose.DialectPostgres, db, os.DirFS("../../db/migrations"),
		goose.WithSessionLocker(locker))
	if errors.Is(err, goose.ErrNoMigrations) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read db/migrations: %w", err)
	}
	ctx := context.Background() //nolint:forbidigo // TestMain runs before any test, so there is no t.Context() yet.
	if _, err := provider.Up(ctx); err != nil {
		return fmt.Errorf("migrate the test database: %w", err)
	}
	return nil
}
