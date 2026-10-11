//! Rebuilds the crate when migrations/ changes. `sqlx::migrate!` and `#[sqlx::test]` embed the
//! migrations at compile time, and on a stable compiler nothing else tells cargo that a new file
//! there must reach the tests: without this line they keep running the old set. The line names the
//! folder only once it exists: cargo would rebuild on every call while it is missing.

use std::path::Path;

fn main() {
    if Path::new("migrations").is_dir() {
        println!("cargo::rerun-if-changed=migrations");
    }
}
