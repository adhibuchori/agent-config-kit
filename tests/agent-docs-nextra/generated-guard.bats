#!/usr/bin/env bats
# agent-docs-nextra's generated-guard hook, run the way Claude Code runs it: JSON on stdin, a block
# is exit 2 with the reason on stderr, and in plugin mode nothing happens until the project opts in.

load helpers

DOCS_PATHS='{"generatedPaths": ["content/technical", "content/changelog.mdx"]}'

setup() {
  SITE="$(dn_site)"
}

# --- The project gate (plugin mode) ---------------------------------------------------------------

@test "plugin mode: a project that has not opted in gets no hook, even for a generated page" {
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/openapi.json\"}")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "plugin mode: the lock alone opts in, and the default paths apply" {
  dn_opt_in_lock "$SITE"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/openapi.json\"}")"
  [[ "$stderr" == *"[generated-guard] BLOCKED: openapi.json is the API contract"* ]] || false
  [ -z "$output" ]
}

@test "plugin mode: agent-config.json alone opts in and names the docs generators' output" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/technical/api.mdx\"}")"
  [[ "$stderr" == *"[generated-guard] BLOCKED: content/technical/api.mdx is generated output (content/technical in generatedPaths)."* ]] || false
  [[ "$stderr" == *"run the project's generator"* ]] || false
}

@test "template mode: without CLAUDE_PLUGIN_ROOT the guard runs with no opt-in file" {
  run -2 --separate-stderr dn_guard_template_mode "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/openapi.json\"}")"
  [[ "$stderr" == *"BLOCKED"* ]] || false
}

# --- What it blocks and what it lets through -----------------------------------------------------

@test "blocks Write, Edit and MultiEdit on a generated page or file" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  local tool
  for tool in Write Edit MultiEdit; do
    run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload "$tool" "{\"file_path\": \"$SITE/content/changelog.mdx\"}")"
    [[ "$stderr" == *"content/changelog.mdx is generated output"* ]] || false
  done
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/technical/new/page.mdx\"}")"
}

@test "a relative file_path resolves against the call's cwd" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit '{"file_path": "technical/api.mdx"}' "$SITE/content")"
  [[ "$stderr" == *"content/technical/api.mdx is generated output"* ]] || false
}

@test "allows hand-written pages, look-alike names and files outside the project" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/index.mdx\"}")"
  [ "$status" -eq 0 ]
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/technical-notes.mdx\"}")"
  [ "$status" -eq 0 ]
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$BATS_TEST_TMPDIR/elsewhere/content/technical/x.mdx\"}")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "a generatedPaths list replaces the defaults whole" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/openapi.json\"}")"
  [ "$status" -eq 0 ]
}

@test "blocks Serena's single-file writes by relative_path" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_content '{"relative_path": "content/technical/api.mdx", "needle": "a", "repl": "b", "mode": "literal"}')"
  [[ "$stderr" == *"content/technical/api.mdx is generated output"* ]] || false
}

@test "Serena's replace_in_files: blocked when its scope reaches a generated page, allowed when it does not" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_in_files '{"relative_path": "content", "needle": "probeNeedle", "repl": "x", "mode": "literal"}')"
  [[ "$stderr" == *"this replace_in_files reaches generated output"* ]] || false
  run --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_in_files '{"relative_path": "content", "paths_exclude_glob": "content/technical/**", "needle": "probeNeedle", "repl": "x", "mode": "literal"}')"
  [ "$status" -eq 0 ]
  run --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_in_files '{"relative_path": "content", "needle": "probeNeedle", "repl": "x", "mode": "literal", "dry_run": true}')"
  [ "$status" -eq 0 ]
  run --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_in_files '{"relative_path": "content", "needle": "absentNeedle", "repl": "x", "mode": "literal"}')"
  [ "$status" -eq 0 ]
}

@test "the agent-config.json that setup seeds guards exactly the two generated surfaces" {
  mkdir -p "$SITE/.claude"
  cp "$DN_STACK/.claude/agent-config.json" "$SITE/.claude/agent-config.json"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/technical/api.mdx\"}")"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/changelog.mdx\"}")"
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/index.mdx\"}")"
  [ "$status" -eq 0 ]
}

# --- Error paths: the guard fails closed --------------------------------------------------------

@test "a payload that is not a JSON object is refused" {
  dn_opt_in_lock "$SITE"
  run -2 --separate-stderr dn_guard "$SITE" 'not json'
  [[ "$stderr" == *"[generated-guard] BLOCKED: this tool call's payload is not a JSON object"* ]] || false
  run -2 --separate-stderr dn_guard "$SITE" '["Write"]'
}

@test "with neither python3 nor jq the guard refuses instead of guarding nothing" {
  dn_opt_in_lock "$SITE"
  local nopath
  nopath="$(dn_path_without_readers)"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/index.mdx\"}")" PATH="$nopath"
  [[ "$stderr" == *"neither python3 nor jq is installed"* ]] || false
}

@test "jq without python3: file writes are still judged, and replace_in_files is refused" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  local jqonly
  jqonly="$(dn_path_with jq-only jq)"
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/changelog.mdx\"}")" PATH="$jqonly"
  [[ "$stderr" == *"content/changelog.mdx is generated output"* ]] || false
  run -0 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/index.mdx\"}")" PATH="$jqonly"
  # Its reach needs python3 to work out, so the guard refuses rather than guess.
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_in_files '{"relative_path": "content", "needle": "probeNeedle", "repl": "x", "mode": "literal"}')" PATH="$jqonly"
  [[ "$stderr" == *"checked by python3, which is not installed"* ]] || false
}

@test "a python3 that hangs is refused before the hooks.json timeout, not waited out" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  local hung limit start elapsed
  hung="$(dn_path_with hung jq)"
  dn_hung_python "$hung"
  limit="$(dn_hook_timeout)"
  # The real caps, not HOOK_PROBE_CAP: 3 s for the config read, then 5 s for the scope check. A hook
  # that outlasts its timeout is cancelled, and the tool call then goes ahead unchecked.
  start=$SECONDS
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload mcp__serena__replace_in_files '{"relative_path": "content", "needle": "probeNeedle", "repl": "x", "mode": "literal"}')" PATH="$hung"
  elapsed=$((SECONDS - start))
  [[ "$stderr" == *"did not finish (python3 failed or took over 5 s)"* ]] || false
  [ "$elapsed" -lt "$limit" ]
  # A plain write reads its config with jq once python3 gives up, and is judged as usual.
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Edit "{\"file_path\": \"$SITE/content/technical/api.mdx\"}")" PATH="$hung"
  [[ "$stderr" == *"content/technical/api.mdx is generated output"* ]] || false
}

@test "the gate still comes first: without readers and without opt-in, nothing is refused" {
  local nopath
  nopath="$(dn_path_without_readers)"
  run --separate-stderr dn_guard "$SITE" 'not json' PATH="$nopath"
  [ "$status" -eq 0 ]
}

@test "runs under /bin/bash 3.2 where the system has it" {
  [[ -x /bin/bash && "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" == 3 ]] || skip "no bash 3.2 at /bin/bash"
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  DN_BASH=/bin/bash run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/technical/api.mdx\"}")"
  DN_BASH=/bin/bash run --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/index.mdx\"}")"
  [ "$status" -eq 0 ]
}

# --- The wiring in hooks/hooks.json ---------------------------------------------------------------

@test "hooks.json wires the guard once, quoted, through bash, with a 10 s timeout" {
  run python3 - "$DN_PLUGIN/hooks/hooks.json" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
assert set(d["hooks"]) == {"PreToolUse"}, d["hooks"].keys()
entries = d["hooks"]["PreToolUse"]
assert len(entries) == 1
m = entries[0]["matcher"]
for tool in ("Write", "Edit", "MultiEdit", "mcp__serena__replace_in_files", "mcp__serena__replace_content"):
    assert re.fullmatch(m, tool), tool
for tool in ("Bash", "Read", "mcp__github__push_files"):
    assert not re.fullmatch(m, tool), tool
(h,) = entries[0]["hooks"]
assert h["type"] == "command" and h["timeout"] == 10 and isinstance(h["timeout"], int)
assert h["command"] == 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/generated-guard.sh"', h["command"]
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "the exact hooks.json command works from an install path that contains a space" {
  local root="$BATS_TEST_TMPDIR/plugin cache/agent-docs-nextra/1.0.0" cmd
  mkdir -p "$root"
  cp -R "$DN_PLUGIN/." "$root/"
  cmd="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$DN_PLUGIN/hooks/hooks.json")"
  # shellcheck disable=SC2016 # the literal text of the hooks.json command
  [[ "$cmd" == *'"${CLAUDE_PLUGIN_ROOT}/'* ]] || false
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run -2 --separate-stderr env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$SITE" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/plugin-data" \
    PAYLOAD="$(dn_payload Write "{\"file_path\": \"$SITE/content/changelog.mdx\"}")" \
    sh -c "printf '%s' \"\$PAYLOAD\" | $cmd"
  [[ "$stderr" == *"content/changelog.mdx is generated output"* ]] || false
}

@test "the exact hooks.json command also runs under dash, Ubuntu's sh" {
  local dash
  dash="$(command -v dash || true)"
  [[ -n "$dash" ]] || skip "dash is not installed"
  local cmd
  cmd="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$DN_PLUGIN/hooks/hooks.json")"
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  run -2 --separate-stderr env CLAUDE_PLUGIN_ROOT="$DN_PLUGIN" CLAUDE_PROJECT_DIR="$SITE" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/plugin-data" \
    PAYLOAD="$(dn_payload Write "{\"file_path\": \"$SITE/content/changelog.mdx\"}")" \
    "$dash" -c "printf '%s' \"\$PAYLOAD\" | $cmd"
  [[ "$stderr" == *"content/changelog.mdx is generated output"* ]] || false
  run -0 --separate-stderr env CLAUDE_PLUGIN_ROOT="$DN_PLUGIN" CLAUDE_PROJECT_DIR="$SITE" \
    CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/plugin-data" \
    PAYLOAD="$(dn_payload Write "{\"file_path\": \"$SITE/content/index.mdx\"}")" \
    "$dash" -c "printf '%s' \"\$PAYLOAD\" | $cmd"
}

@test "the plugin writes nothing under its own folder" {
  dn_opt_in_config "$SITE" "$DOCS_PATHS"
  touch "$BATS_TEST_TMPDIR/marker"
  sleep 1
  run -2 --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/changelog.mdx\"}")"
  run --separate-stderr dn_guard "$SITE" "$(dn_payload Write "{\"file_path\": \"$SITE/content/index.mdx\"}")"
  [ "$status" -eq 0 ]
  [ -z "$(find "$DN_PLUGIN" -newer "$BATS_TEST_TMPDIR/marker" -print)" ]
}

@test "lib.sh is the same bytes as agent-core's copy" {
  [[ -f "$DN_CORE/scripts/lib.sh" ]] || skip "agent-core's scripts/lib.sh is not built yet"
  cmp "$DN_PLUGIN/scripts/lib.sh" "$DN_CORE/scripts/lib.sh"
}
