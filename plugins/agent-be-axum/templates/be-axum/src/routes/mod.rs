//! Every route the service serves. A route enters only through `routes!` (Rule 10), so the router
//! and the `OpenAPI` document come from the same `#[utoipa::path]`. One `routes()` per domain,
//! merged here: a single function that registers every route outgrows clippy's limits.

mod health;
pub(crate) mod paths;

use utoipa::OpenApi;
use utoipa_axum::router::OpenApiRouter;

use crate::platform::error::Problem;
use crate::platform::state::AppState;

/// The document's shared part: the problem body, with the closed list of codes inline.
#[derive(OpenApi)]
#[openapi(components(schemas(Problem)))]
struct ApiDoc;

/// Every route, with the document that describes it.
pub(crate) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::with_openapi(ApiDoc::openapi()).merge(health::routes())
}
