//! The contract: the committed openapi.json is what the code declares (Rule 10), and every
//! operation declares its errors the way clients read them (Rule 8).

use serde_json::Value;

const REGENERATE: &str = "cargo run --locked --quiet --bin openapi";

fn document() -> Value {
    serde_json::to_value(service::openapi()).expect("serializable")
}

#[test]
fn the_committed_openapi_json_is_current() {
    let generated = service::openapi().to_pretty_json().expect("serializable");
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/openapi.json");
    let committed = std::fs::read_to_string(path).expect(REGENERATE);
    assert_eq!(
        committed.trim_end(),
        generated.trim_end(),
        "openapi.json is stale: {REGENERATE}"
    );
}

/// Every operation in the document, labelled `<method> <path>`.
fn operations(document: &Value) -> Vec<(String, &Value)> {
    let paths = document["paths"].as_object().expect("paths");
    paths
        .iter()
        .flat_map(|(path, item)| {
            let methods = item.as_object().expect("a path item");
            methods
                .iter()
                .map(move |(method, operation)| (format!("{method} {path}"), operation))
        })
        .collect()
}

#[test]
fn every_response_is_described_and_every_error_is_a_problem() {
    let document = document();
    let operations = operations(&document);
    assert!(
        !operations.is_empty(),
        "the router declares at least one route"
    );
    for (label, operation) in operations {
        let responses = operation["responses"].as_object().expect("responses");
        let has_body = operation.get("requestBody").is_some();
        assert!(
            !has_body || responses.contains_key("422"),
            "{label}: a body needs a 422"
        );
        for (status, response) in responses {
            let described = response["description"]
                .as_str()
                .is_some_and(|d| !d.is_empty());
            assert!(described, "{label} {status}: a description");
            let is_error = status.starts_with('4') || status.starts_with('5');
            let is_problem = response["content"]["application/problem+json"].is_object();
            assert!(
                !is_error || is_problem,
                "{label} {status}: application/problem+json"
            );
        }
    }
}

#[test]
fn the_problem_schema_publishes_its_type_base_and_an_inline_code_list() {
    let document = document();
    let problem = &document["components"]["schemas"]["Problem"];
    let kind = &problem["properties"]["type"];
    assert_eq!(kind["format"], "uri", "type is a URI");
    let base = kind["x-problem-type-base"]
        .as_str()
        .expect("x-problem-type-base");
    assert!(
        base.starts_with("https://") && base.ends_with('/'),
        "an https base ending in /: {base}"
    );
    let required = problem["required"].as_array().expect("required");
    for member in ["type", "title", "status", "code"] {
        assert!(
            required.iter().any(|name| name == member),
            "{member} is required"
        );
    }
    let codes = problem["properties"]["code"]["enum"]
        .as_array()
        .expect("an inline code enum");
    assert!(!codes.is_empty(), "at least one code");
    for code in codes {
        let code = code.as_str().expect("a string");
        let shaped = code.starts_with(|c: char| c.is_ascii_uppercase())
            && code
                .bytes()
                .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_');
        assert!(shaped, "{code} matches ^[A-Z][A-Z0-9_]*$");
    }
}
