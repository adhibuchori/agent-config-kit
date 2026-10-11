//! What every handler can reach: handles, never request data.

use std::sync::Arc;

use sqlx::PgPool;

use super::config::Config;

/// Cloned for every request: the pool and the configuration.
#[derive(Clone)]
pub struct AppState {
    /// The pool every repository queries through.
    pub pool: PgPool,
    /// The configuration read at startup.
    pub config: Arc<Config>,
}
