//! The error contract (Rule 6, Rule 7). Every error a client sees carries an [`ErrorCode`], and
//! [`problem`] is the only place its RFC 9457 body is built.

use axum::http::header::{CONTENT_TYPE, RETRY_AFTER};
use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use serde::Serialize;

use super::extract::FieldProblem;

/// The base of every problem `type`: `type` = base + code. Set it once, to an https URL your team
/// owns, before the first release: changing it later breaks every client (Rule 7).
pub(crate) const PROBLEM_TYPE_BASE: &str = "https://example.invalid/problems/";

/// The problem body's media type (RFC 9457 §3).
pub(crate) const PROBLEM_JSON: &str = "application/problem+json";

/// How long a client waits before it retries a 503.
const RETRY_AFTER_SECONDS: &str = "5";

tokio::task_local! {
    /// The request's id, set by the layers for the request's whole task, read by [`problem`].
    pub(crate) static REQUEST_ID: String;
}

/// Every code a client can receive. A code missing here does not compile, and a code nothing
/// builds fails the build (`dead_code`), so this enum never derives `Deserialize` (Rule 6).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, utoipa::ToSchema)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(crate) enum ErrorCode {
    BadRequest,
    ValidationFailed,
    RouteNotFound,
    MethodNotAllowed,
    PayloadTooLarge,
    RequestTimeout,
    DatabaseUnavailable,
    Internal,
}

impl ErrorCode {
    /// The code as the wire spells it; a test holds it equal to the serialized form.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::BadRequest => "BAD_REQUEST",
            Self::ValidationFailed => "VALIDATION_FAILED",
            Self::RouteNotFound => "ROUTE_NOT_FOUND",
            Self::MethodNotAllowed => "METHOD_NOT_ALLOWED",
            Self::PayloadTooLarge => "PAYLOAD_TOO_LARGE",
            Self::RequestTimeout => "REQUEST_TIMEOUT",
            Self::DatabaseUnavailable => "DATABASE_UNAVAILABLE",
            Self::Internal => "INTERNAL",
        }
    }

    /// The problem type's title: one per code, the same for every occurrence (RFC 9457 §3.1.3).
    pub(crate) const fn title(self) -> &'static str {
        match self {
            Self::BadRequest => "Bad request",
            Self::ValidationFailed => "Request validation failed",
            Self::RouteNotFound => "No such route",
            Self::MethodNotAllowed => "Method not allowed",
            Self::PayloadTooLarge => "Request body too large",
            Self::RequestTimeout => "Request timed out",
            Self::DatabaseUnavailable => "Database unavailable",
            Self::Internal => "Internal error",
        }
    }

    /// This code's problem `type`: [`PROBLEM_TYPE_BASE`] followed by the code.
    pub(crate) fn type_uri(self) -> String {
        format!("{PROBLEM_TYPE_BASE}{}", self.as_str())
    }
}

/// `application/problem+json` (RFC 9457) with `code`, `requestId` and, on a 422, `fields`.
#[derive(Debug, Serialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Problem {
    /// The problem's identity: the problem-type base followed by `code` (RFC 9457 §3.1.1).
    #[serde(rename = "type")]
    #[schema(format = "uri", extensions(("x-problem-type-base" = json!(PROBLEM_TYPE_BASE))))]
    kind: String,
    title: &'static str,
    status: u16,
    // Inline: a client reads the closed list of codes where it reads the body.
    #[schema(inline)]
    code: ErrorCode,
    #[serde(skip_serializing_if = "Option::is_none")]
    request_id: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    fields: Vec<FieldProblem>,
}

/// The only builder of a problem body (Rule 7). `fields` names what was refused, never its value.
pub(crate) fn problem(status: StatusCode, code: ErrorCode, fields: Vec<FieldProblem>) -> Response {
    let body = Problem {
        kind: code.type_uri(),
        title: code.title(),
        status: status.as_u16(),
        code,
        request_id: REQUEST_ID.try_with(Clone::clone).ok(),
        fields,
    };
    let mut response = (status, axum::Json(body)).into_response();
    let headers = response.headers_mut();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static(PROBLEM_JSON));
    if status == StatusCode::SERVICE_UNAVAILABLE {
        headers.insert(RETRY_AFTER, HeaderValue::from_static(RETRY_AFTER_SECONDS));
    }
    response
}

/// Every error a handler returns. The message goes to the log; the client gets the code.
#[derive(Debug, thiserror::Error)]
pub(crate) enum AppError {
    #[error("the database did not answer: {0}")]
    DatabaseUnavailable(sqlx::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code) = match &self {
            Self::DatabaseUnavailable(_) => (
                StatusCode::SERVICE_UNAVAILABLE,
                ErrorCode::DatabaseUnavailable,
            ),
        };
        tracing::error!(error = %self, code = code.as_str(), "request failed");
        problem(status, code, Vec::new())
    }
}

/// Why the problem-type base is refused at startup.
#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum ProblemTypeBaseError {
    /// Not an absolute, normalized https URL ending in `/`, without query or fragment.
    #[error(
        "the problem-type base must be an absolute https URL ending in /, with no query or fragment"
    )]
    Malformed,
    /// Still the `.invalid` placeholder while `APP_ENV=production`.
    #[error("the problem-type base is still the .invalid placeholder; set PROBLEM_TYPE_BASE first")]
    Placeholder,
}

/// Refuses a malformed problem-type base, and the `.invalid` placeholder in production (Rule 7).
///
/// # Errors
/// The base is malformed, or still the placeholder while `production` is true.
pub fn check_problem_type_base(production: bool) -> Result<(), ProblemTypeBaseError> {
    check_base(PROBLEM_TYPE_BASE, production)
}

/// [`check_problem_type_base`] for any base, so the rules can be tested one by one.
pub(crate) fn check_base(base: &str, production: bool) -> Result<(), ProblemTypeBaseError> {
    let rest = base
        .strip_prefix("https://")
        .ok_or(ProblemTypeBaseError::Malformed)?;
    let (host, path) = rest
        .split_once('/')
        .ok_or(ProblemTypeBaseError::Malformed)?;
    let host_ok = !host.is_empty()
        && host
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'.' || b == b'-');
    let path_ok = base.ends_with('/')
        && !base.contains(['?', '#', '%', ' '])
        && !path.split('/').any(|segment| matches!(segment, "." | ".."))
        && !path.contains("//");
    if !(host_ok && path_ok) {
        return Err(ProblemTypeBaseError::Malformed);
    }
    if production && (host == "invalid" || host.ends_with(".invalid")) {
        return Err(ProblemTypeBaseError::Placeholder);
    }
    Ok(())
}

#[cfg(test)]
#[path = "error_tests.rs"]
mod tests;
