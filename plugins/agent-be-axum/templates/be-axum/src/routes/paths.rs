//! The route registry (Rule 10): every path the service serves is spelled once, here, and named
//! by its handler's `#[utoipa::path(path = paths::...)]`.

pub(crate) const HEALTH: &str = "/api/health";
pub(crate) const READY: &str = "/api/ready";
