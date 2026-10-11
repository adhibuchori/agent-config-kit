//! Liveness and readiness. Liveness never touches the database; readiness asks it one question.

use axum::Json;
use axum::extract::State;
use serde::Serialize;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;

use super::paths;
use crate::platform::db;
use crate::platform::error::{AppError, Problem};
use crate::platform::state::AppState;

/// A probe's answer.
#[derive(Debug, Serialize, utoipa::ToSchema)]
pub(crate) struct Status {
    status: &'static str,
}

/// This domain's routes, merged in `routes/mod.rs`.
pub(super) fn routes() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(health))
        .routes(routes!(ready))
}

#[utoipa::path(
    get,
    path = paths::HEALTH,
    tag = "health",
    responses((status = 200, description = "The process is up", body = Status))
)]
async fn health() -> Json<Status> {
    Json(Status { status: "ok" })
}

#[utoipa::path(
    get,
    path = paths::READY,
    tag = "health",
    responses(
        (status = 200, description = "The database answers", body = Status),
        (status = 503, description = "The database does not answer", body = Problem,
            content_type = "application/problem+json"),
    )
)]
async fn ready(State(state): State<AppState>) -> Result<Json<Status>, AppError> {
    db::ping(&state.pool)
        .await
        .map_err(AppError::DatabaseUnavailable)?;
    Ok(Json(Status { status: "ready" }))
}
