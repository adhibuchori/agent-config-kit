//! The service as a library: `main.rs`, `bin/openapi.rs` and the tests build it through [`app`]
//! and [`openapi`]. This file only composes (Rule 1): routes from `routes`, layers from `platform`.

mod platform;
mod routes;

pub use platform::config::{Config, ConfigError};
pub use platform::db::pool;
pub use platform::error::{ProblemTypeBaseError, check_problem_type_base};
pub use platform::state::AppState;

/// The service: every registered route and its state, inside the layers.
pub fn app(state: AppState) -> axum::Router {
    let config = std::sync::Arc::clone(&state.config);
    let (router, _document) = routes::router().split_for_parts();
    platform::middleware::layers(router.with_state(state), &config)
}

/// The `OpenAPI` document, built from the same declarations as the router.
#[must_use]
pub fn openapi() -> utoipa::openapi::OpenApi {
    routes::router().into_openapi()
}
