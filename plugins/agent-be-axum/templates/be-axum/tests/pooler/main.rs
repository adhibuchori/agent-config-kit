//! Pooler tier: the service's own pool through `PgBouncer` in transaction mode. The quality gate
//! runs it with `pgbouncer-tests: true` (scripts/check/pooler.sh); everywhere else it is ignored.
//! It catches what a pooler breaks silently: prepared statements answering for another client,
//! startup parameters refused, and session settings leaking between clients.
#![cfg(test)]

use service::{Config, pool};
use sqlx::{AssertSqlSafe, PgPool};

const WORKERS: i64 = 8;
const QUERIES: i64 = 50;

#[expect(
    clippy::disallowed_methods,
    reason = "the test reads the pooler URL the quality gate exports"
)]
fn pooled() -> PgPool {
    let url = std::env::var("TEST_POOLER_DATABASE_URL")
        .expect("TEST_POOLER_DATABASE_URL: run scripts/check/pooler.sh");
    let config =
        Config::from_lookup(|key| (key == "DATABASE_URL").then(|| url.clone())).expect("config");
    pool(&config).expect("pool")
}

/// One worker's queries, each with SQL text of its own, so each is a statement of its own.
async fn ask(pool: PgPool, worker: i64) {
    for query in 0..QUERIES {
        // sql-safe: both numbers are loop counters, never input.
        let sql = format!("SELECT $1::int8 * {query} + {worker}");
        let answer: i64 = sqlx::query_scalar(AssertSqlSafe(sql))
            .bind(7_i64)
            .fetch_one(&pool)
            .await
            .expect("answer");
        assert_eq!(answer, 7 * query + worker, "worker {worker}, query {query}");
    }
}

#[tokio::test]
#[ignore = "runs behind PgBouncer in the quality gate"]
async fn every_query_gets_its_own_answer() {
    let pool = pooled();
    let workers: Vec<_> = (0..WORKERS)
        .map(|worker| tokio::spawn(ask(pool.clone(), worker)))
        .collect();
    for worker in workers {
        worker.await.expect("the worker finished");
    }
}

#[tokio::test]
#[ignore = "runs behind PgBouncer in the quality gate"]
async fn the_role_timeout_reaches_every_session_and_nothing_leaks() {
    let pool = pooled();
    let configured: String = sqlx::query_scalar(
        "SELECT split_part(setting, '=', 2) FROM pg_db_role_setting, unnest(setconfig) AS setting \
         WHERE setrole = current_user::text::regrole AND setdatabase = 0 \
         AND setting LIKE 'statement_timeout=%'",
    )
    .fetch_one(&pool)
    .await
    .expect("db/roles.sql sets statement_timeout on this role");
    assert_ne!(configured, "0", "a real timeout");
    for read in 0..20 {
        let seen: String = sqlx::query_scalar("SELECT current_setting('statement_timeout')")
            .fetch_one(&pool)
            .await
            .expect("read");
        assert_eq!(
            seen, configured,
            "read {read}: the role's timeout, never another session's"
        );
    }
}
