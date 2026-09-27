# shellcheck shell=bash
# fe-nextjs (agent-fe-nextjs): a Next.js web app. Sourced by gate.sh after lib.sh.
#
# Install, then the API client when the repo generates one, then the repo's gates.list (format, lint,
# types, dead code, tests with coverage, the agent-fe-nextjs checks), then what only a pull request
# can check: the coverage floor, a committed .env, the diff scans, gitleaks over the PR's commits,
# the audit, a changed skill, the production build and its source maps.
stack_gate() {
  qg_js_install || return 0
  # The generated client is gitignored, so a fresh checkout has none until it is built; the type
  # check and the dead-code check both import it.
  if { [ -f orval.config.ts ] || [ -f orval.config.js ] || [ -f orval.config.mjs ]; } && qg_has_script generate:api; then
    qg_run "Generate API Client" qg_pm_run generate:api
  fi
  qg_gates
  qg_coverage_floor
  qg_env_committed
  qg_js_scans
  qg_gitleaks
  qg_js_audit
  qg_skill_scan
  qg_build
  qg_source_maps .next/static
}
