#!/usr/bin/env bats
# The Python half of the payload contract (payload-encryption=yes): the seeded tests pass against
# the seeded implementation, at 100% branch coverage, and they read the same vectors as the
# TypeScript stacks. Runs through uv at pinned releases, or a python3 that already has them.

load helpers

setup() {
  ai_setup_env
  if command -v uv >/dev/null 2>&1; then
    PY=(uv run --quiet --no-project --with cryptography==50.0.1 --with pytest==9.1.1
      --with pytest-asyncio==1.4.0 --with pytest-cov==7.0.0 python3)
  elif python3 -c 'import cryptography, pytest, pytest_asyncio, pytest_cov' 2>/dev/null; then
    PY=(python3)
  else
    skip "neither uv nor a python3 with cryptography and pytest is available"
  fi
  REPO="$BATS_TEST_TMPDIR/svc"
  mkdir -p "$REPO/src/app/core" "$REPO/tests/unit/core" "$REPO/scripts/check"
  : >"$REPO/src/app/__init__.py"
  : >"$REPO/src/app/core/__init__.py"
  cp -R "$TPL/src/app/core/payload" "$REPO/src/app/core/"
  cp -R "$TPL/tests/unit/core/payload" "$REPO/tests/unit/core/"
  cp "$TPL/scripts/check/payload-vectors.json" "$REPO/scripts/check/"
}

# pytest_run [pytest args...]
pytest_run() {
  local n=${#PY[@]}
  run bash -c 'cd "$1" && shift && n="$1" && shift && PYTHONPATH=src "${@:1:n}" -m pytest tests -q \
    -p no:cacheprovider -o asyncio_mode=auto "${@:n+1}"' _ "$REPO" "$n" "${PY[@]}" "$@"
}

@test "payload (python): the seeded tests pass at 100% branch coverage" {
  pytest_run --cov=src/app --cov-branch --cov-fail-under=100
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed"* ]]
  [[ "$output" == *"Required test coverage of 100% reached"* ]]
}

@test "payload (python): an AAD builder that drifted fails the shared vectors" {
  python3 - "$REPO/src/app/core/payload/envelope.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("{method.upper()}", "{method.lower()}", 1)
open(p, "w").write(s)
PY
  pytest_run
  [ "$status" -ne 0 ]
  [[ "$output" == *"test_builds_the_same_aad_and_opens_the_ciphertext"* ]]
}
