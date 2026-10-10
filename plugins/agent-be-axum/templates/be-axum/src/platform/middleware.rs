//! The layers every request passes, outermost first (Rule 18). The order is the contract: the
//! request id exists before anything logs, and every bare error status becomes a problem body.

use axum::Router;
use axum::body::Body;
use axum::extract::Request;
use axum::http::header::CONTENT_TYPE;
use axum::http::{HeaderName, HeaderValue, Method, StatusCode};
use axum::middleware::{Next, from_fn};
use axum::response::Response;
use tower::ServiceBuilder;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

use super::config::Config;
use super::error::{ErrorCode, PROBLEM_JSON, REQUEST_ID, problem};

/// The header that carries the request id in and out.
const REQUEST_ID_HEADER: HeaderName = HeaderName::from_static("x-request-id");

/// Wraps the routed service in the layers, listed outermost first.
pub(crate) fn layers(router: Router, config: &Config) -> Router {
    let origins: Vec<HeaderValue> = config
        .cors_origins
        .iter()
        .filter_map(|origin| origin.parse().ok())
        .collect();
    router.layer(
        ServiceBuilder::new()
            .layer(from_fn(drop_untrusted_request_id))
            .layer(SetRequestIdLayer::new(REQUEST_ID_HEADER, MakeRequestUuid))
            .layer(TraceLayer::new_for_http().make_span_with(span_for))
            .layer(PropagateRequestIdLayer::new(REQUEST_ID_HEADER))
            .layer(from_fn(problems))
            .layer(CatchPanicLayer::new())
            .layer(
                CorsLayer::new()
                    .allow_origin(AllowOrigin::list(origins))
                    .allow_methods([
                        Method::GET,
                        Method::POST,
                        Method::PUT,
                        Method::PATCH,
                        Method::DELETE,
                    ])
                    .allow_headers([CONTENT_TYPE]),
            )
            .layer(RequestBodyLimitLayer::new(config.body_limit_bytes))
            .layer(TimeoutLayer::with_status_code(
                StatusCode::GATEWAY_TIMEOUT,
                config.request_timeout,
            )),
    )
}

/// A client may send its own `x-request-id`; one that is not a plain token is dropped, so a
/// fresh id replaces it before anything logs it.
async fn drop_untrusted_request_id(mut request: Request, next: Next) -> Response {
    let trusted = request
        .headers()
        .get(&REQUEST_ID_HEADER)
        .is_none_or(|value| is_plain_id(value.as_bytes()));
    if !trusted {
        request.headers_mut().remove(&REQUEST_ID_HEADER);
    }
    next.run(request).await
}

/// 1 to 64 letters, digits, `-`, `_` or `.`: safe to log and to echo.
fn is_plain_id(id: &[u8]) -> bool {
    (1..=64).contains(&id.len())
        && id
            .iter()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
}

/// The trace span every log line of the request carries, with the request id in it.
fn span_for(request: &Request<Body>) -> tracing::Span {
    let id = request
        .headers()
        .get(&REQUEST_ID_HEADER)
        .and_then(|value| value.to_str().ok());
    tracing::info_span!("request", method = %request.method(), path = %request.uri().path(), request_id = id)
}

/// Runs the request with its id in reach of [`problem`], and turns a bare error status from a
/// layer (no route, wrong method, body too large, timeout, panic) into a problem body.
async fn problems(request: Request, next: Next) -> Response {
    let id = request
        .headers()
        .get(&REQUEST_ID_HEADER)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_owned();
    let response = REQUEST_ID.scope(id.clone(), next.run(request)).await;
    let status = response.status();
    let is_problem = response
        .headers()
        .get(CONTENT_TYPE)
        .is_some_and(|value| value == PROBLEM_JSON);
    if is_problem || !(status.is_client_error() || status.is_server_error()) {
        return response;
    }
    REQUEST_ID.sync_scope(id, || problem(status, code_for(status), Vec::new()))
}

/// The registered code for a status a layer or a bare handler answered with.
fn code_for(status: StatusCode) -> ErrorCode {
    match status {
        StatusCode::NOT_FOUND => ErrorCode::RouteNotFound,
        StatusCode::METHOD_NOT_ALLOWED => ErrorCode::MethodNotAllowed,
        StatusCode::PAYLOAD_TOO_LARGE => ErrorCode::PayloadTooLarge,
        StatusCode::UNPROCESSABLE_ENTITY => ErrorCode::ValidationFailed,
        StatusCode::GATEWAY_TIMEOUT => ErrorCode::RequestTimeout,
        status if status.is_client_error() => ErrorCode::BadRequest,
        _ => ErrorCode::Internal,
    }
}

#[cfg(test)]
#[path = "middleware_tests.rs"]
mod tests;
