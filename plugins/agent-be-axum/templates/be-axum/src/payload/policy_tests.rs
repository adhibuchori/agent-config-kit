use super::{Endpoint, Policy, find, first_inconsistent};
use crate::payload::{ENDPOINTS, Mode};

const NOTES: &[Endpoint] = &[
    Endpoint {
        method: "GET",
        route: "/api/notes/{id}",
        pattern: "/api/notes/:id",
        policy: Policy::Strict,
        reason: "",
    },
    Endpoint {
        method: "POST",
        route: "/api/notes",
        pattern: "/api/notes",
        policy: Policy::ResponseOnly,
        reason: "multipart",
    },
];

#[test]
fn each_policy_seals_the_sides_its_name_says() {
    let table = [
        (Policy::Strict, true, true),
        (Policy::ResponseOnly, false, true),
        (Policy::RequestOnly, true, false),
        (Policy::None, false, false),
    ];
    for (policy, request, response) in table {
        assert_eq!(policy.seals_request(), request, "{policy:?} request");
        assert_eq!(policy.seals_response(), response, "{policy:?} response");
        assert_eq!(
            policy.under(Mode::Strict),
            policy,
            "{policy:?} under strict"
        );
        assert_eq!(
            policy.under(Mode::Off),
            Policy::None,
            "{policy:?} under off"
        );
    }
}

#[test]
fn a_request_finds_its_entry_by_method_and_matched_route() {
    let found = find(NOTES, "GET", "/api/notes/{id}").expect("registered");
    assert_eq!(found.pattern, "/api/notes/:id", "the AAD form");
    assert!(
        find(NOTES, "DELETE", "/api/notes/{id}").is_none(),
        "another method"
    );
    assert!(
        find(NOTES, "GET", "/api/notes/:id").is_none(),
        "the AAD form is not a route"
    );
}

#[test]
fn a_registry_with_a_wrong_pattern_or_reason_names_its_entry() {
    assert!(first_inconsistent(NOTES).is_none(), "consistent");
    let broken: [&[Endpoint]; 3] = [
        &[Endpoint {
            method: "GET",
            route: "/api/a/{id}",
            pattern: "/api/a/{id}",
            policy: Policy::Strict,
            reason: "",
        }],
        &[Endpoint {
            method: "GET",
            route: "/api/a",
            pattern: "/api/a",
            policy: Policy::Strict,
            reason: "why",
        }],
        &[Endpoint {
            method: "GET",
            route: "/api/a",
            pattern: "/api/a",
            policy: Policy::None,
            reason: " ",
        }],
    ];
    for registry in broken {
        let entry = first_inconsistent(registry).expect("inconsistent");
        assert_eq!(entry.route, registry[0].route, "names the entry");
    }
}

#[test]
fn the_generated_registry_is_consistent() {
    assert!(
        first_inconsistent(ENDPOINTS).is_none(),
        "regenerate: node scripts/generate/payload-registry.mjs"
    );
}
