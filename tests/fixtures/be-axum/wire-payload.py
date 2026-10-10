"""The by-hand wiring steps that src/payload/mod.rs lists (2 to 5: config, path, routes, lib and
main), applied to a repo set up with payload-encryption=yes, for tests/agent-be-axum/payload.bats.
The crates (step 1) are added with cargo add by the caller.

    python3 tests/fixtures/be-axum/wire-payload.py <repo>
"""
import sys

root = sys.argv[1]


def edit(path, old, new, count=1):
    full = f"{root}/{path}"
    text = open(full, encoding="utf-8").read()
    if new in text:
        return
    assert text.count(old) == count, f"{path}: {old!r} found {text.count(old)} times"
    open(full, "w", encoding="utf-8").write(text.replace(old, new))


# 2. platform/config.rs: four fields, read from the environment.
edit("src/platform/config.rs",
     "    pub shutdown_grace: Duration,\n}",
     "    pub shutdown_grace: Duration,\n"
     "    /// `PAYLOAD_MODE`: `strict` or `off`; unset defers to payload.config.json (Rule 33).\n"
     "    pub payload_mode: Option<String>,\n"
     "    /// `PAYLOAD_KEY`: `kid:base64key` for server callers (Rule 32).\n"
     "    pub payload_key: Option<String>,\n"
     "    /// `PAYLOAD_KEY_NEXT`: the rotation slot beside `PAYLOAD_KEY`.\n"
     "    pub payload_key_next: Option<String>,\n"
     "    /// `PAYLOAD_SERVER_JWK`: the key pair public clients agree keys with.\n"
     "    pub payload_server_jwk: Option<String>,\n}")
edit("src/platform/config.rs",
     "            shutdown_grace: millis(get, \"SHUTDOWN_GRACE_MS\", 20_000)?,\n",
     "            shutdown_grace: millis(get, \"SHUTDOWN_GRACE_MS\", 20_000)?,\n"
     "            payload_mode: get(\"PAYLOAD_MODE\"),\n"
     "            payload_key: get(\"PAYLOAD_KEY\"),\n"
     "            payload_key_next: get(\"PAYLOAD_KEY_NEXT\"),\n"
     "            payload_server_jwk: get(\"PAYLOAD_SERVER_JWK\"),\n")

# 3. routes/paths.rs: the handshake's path.
edit("src/routes/paths.rs",
     'pub(crate) const READY: &str = "/api/ready";\n',
     'pub(crate) const READY: &str = "/api/ready";\n'
     'pub(crate) const PAYLOAD_HANDSHAKE: &str = "/api/payload/handshake";\n')

# 4. routes/mod.rs: the module, its routes, and the codes in the document.
edit("src/routes/mod.rs", "mod health;\npub(crate) mod paths;\n",
     "mod health;\npub(crate) mod paths;\npub(crate) mod payload;\n")
edit("src/routes/mod.rs",
     "    OpenApiRouter::with_openapi(ApiDoc::openapi()).merge(health::routes())\n}",
     "    let mut router = OpenApiRouter::with_openapi(ApiDoc::openapi())\n"
     "        .merge(health::routes())\n"
     "        .merge(payload::routes());\n"
     "    payload::document(router.get_openapi_mut());\n"
     "    router\n}")

# 5. lib.rs: the module, the exports, and the route_layer once every route is merged.
edit("src/lib.rs", "mod platform;\nmod routes;\n", "mod payload;\nmod platform;\nmod routes;\n")
edit("src/lib.rs", "pub use platform::config::{Config, ConfigError};\n",
     "pub use payload::PayloadSetupError;\npub use platform::config::{Config, ConfigError};\n")
edit("src/lib.rs", "pub use platform::state::AppState;\n",
     "pub use platform::state::AppState;\npub use routes::payload::check_payload_settings;\n")
edit("src/lib.rs",
     "    let (router, _document) = routes::router().split_for_parts();\n",
     "    let (router, _document) = routes::router().split_for_parts();\n"
     "    let router = routes::payload::seal(router, &config);\n")

# 5. main.rs: refuse to start on payload settings that do not hold.
edit("src/main.rs", "use service::{AppState, Config, app, check_problem_type_base, pool};",
     "use service::{AppState, Config, app, check_payload_settings, check_problem_type_base, pool};")
edit("src/main.rs", "    check_problem_type_base(config.production)?;\n",
     "    check_problem_type_base(config.production)?;\n    check_payload_settings(&config)?;\n")
print("wired", root)
