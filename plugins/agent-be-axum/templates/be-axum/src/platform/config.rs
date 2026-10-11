//! The one reader of the process environment (Rule 19). Every value is read once, at startup.

use std::net::SocketAddr;
use std::str::FromStr;
use std::time::Duration;

/// The smallest pool the service runs with: one connection serialises every request (Rule 17).
const MIN_POOL: u32 = 3;

/// Everything the service reads from its environment.
#[derive(Debug, Clone)]
pub struct Config {
    /// `DATABASE_URL`: the pool's connection string, for the `app_rw` role.
    pub database_url: String,
    /// `LISTEN_ADDR`, default `0.0.0.0:8080`.
    pub listen: SocketAddr,
    /// `APP_ENV=production`: the placeholder problem-type base is then refused (Rule 7).
    pub production: bool,
    /// `REQUEST_TIMEOUT_MS`, default 15 000: a slower request answers 504.
    pub request_timeout: Duration,
    /// `BODY_LIMIT_BYTES`, default 1 MiB: a larger body answers 413.
    pub body_limit_bytes: usize,
    /// `CORS_ORIGINS`, comma separated. Empty lets no browser origin in.
    pub cors_origins: Vec<String>,
    /// `DB_MAX_CONNECTIONS`, default 10, at least 3 (Rule 17).
    pub db_max_connections: u32,
    /// `DB_ACQUIRE_TIMEOUT_MS`, default 5 000: how long a request waits for a connection.
    pub db_acquire_timeout: Duration,
    /// `SHUTDOWN_GRACE_MS`, default 20 000: how long a shutdown waits for requests in flight.
    pub shutdown_grace: Duration,
}

/// A variable that is missing or does not parse. The message names it, never its value.
#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum ConfigError {
    /// A required variable is not set.
    #[error("environment variable {0} is missing")]
    Missing(&'static str),
    /// A variable is set to something the service cannot use.
    #[error("environment variable {0} is invalid")]
    Invalid(&'static str),
}

type Lookup<'a> = &'a dyn Fn(&str) -> Option<String>;

impl Config {
    /// Reads the process environment.
    ///
    /// # Errors
    /// A required variable is missing, or a value does not parse.
    #[expect(
        clippy::disallowed_methods,
        reason = "the one place the environment is read (Rule 19)"
    )]
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::from_lookup(|key| std::env::var(key).ok())
    }

    /// Reads the configuration through `get`, so a test passes its own values.
    ///
    /// # Errors
    /// A required variable is missing, or a value does not parse.
    pub fn from_lookup(get: impl Fn(&str) -> Option<String>) -> Result<Self, ConfigError> {
        let get: Lookup<'_> = &get;
        let db_max_connections = number(get, "DB_MAX_CONNECTIONS", 10)?;
        if db_max_connections < MIN_POOL {
            return Err(ConfigError::Invalid("DB_MAX_CONNECTIONS"));
        }
        Ok(Self {
            database_url: get("DATABASE_URL").ok_or(ConfigError::Missing("DATABASE_URL"))?,
            listen: number(get, "LISTEN_ADDR", SocketAddr::from(([0, 0, 0, 0], 8080)))?,
            production: get("APP_ENV").as_deref() == Some("production"),
            request_timeout: millis(get, "REQUEST_TIMEOUT_MS", 15_000)?,
            body_limit_bytes: number(get, "BODY_LIMIT_BYTES", 1_048_576)?,
            cors_origins: get("CORS_ORIGINS")
                .unwrap_or_default()
                .split(',')
                .map(str::trim)
                .filter(|origin| !origin.is_empty())
                .map(str::to_owned)
                .collect(),
            db_max_connections,
            db_acquire_timeout: millis(get, "DB_ACQUIRE_TIMEOUT_MS", 5_000)?,
            shutdown_grace: millis(get, "SHUTDOWN_GRACE_MS", 20_000)?,
        })
    }
}

/// `key` parsed as `T`, or `default` when it is not set.
fn number<T: FromStr>(get: Lookup<'_>, key: &'static str, default: T) -> Result<T, ConfigError> {
    match get(key) {
        None => Ok(default),
        Some(raw) => raw.trim().parse().or(Err(ConfigError::Invalid(key))),
    }
}

/// `key` as a number of milliseconds.
fn millis(get: Lookup<'_>, key: &'static str, default: u64) -> Result<Duration, ConfigError> {
    number(get, key, default).map(Duration::from_millis)
}

#[cfg(test)]
#[path = "config_tests.rs"]
mod tests;
