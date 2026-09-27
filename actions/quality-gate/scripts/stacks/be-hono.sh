# shellcheck shell=bash
# be-hono (agent-be-hono): a Bun + Hono + Drizzle API. Sourced by gate.sh after lib.sh.
#
# gates.list (format, lint, types, dead code, mocks, tests with coverage), then the pull-request
# checks: the coverage floor, migration drift, index coverage, runtime hardening, a committed .env,
# the diff scans, gitleaks over the PR's commits, a changed skill, the OpenAPI spec drift (when the
# repo exports one), the production build and its source maps.

# The runtime rules agent-be-hono's AGENTS.md hands to this gate (Rules 17, 38, 39, 40, 41): read
# with comments stripped, so a commented-out middleware does not count.
be_hono_hardening() {
  qg_step "Runtime Hardening Check"
  local app=src/app.ts db=src/db/client/index.ts app_code db_code bad=0 mw setting
  if [ ! -f "$app" ] || [ ! -f "$db" ]; then
    qg_fail "Runtime Hardening Check reads $app and $db (agent-be-hono's layout); one is missing"
    return
  fi
  # Read into a variable first: `sed | grep -q` under pipefail turns grep's early exit into a miss.
  app_code=$(sed -E 's://.*$::' "$app" | sed -E '/^[[:space:]]*[*]/d; /^[[:space:]]*\/\*/d')
  db_code=$(sed -E 's://.*$::' "$db" | sed -E '/^[[:space:]]*[*]/d; /^[[:space:]]*\/\*/d')
  if grep -qE 'cors\([[:space:]]*\)' <<<"$app_code"; then
    echo "::error file=$app::a bare cors() sends Access-Control-Allow-Origin: *; pass an origin allowlist (Rule 39)"
    bad=1
  fi
  for mw in requestId secureHeaders bodyLimit timeout; do
    if ! grep -qF "${mw}(" <<<"$app_code"; then
      echo "::error file=$app::the ${mw} middleware is missing (Rules 40 and 41)"
      bad=1
    fi
  done
  if grep -qE 'max:[[:space:]]*[12]([^0-9]|$)' <<<"$db_code"; then
    echo "::error file=$db::a pool cap of 1 or 2 serializes every request (Rule 17)"
    bad=1
  fi
  for setting in statement_timeout idle_in_transaction_session_timeout; do
    if ! grep -qF "$setting" <<<"$db_code"; then
      echo "::error file=$db::$setting is not set (Rule 38)"
      bad=1
    fi
  done
  if [ "$bad" -ne 0 ]; then
    qg_fail "Runtime Hardening Check"
  else
    echo "Clean"
  fi
}

# openapi.json feeds the generated clients downstream. A generator that fails leaves the old file in
# place, and a spec never committed is invisible to `git diff`; both fail here.
be_hono_spec_drift() {
  qg_step "OpenAPI Spec Drift Check"
  if ! qg_has_script spec:export; then
    echo "package.json has no spec:export script; nothing to compare"
    return
  fi
  if ! qg_pm_run spec:export; then
    qg_fail "spec:export failed, so openapi.json was not regenerated"
  elif [ -n "$(git status --porcelain -- openapi.json)" ]; then
    git --no-pager diff -- openapi.json | head -40 | qg_quote
    qg_fail "openapi.json is stale or uncommitted: run spec:export and commit it"
  else
    echo "Clean"
  fi
}

be_hono_script() {
  local name="$1" script="$2"
  if [ -f "$script" ]; then
    qg_run "$name" bash "$script"
  else
    qg_step "$name"
    qg_skip "$name" "$script is missing: run /agent-be-hono:setup"
  fi
}

stack_gate() {
  qg_js_install || return 0
  qg_gates
  qg_coverage_floor
  be_hono_script "Migration Drift Check" scripts/check/migrations.sh
  be_hono_script "Index Coverage Check" scripts/check/index-coverage.sh
  be_hono_hardening
  qg_env_committed
  qg_js_scans
  qg_gitleaks
  qg_js_audit
  qg_skill_scan
  be_hono_spec_drift
  qg_build
  qg_source_maps dist
}
