# shellcheck shell=bash
# ai-fastapi (agent-ai-fastapi): a FastAPI service on uv. Sourced by gate.sh after lib.sh.
#
# uv installs exactly uv.lock, then the repo's gates.list (ruff, mypy, import boundaries, vulture,
# deptry, pytest with coverage, the kit checks), then the pull-request checks: the coverage floor
# from coverage.py's data, a committed .env, gitleaks over the PR's commits, pip-audit when the repo
# lists it, a changed skill, the Docker build when there is a Dockerfile, and the integration tests
# when the caller turned them on.

ai_coverage_floor() {
  qg_step "Coverage Floor (${QG_COVERAGE_THRESHOLD}%)"
  if qg_threshold_off "$QG_COVERAGE_THRESHOLD"; then
    echo "coverage-threshold is 0: no floor (pyproject's fail_under still applies)"
    return
  fi
  if [ ! -f .coverage ]; then
    qg_skip "Coverage Floor" "no .coverage data: run pytest with --cov in scripts/check/gates.list, or pass coverage-threshold: 0"
    return
  fi
  env -u PYTHONPATH uv run --frozen coverage report --fail-under="$QG_COVERAGE_THRESHOLD"
  case $? in
  0) ;;
  2) qg_fail "coverage is below the ${QG_COVERAGE_THRESHOLD}% floor" ;;
  *) qg_fail "coverage report could not read .coverage" ;;
  esac
}

ai_audit() {
  qg_step "Security Audit (pip-audit)"
  if env -u PYTHONPATH uv run --frozen --no-sync pip-audit --version >/dev/null 2>&1; then
    env -u PYTHONPATH uv run --frozen --no-sync pip-audit --skip-editable ||
      qg_fail "pip-audit found a vulnerable dependency (or could not read the environment)"
  else
    echo "pip-audit is not a dev dependency here; dependency-review.yml checks the dependencies this pull request adds"
  fi
}

ai_docker_build() {
  qg_step "Production Build (docker build)"
  if [ ! -f Dockerfile ]; then
    echo "No Dockerfile; no image to build"
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    qg_skip "Production Build" "the runner has no docker"
    return
  fi
  docker build --pull=false -t quality-gate-build . || qg_fail "docker build failed"
}

ai_integration() {
  qg_step "Integration Tests"
  if [ "$QG_INTEGRATION_TESTS" != "true" ]; then
    echo "integration-tests is off; pass integration-tests: true with a DATABASE_URL secret that reaches a database"
    return
  fi
  RUN_INTEGRATION_TESTS=1 env -u PYTHONPATH uv run --frozen pytest tests -q -m integration
  local rc=$?
  # 5 is "no tests collected": nothing is marked integration yet.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ]; then
    qg_fail "Integration Tests failed"
  fi
}

stack_gate() {
  qg_run "Install Dependencies (uv sync --frozen)" env -u PYTHONPATH uv sync --frozen
  qg_gates
  ai_coverage_floor
  qg_env_committed
  qg_gitleaks
  ai_audit
  qg_skill_scan
  ai_docker_build
  ai_integration
}
