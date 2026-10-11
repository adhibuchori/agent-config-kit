// Tests of the service's pool behind a transaction pooler; only the quality gate builds them.

//go:build pooler

package postgres_test

import (
	"fmt"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"example.com/service/internal/postgres"
)

// These tests run only behind a transaction pooler: scripts/check/pooler.sh builds them with the
// pooler tag once the quality gate has PgBouncer listening (TEST_POOLER_DATABASE_URL), and the
// default test run never compiles them. They go through the service's own pool constructor, so
// they prove the configuration production runs, not a test-only one.

func poolAt(t *testing.T, key string) *pgxpool.Pool {
	t.Helper()
	pc, err := postgres.Config(testURL(t, key), 8)
	if err != nil {
		t.Fatal(err)
	}
	pool, err := postgres.NewPool(t.Context(), pc)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func roleSettings(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	var got string
	err := pool.QueryRow(t.Context(), `select current_setting('statement_timeout') || '|' ||
		current_setting('idle_in_transaction_session_timeout') || '|' || current_setting('lock_timeout')`).Scan(&got)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

// TestPoolerAnswersEveryQueryRight: 8 workers, 50 statements each, every one with its own SQL text,
// so each is a new prepared statement. A pooler that hands one client's statement or result to
// another shows up as an error or a wrong answer.
func TestPoolerAnswersEveryQueryRight(t *testing.T) {
	pool := poolAt(t, "TEST_POOLER_DATABASE_URL")
	var wg sync.WaitGroup
	errs := make(chan error, 8*50)
	for worker := range 8 {
		wg.Go(func() {
			for i := range 50 {
				n := worker*1000 + i
				var got int64
				sql := fmt.Sprintf("select $1::bigint * 3 + %d", n)
				if err := pool.QueryRow(t.Context(), sql, int64(n)).Scan(&got); err != nil {
					errs <- fmt.Errorf("worker %d query %d: %w", worker, i, err)
				} else if want := int64(n)*3 + int64(n); got != want {
					errs <- fmt.Errorf("worker %d query %d: got %d, want %d", worker, i, got, want)
				}
			}
		})
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
}

// TestPoolerKeepsTheRoleTimeouts: the timeouts read through the pooler are the role's, the same
// as a direct connection reads, and not zero; twenty reads in a row agree, so no session state
// leaked from one client to the next.
func TestPoolerKeepsTheRoleTimeouts(t *testing.T) {
	direct := roleSettings(t, poolAt(t, "TEST_DATABASE_URL"))
	if direct == "0|0|0" {
		t.Fatalf("the role has no timeouts (%s): apply db/roles.sql", direct)
	}
	pooled := poolAt(t, "TEST_POOLER_DATABASE_URL")
	for i := range 20 {
		if got := roleSettings(t, pooled); got != direct {
			t.Fatalf("read %d through the pooler: %s, direct: %s", i, got, direct)
		}
	}
}
