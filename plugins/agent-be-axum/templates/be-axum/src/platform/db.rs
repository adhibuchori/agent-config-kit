//! The connection pool: every limit set on purpose, none left at its default (Rule 17).

use std::time::Duration;

use sqlx::PgPool;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};

use super::config::Config;

/// A lazily connecting pool for the `app_rw` role. Session timeouts come from the role
/// (`ALTER ROLE app_rw SET ...` in db/roles.sql), never from startup parameters: a transaction
/// pooler refuses those, and `extra_float_digits` is one sqlx sends unless told not to.
///
/// # Errors
/// `DATABASE_URL` does not parse.
pub fn pool(config: &Config) -> Result<PgPool, sqlx::Error> {
    let options = config
        .database_url
        .parse::<PgConnectOptions>()?
        .application_name(env!("CARGO_PKG_NAME"))
        .extra_float_digits(None);
    Ok(PgPoolOptions::new()
        .max_connections(config.db_max_connections)
        .min_connections(0)
        .acquire_timeout(config.db_acquire_timeout)
        .idle_timeout(Duration::from_mins(5))
        .max_lifetime(Duration::from_mins(30))
        .connect_lazy_with(options))
}

/// Whether the database answers: the readiness probe's one query.
pub(crate) async fn ping(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::query("SELECT 1").execute(pool).await.map(drop)
}
