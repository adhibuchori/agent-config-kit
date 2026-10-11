//! The payload contract at this service's edge (Rules 30 to 34; the wiring steps are in
//! `src/payload/mod.rs`): the handshake a public client agrees its key through, the `ENVELOPE_*`
//! codes in the document, the settings check `main.rs` runs, and [`seal`], which puts the layer
//! (`payload_layer.rs`) in front of every merged route.

#[path = "payload_layer.rs"]
mod layer;

use std::sync::Arc;

use axum::extract::Request;
use axum::http::StatusCode;
use axum::http::header::CACHE_CONTROL;
use axum::middleware::{Next, from_fn};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Json, Router};
use serde::Serialize;
use serde_json::Value;
use utoipa::openapi::{OpenApi, RefOr, Schema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;

use self::layer::{refuse, seal_with};
use super::paths;
use crate::payload::{
    Boundary, CONFIG_MODE, ENDPOINTS, Mode, PayloadCode, PayloadError, PayloadSetupError, Settings,
    WIRE_NAMES,
};
use crate::platform::config::Config;
use crate::platform::error::{ErrorCode, Problem, problem};
use crate::platform::state::AppState;

/// What a public client needs to agree a key.
#[derive(Debug, Serialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PayloadHandshake {
    /// Base64url of the service's uncompressed P-256 public key.
    public_key: String,
    /// The switch; a client treats anything but `off` as `strict`.
    #[schema(inline)]
    mode: Mode,
}

/// The handshake route, merged in `routes/mod.rs`.
pub(crate) fn routes() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(handshake))
}

#[utoipa::path(
    get,
    path = paths::PAYLOAD_HANDSHAKE,
    operation_id = "getPayloadHandshake",
    tag = "payload",
    responses(
        (status = 200, description = "The service's public key and the switch; never cached",
            body = PayloadHandshake),
        (status = 400, description = "The service holds no key pair (ENVELOPE_KEY_UNKNOWN)",
            body = Problem, content_type = "application/problem+json"),
    )
)]
async fn handshake(Extension(boundary): Extension<Arc<Boundary>>) -> Response {
    let Some(public_key) = boundary.public_key() else {
        let error = PayloadError::new(PayloadCode::KeyUnknown, "the handshake has no key pair");
        return refuse(StatusCode::BAD_REQUEST, paths::PAYLOAD_HANDSHAKE, error);
    };
    let mode = boundary.mode();
    let answer = PayloadHandshake { public_key, mode };
    ([(CACHE_CONTROL, "no-store")], Json(answer)).into_response()
}

/// Appends the `ENVELOPE_*` codes to the document's `Problem.code` list (Rule 34).
pub(crate) fn document(openapi: &mut OpenApi) {
    if let Some(components) = openapi.components.as_mut()
        && let Some(RefOr::T(Schema::Object(problem))) = components.schemas.get_mut("Problem")
        && let Some(RefOr::T(Schema::Object(code))) = problem.properties.get_mut("code")
    {
        let codes = code.enum_values.get_or_insert_with(Vec::new);
        codes.extend(WIRE_NAMES.map(Value::from));
    }
}

/// Refuses to start on payload settings that do not hold (`main.rs`).
///
/// # Errors
/// The switch, a key, the server key pair or the generated registry is refused.
pub fn check_payload_settings(config: &Config) -> Result<(), PayloadSetupError> {
    boundary(config).map(drop)
}

/// The boundary the configuration and the generated registry describe.
fn boundary(config: &Config) -> Result<Boundary, PayloadSetupError> {
    let keys = [
        ("PAYLOAD_KEY", config.payload_key.as_deref()),
        ("PAYLOAD_KEY_NEXT", config.payload_key_next.as_deref()),
    ];
    let mode = config.payload_mode.as_deref();
    let server_jwk = config.payload_server_jwk.as_deref();
    let production = config.production;
    let settings = Settings {
        mode,
        keys,
        server_jwk,
        production,
    };
    Boundary::new(&settings, ENDPOINTS, CONFIG_MODE)
}

/// Puts the boundary in front of every route the router holds, so call it once every route is
/// merged (`lib.rs`; a router with no route panics). Settings that do not hold, which `main.rs`
/// refuses to start on, answer every route with a 500.
pub(crate) fn seal(router: Router<AppState>, config: &Config) -> Router<AppState> {
    match boundary(config) {
        Ok(boundary) => seal_with(router, boundary),
        Err(error) => {
            tracing::error!(%error, "payload settings refused; every route answers 500");
            router.route_layer(from_fn(refuse_every_route))
        }
    }
}

/// What a service whose payload settings were refused answers.
async fn refuse_every_route(_request: Request, _next: Next) -> Response {
    problem(
        StatusCode::INTERNAL_SERVER_ERROR,
        ErrorCode::Internal,
        Vec::new(),
    )
}

#[cfg(test)]
#[path = "payload_tests.rs"]
mod tests;
