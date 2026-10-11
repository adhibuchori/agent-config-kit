//! Database tier: each `#[sqlx::test]` gets its own database on the server `DATABASE_URL` names,
//! with migrations/ applied, and reaches it through the same router a client does (Rule 26).
#![cfg(test)]

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use service::{AppState, Config, app};
use sqlx::PgPool;
use tower::ServiceExt as _;

fn config() -> Config {
    Config::from_lookup(|key| (key == "DATABASE_URL").then(|| "postgres://unused".to_owned()))
        .expect("the test configuration is complete")
}

#[sqlx::test]
async fn ready_answers_when_the_database_does(pool: PgPool) {
    let state = AppState {
        pool,
        config: Arc::new(config()),
    };
    let request = Request::get("/api/ready")
        .body(Body::empty())
        .expect("request");
    let response = app(state).oneshot(request).await.expect("infallible");
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "the database answered SELECT 1"
    );
}
