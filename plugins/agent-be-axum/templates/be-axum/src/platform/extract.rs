//! `ValidJson<T>`: the one way a handler reads a JSON body (Rule 7). Its 422 names the field and
//! never echoes the submitted value, which axum's own `Json` rejection does.

use axum::body::Bytes;
use axum::extract::{FromRequest, Request};
use axum::http::StatusCode;
use axum::http::header::CONTENT_TYPE;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use serde::de::DeserializeOwned;

use super::error::{ErrorCode, problem};

/// Why one field was refused: a code from this closed list, never the value that was sent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, utoipa::ToSchema)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub(crate) enum FieldCode {
    Invalid,
}

/// One refused field of a 422: its path in the body (`items[2].name`) and why.
#[derive(Debug, Serialize, utoipa::ToSchema)]
pub(crate) struct FieldProblem {
    pub(crate) field: String,
    pub(crate) code: FieldCode,
}

/// A JSON request body of type `T`. Request types carry `#[serde(deny_unknown_fields)]`.
pub(crate) struct ValidJson<T>(pub(crate) T);

/// A body `ValidJson` refused: over the size limit, or not the JSON `T` describes.
#[derive(Debug)]
pub(crate) enum BodyRejection {
    TooLarge,
    Field(String),
}

impl IntoResponse for BodyRejection {
    fn into_response(self) -> Response {
        match self {
            Self::TooLarge => problem(
                StatusCode::PAYLOAD_TOO_LARGE,
                ErrorCode::PayloadTooLarge,
                Vec::new(),
            ),
            Self::Field(field) => problem(
                StatusCode::UNPROCESSABLE_ENTITY,
                ErrorCode::ValidationFailed,
                vec![FieldProblem {
                    field,
                    code: FieldCode::Invalid,
                }],
            ),
        }
    }
}

impl<S: Send + Sync, T: DeserializeOwned> FromRequest<S> for ValidJson<T> {
    type Rejection = BodyRejection;

    async fn from_request(request: Request, state: &S) -> Result<Self, BodyRejection> {
        let is_json = request
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .is_some_and(|value| value.starts_with("application/json"));
        if !is_json {
            return Err(BodyRejection::Field("$body".to_owned()));
        }
        let bytes = Bytes::from_request(request, state)
            .await
            .map_err(|_over_limit| BodyRejection::TooLarge)?;
        let mut json = serde_json::Deserializer::from_slice(&bytes);
        let value = serde_path_to_error::deserialize(&mut json)
            .map_err(|error| BodyRejection::Field(error.path().to_string()))?;
        json.end()
            .map_err(|_trailing| BodyRejection::Field("$body".to_owned()))?;
        Ok(Self(value))
    }
}

#[cfg(test)]
#[path = "extract_tests.rs"]
mod tests;
