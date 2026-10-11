use std::time::Duration;

use super::{Config, ConfigError};

/// A lookup over fixed pairs, the way a test environment would answer.
fn lookup(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
    let pairs: Vec<(String, String)> = pairs
        .iter()
        .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
        .collect();
    move |key| {
        pairs
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value.clone())
    }
}

const URL: (&str, &str) = ("DATABASE_URL", "postgres://app_rw@127.0.0.1:5432/app");

#[test]
fn only_the_database_url_is_required_and_the_rest_has_defaults() {
    let config = Config::from_lookup(lookup(&[URL])).expect("complete");
    assert_eq!(config.database_url, URL.1, "the URL as given");
    assert_eq!(
        config.listen.to_string(),
        "0.0.0.0:8080",
        "default listen address"
    );
    assert!(!config.production, "production only when APP_ENV says so");
    assert_eq!(
        config.request_timeout,
        Duration::from_secs(15),
        "default request timeout"
    );
    assert_eq!(config.body_limit_bytes, 1_048_576, "default body limit");
    assert!(
        config.cors_origins.is_empty(),
        "no browser origin by default"
    );
    assert_eq!(config.db_max_connections, 10, "default pool size");
    assert_eq!(
        config.db_acquire_timeout,
        Duration::from_secs(5),
        "default acquire timeout"
    );
    assert_eq!(
        config.shutdown_grace,
        Duration::from_secs(20),
        "default shutdown grace"
    );
}

#[test]
fn every_value_can_be_set() {
    let config = Config::from_lookup(lookup(&[
        URL,
        ("LISTEN_ADDR", "127.0.0.1:9000"),
        ("APP_ENV", "production"),
        ("REQUEST_TIMEOUT_MS", "250"),
        ("BODY_LIMIT_BYTES", "64"),
        (
            "CORS_ORIGINS",
            "https://app.example.com, ,https://admin.example.com",
        ),
        ("DB_MAX_CONNECTIONS", "3"),
        ("DB_ACQUIRE_TIMEOUT_MS", "100"),
        ("SHUTDOWN_GRACE_MS", "1000"),
    ]))
    .expect("complete");
    assert_eq!(
        config.listen.to_string(),
        "127.0.0.1:9000",
        "listen address"
    );
    assert!(config.production, "APP_ENV=production");
    assert_eq!(
        config.request_timeout,
        Duration::from_millis(250),
        "request timeout"
    );
    assert_eq!(config.body_limit_bytes, 64, "body limit");
    assert_eq!(
        config.cors_origins,
        ["https://app.example.com", "https://admin.example.com"],
        "origins trimmed, blanks dropped"
    );
    assert_eq!(config.db_max_connections, 3, "pool size");
    assert_eq!(
        config.db_acquire_timeout,
        Duration::from_millis(100),
        "acquire timeout"
    );
    assert_eq!(
        config.shutdown_grace,
        Duration::from_secs(1),
        "shutdown grace"
    );
}

#[test]
fn a_missing_database_url_is_named() {
    let error = Config::from_lookup(lookup(&[])).expect_err("DATABASE_URL is required");
    assert_eq!(
        error,
        ConfigError::Missing("DATABASE_URL"),
        "names the variable"
    );
    assert_eq!(
        error.to_string(),
        "environment variable DATABASE_URL is missing",
        "message"
    );
}

#[test]
fn a_value_that_does_not_parse_is_named_and_not_echoed() {
    for key in [
        "LISTEN_ADDR",
        "BODY_LIMIT_BYTES",
        "DB_MAX_CONNECTIONS",
        "REQUEST_TIMEOUT_MS",
    ] {
        let error = Config::from_lookup(lookup(&[URL, (key, "secret-value")])).expect_err(key);
        assert_eq!(error, ConfigError::Invalid(key), "names {key}");
        assert!(
            !error.to_string().contains("secret-value"),
            "never echoes the value"
        );
    }
}

#[test]
fn a_pool_below_three_connections_is_refused() {
    let error = Config::from_lookup(lookup(&[URL, ("DB_MAX_CONNECTIONS", "2")])).expect_err("2");
    assert_eq!(
        error,
        ConfigError::Invalid("DB_MAX_CONNECTIONS"),
        "names the variable"
    );
}

#[test]
fn from_env_reads_the_process_environment() {
    // The tests run with CI's variables (scripts/check/ci-env.sh), so DATABASE_URL is set or absent.
    match Config::from_env() {
        Ok(config) => assert!(!config.database_url.is_empty(), "a URL"),
        Err(error) => assert_eq!(error, ConfigError::Missing("DATABASE_URL"), "only the URL"),
    }
}
