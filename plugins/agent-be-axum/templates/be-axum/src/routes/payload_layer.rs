//! The payload layer, a `route_layer` over every merged route (Rules 30 and 31). It finds the
//! route through `MatchedPath`, opens a sealed request before any extractor runs, so `ValidJson`
//! and the handlers see plaintext, and seals the answer the route's policy names. A route the
//! registry lacks passes through. A refusal leaves in plaintext through `problem()` with an
//! `ENVELOPE_*` code; its reason goes to the log with the code and the route pattern, never a
//! body or a key (P10).

use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::extract::{MatchedPath, Request, State};
use axum::http::header::{CONTENT_LENGTH, CONTENT_TYPE, VARY};
use axum::http::{HeaderValue, StatusCode};
use axum::middleware::{Next, from_fn_with_state};
use axum::response::Response;

use crate::payload::{
    Boundary, EPK_HEADER, Exchange, KID_HEADER, PayloadCode, PayloadError, Route,
    SEALED_MEDIA_TYPE, now_millis,
};
use crate::platform::error::{ErrorCode, WireCode as _, problem};

/// A sealed answer depends on the key these request headers chose, so a shared cache keys on them
/// and never serves one caller's envelope to another.
const SEALED_VARY: &str = "x-payload-epk, x-payload-kid";

/// The layer over every route `router` holds, with a boundary already built.
pub(crate) fn seal_with<S>(router: Router<S>, boundary: Boundary) -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    router.route_layer(from_fn_with_state(Arc::new(boundary), guard))
}

/// The boundary for the handshake, then open, run, seal.
async fn guard(
    State(boundary): State<Arc<Boundary>>,
    mut request: Request,
    next: Next,
) -> Response {
    request.extensions_mut().insert(Arc::clone(&boundary));
    let method = request.method().as_str();
    let matched = request
        .extensions()
        .get::<MatchedPath>()
        .map(MatchedPath::as_str);
    let Some(route) = matched.and_then(|matched| boundary.matched_route(method, matched)) else {
        return next.run(request).await;
    };
    let keys = boundary.exchange(header(&request, EPK_HEADER), header(&request, KID_HEADER));
    let exchange = match keys {
        Ok(exchange) => exchange,
        Err(error) => return refuse(StatusCode::BAD_REQUEST, route.pattern, error),
    };
    if route.opens_request {
        request = match open(request, route, &exchange).await {
            Ok(request) => request,
            Err(refusal) => return *refusal,
        };
    }
    let response = next.run(request).await;
    if !route.seals_response {
        return response;
    }
    seal_answer(response, route, &exchange).await
}

/// A request header's value, when it is present, readable and not blank.
fn header<'a>(request: &'a Request, name: &str) -> Option<&'a str> {
    let value = request.headers().get(name)?.to_str().ok()?;
    (!value.trim().is_empty()).then_some(value)
}

/// The request with its sealed body replaced by the plaintext JSON; an empty body passes. A body
/// the limit cuts off answers 413, as `ValidJson` does.
async fn open(
    request: Request,
    route: Route,
    exchange: &Exchange<'_>,
) -> Result<Request, Box<Response>> {
    let (mut parts, body) = request.into_parts();
    let Ok(bytes) = axum::body::to_bytes(body, usize::MAX).await else {
        let too_large = problem(
            StatusCode::PAYLOAD_TOO_LARGE,
            ErrorCode::PayloadTooLarge,
            Vec::new(),
        );
        return Err(Box::new(too_large));
    };
    parts.headers.remove(CONTENT_LENGTH);
    if bytes.is_empty() {
        return Ok(Request::from_parts(parts, Body::empty()));
    }
    let media = parts
        .headers
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok());
    let (method, now) = (parts.method.as_str(), now_millis());
    let opened = exchange.open_request(
        method,
        route.pattern,
        media.unwrap_or_default(),
        &bytes,
        now,
    );
    let plaintext =
        opened.map_err(|error| Box::new(refuse(StatusCode::BAD_REQUEST, route.pattern, error)))?;
    let json = HeaderValue::from_static("application/json");
    parts.headers.insert(CONTENT_TYPE, json);
    Ok(Request::from_parts(parts, Body::from(plaintext)))
}

/// The answer sealed under the exchange's key and bound to its status; an empty body passes, and
/// one that cannot be sealed (not JSON, or unreadable) becomes a plaintext 500.
async fn seal_answer(response: Response, route: Route, exchange: &Exchange<'_>) -> Response {
    let status = response.status();
    let (mut parts, body) = response.into_parts();
    let bytes = match axum::body::to_bytes(body, usize::MAX).await {
        Ok(bytes) if bytes.is_empty() => return Response::from_parts(parts, Body::empty()),
        Ok(bytes) => bytes,
        Err(_unreadable) => {
            let error = PayloadError::new(PayloadCode::Malformed, "the answer could not be read");
            return refuse(StatusCode::INTERNAL_SERVER_ERROR, route.pattern, error);
        }
    };
    match exchange.seal_response(status.as_u16(), route.pattern, &bytes, now_millis()) {
        Ok(sealed) => {
            let headers = &mut parts.headers;
            headers.insert(CONTENT_TYPE, HeaderValue::from_static(SEALED_MEDIA_TYPE));
            headers.append(VARY, HeaderValue::from_static(SEALED_VARY));
            headers.remove(CONTENT_LENGTH);
            Response::from_parts(parts, Body::from(sealed))
        }
        Err(error) => refuse(StatusCode::INTERNAL_SERVER_ERROR, route.pattern, error),
    }
}

/// A plaintext refusal through `problem()`, logged with its code, pattern and reason.
pub(crate) fn refuse(status: StatusCode, pattern: &str, error: PayloadError) -> Response {
    let code = error.code.as_str();
    tracing::warn!(code, pattern, reason = error.reason, "payload refused");
    problem(status, error.code, Vec::new())
}

#[cfg(test)]
#[path = "payload_client_tests.rs"]
mod client;

#[cfg(test)]
#[path = "payload_layer_tests.rs"]
mod tests;
