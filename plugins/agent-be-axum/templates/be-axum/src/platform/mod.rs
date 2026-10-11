//! What every domain stands on: configuration, the pool, the error contract, the JSON extractor
//! and the layers. Nothing here names a domain or a route (Rule 2).

pub(crate) mod config;
pub(crate) mod db;
pub(crate) mod error;
#[cfg_attr(
    not(test),
    expect(
        dead_code,
        reason = "no route reads a JSON body yet: delete this attribute with the first one"
    )
)]
pub(crate) mod extract;
pub(crate) mod middleware;
pub(crate) mod state;
