//! Writes the `OpenAPI` document to openapi.json at the crate root:
//! `cargo run --locked --quiet --bin openapi`. tests/api/openapi.rs fails while the committed file
//! differs from what the code declares, and the quality gate runs this and diffs the result.

use std::path::Path;
use std::process::ExitCode;

fn main() -> ExitCode {
    let Ok(json) = service::openapi().to_pretty_json() else {
        return ExitCode::FAILURE;
    };
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("openapi.json");
    match std::fs::write(path, json + "\n") {
        Ok(()) => ExitCode::SUCCESS,
        Err(_unwritable) => ExitCode::FAILURE,
    }
}
