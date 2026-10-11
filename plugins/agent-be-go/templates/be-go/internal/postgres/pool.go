// Package postgres owns the connection pool and the stores that adapt sqlc's queries to the
// interfaces the modules declare. It is the only package that imports pgx.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MinConns is the smallest pool a service may run: with one or two connections every request
// queues behind the others.
const MinConns = 3

// ErrStartupTimeout is Config's answer to a connection string that sets a server timeout. A
// transaction pooler refuses such a startup parameter, and the timeouts belong to the role.
var ErrStartupTimeout = errors.New("set server timeouts on the database role (db/roles.sql), not in the connection string")

// ErrDescribeExec is Config's answer to default_query_exec_mode=describe_exec, which reads another
// client's result behind a transaction pooler.
var ErrDescribeExec = errors.New("describe_exec is not safe behind a transaction pooler")

var roleSettings = []string{
	"statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout", "transaction_timeout",
}

// Config is the pool configuration for url: every size, lifetime and the connect timeout set
// explicitly, nothing left to pgxpool's machine-dependent defaults.
func Config(url string, maxConns int32) (*pgxpool.Config, error) {
	pc, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("postgres: parse the connection string: %w", err)
	}
	if maxConns < MinConns {
		return nil, fmt.Errorf("postgres: a pool of %d connections; the floor is %d", maxConns, MinConns)
	}
	for _, name := range roleSettings {
		if _, ok := pc.ConnConfig.RuntimeParams[name]; ok {
			return nil, fmt.Errorf("postgres: %s: %w", name, ErrStartupTimeout)
		}
	}
	if pc.ConnConfig.DefaultQueryExecMode == pgx.QueryExecModeDescribeExec {
		return nil, fmt.Errorf("postgres: %w", ErrDescribeExec)
	}
	pc.MaxConns = maxConns
	pc.MinConns = 0
	pc.MaxConnLifetime = time.Hour
	pc.MaxConnLifetimeJitter = 5 * time.Minute
	pc.MaxConnIdleTime = 10 * time.Minute
	pc.HealthCheckPeriod = time.Minute
	pc.ConnConfig.ConnectTimeout = 5 * time.Second
	return pc, nil
}

// NewPool opens the pool and proves one connection, so a wrong address fails at startup rather
// than on the first request.
func NewPool(ctx context.Context, pc *pgxpool.Config) (*pgxpool.Pool, error) {
	pool, err := pgxpool.NewWithConfig(ctx, pc)
	if err != nil {
		return nil, fmt.Errorf("postgres: open the pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("postgres: reach the database: %w", err)
	}
	return pool, nil
}
