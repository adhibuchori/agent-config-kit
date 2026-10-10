#!/usr/bin/env bats
# actions/quality-gate/scripts/pgbouncer.sh: the pinned image and its version check, the generated
# pgbouncer.ini and userlist, the wait for the port, and the container removed on every path. docker,
# psql and pg_isready are stubs; the real image ran against PostgreSQL 18.6 when the script was
# written, and runs in every be-go or be-axum gate with pgbouncer-tests on.

load helpers

PGB="$QG/pgbouncer.sh"

setup() {
  ci_isolate
  W="$BATS_TEST_TMPDIR/pgbouncer"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$STUBS"
  : >"$STUB_LOG"
  export STUBS STUB_LOG
  # docker: --version prints DOCKER_VERSION_LINE; run -d starts; inspect says DOCKER_RUNNING; logs
  # prints two lines. Every call is logged.
  cat >"$STUBS/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$STUB_LOG"
case "$1 $2" in
"run --rm") echo "${DOCKER_VERSION_LINE-PgBouncer 1.26.0}"; echo "libevent 2.1.13-stable" ;;
"run -d") echo "0123abcd" ; exit "${DOCKER_RUN_EXIT:-0}" ;;
"inspect -f") echo "${DOCKER_RUNNING:-true}" ;;
"logs --tail") echo "LOG process up: PgBouncer 1.26.0"; echo "LOG listening on 127.0.0.1:6432" ;;
esac
exit 0
EOF
  # psql: the login roles a CI database has after db/roles.sql.
  cat >"$STUBS/psql" <<'EOF'
#!/usr/bin/env bash
printf 'psql %s\n' "$*" >>"$STUB_LOG"
printf '%b' "${PSQL_ROLES-app_rw\nagent_ro\nwe\"ird\n}"
exit "${STUB_PSQL_EXIT:-0}"
EOF
  cat >"$STUBS/pg_isready" <<'EOF'
#!/usr/bin/env bash
printf 'pg_isready %s\n' "$*" >>"$STUB_LOG"
exit "${STUB_PG_ISREADY_EXIT:-0}"
EOF
  chmod +x "$STUBS/docker" "$STUBS/psql" "$STUBS/pg_isready"
  PATH="$STUBS:$PATH"
}

pgb() { # pgbouncer.sh with the work folder and a command
  run --separate-stderr bash "$PGB" "$W" "$@"
}

@test "pgbouncer: the image is pinned by digest, and its tag is the release the script checks" {
  local image version
  image=$(sed -n 's/^PGBOUNCER_IMAGE="\(.*\)"$/\1/p' "$PGB")
  version=$(sed -n 's/^PGBOUNCER_VERSION=//p' "$PGB")
  [ "$version" = 1.26.0 ]
  image="${image//\$\{PGBOUNCER_VERSION\}/$version}"
  [[ "$image" =~ ^ghcr\.io/cloudnative-pg/pgbouncer:1\.26\.0@sha256:[0-9a-f]{64}$ ]] || false
}

@test "pgbouncer: the config is transaction mode with a small pool, no ignored startup parameters" {
  QG_PGBOUNCER_MAX_PREPARED=0 pgb true
  [ "$status" -eq 0 ]
  grep -qx 'pool_mode = transaction' "$W/pgbouncer.ini"
  grep -qx 'default_pool_size = 2' "$W/pgbouncer.ini"
  grep -qx 'max_prepared_statements = 0' "$W/pgbouncer.ini"
  grep -qx 'listen_addr = 127.0.0.1' "$W/pgbouncer.ini"
  grep -qx 'listen_port = 6432' "$W/pgbouncer.ini"
  grep -qx '\* = host=127.0.0.1 port=5432' "$W/pgbouncer.ini"
  grep -qx 'auth_type = trust' "$W/pgbouncer.ini"
  run ! grep -q 'ignore_startup_parameters' "$W/pgbouncer.ini"
  pgb true
  grep -qx 'max_prepared_statements = 200' "$W/pgbouncer.ini"
}

@test "pgbouncer: the userlist holds the non-superuser login roles, with a double quote doubled" {
  pgb true
  [ "$status" -eq 0 ]
  grep -q 'rolcanlogin and not rolsuper' "$STUB_LOG"
  [ "$(cat "$W/userlist.txt")" = "$(printf '"app_rw" ""\n"agent_ro" ""\n"we""ird" ""')" ]
  [[ "$output" == *"3 login role(s)"* ]] || false
  # The image runs as its own user: the mounted folder must be readable by others.
  [ "$(find "$W" -maxdepth 0 -perm -o+rx | wc -l | tr -d ' ')" = 1 ]
  [ "$(find "$W/pgbouncer.ini" -perm -o+r | wc -l | tr -d ' ')" = 1 ]
}

@test "pgbouncer: it runs the image on the host network with the config mounted, then removes it" {
  pgb bash -c 'echo "behind the pooler" >>"$STUB_LOG"'
  [ "$status" -eq 0 ]
  local run_line
  run_line=$(grep -n '^docker run -d ' "$STUB_LOG")
  [[ "$run_line" == *"--network host -v $W:/etc/pgbouncer:ro ghcr.io/cloudnative-pg/pgbouncer:1.26.0@sha256:"*" /etc/pgbouncer/pgbouncer.ini" ]] || false
  # Order: the version check, the container, the wait, the command, the removal.
  [ "$(grep -n '^docker run --rm ' "$STUB_LOG" | cut -d: -f1)" -lt "${run_line%%:*}" ]
  [ "$(grep -n '^behind the pooler' "$STUB_LOG" | cut -d: -f1)" -gt "${run_line%%:*}" ]
  [ "$(grep -n '^docker rm -f qg-pgbouncer-' "$STUB_LOG" | cut -d: -f1)" -gt "$(grep -n '^behind the pooler' "$STUB_LOG" | cut -d: -f1)" ]
  grep -q '^pg_isready -q -h 127.0.0.1 -p 6432' "$STUB_LOG"
}

@test "pgbouncer: another release in the image fails before any container or test runs" {
  DOCKER_VERSION_LINE="PgBouncer 1.25.2" pgb touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reports 'PgBouncer 1.25.2', expected PgBouncer 1.26.0"* ]] || false
  run ! grep -q '^docker run -d' "$STUB_LOG"
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "pgbouncer: a port that never opens gives up, prints the log, and removes the container" {
  STUB_PG_ISREADY_EXIT=2 QG_PGBOUNCER_WAIT=2 pgb touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 3 ]
  [[ "$output" == *"PgBouncer did not answer on 127.0.0.1:6432"* ]] || false
  [[ "$output" == *"LOG listening on 127.0.0.1:6432"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  grep -q '^docker rm -f qg-pgbouncer-' "$STUB_LOG"
  [ "$(grep -c '^pg_isready ' "$STUB_LOG")" -eq 2 ]
}

@test "pgbouncer: a container that exits early stops the wait at once" {
  STUB_PG_ISREADY_EXIT=2 DOCKER_RUNNING=false QG_PGBOUNCER_WAIT=30 pgb true
  [ "$status" -eq 3 ]
  [ "$(grep -c '^pg_isready ' "$STUB_LOG")" -eq 1 ]
  grep -q '^docker rm -f qg-pgbouncer-' "$STUB_LOG"
}

@test "pgbouncer: a failing command fails with the log, and the container is still removed" {
  pgb false
  [ "$status" -eq 1 ]
  [[ "$output" == *"PgBouncer's last 40 log lines"* ]] || false
  grep -q '^docker rm -f qg-pgbouncer-' "$STUB_LOG"
}

@test "pgbouncer: no docker, unreadable roles or a bad max_prepared_statements stop it" {
  rm "$STUBS/docker"
  PATH="$(path_without docker)" pgb true
  [ "$status" -eq 3 ]
  [[ "$output" == *"this runner has no docker"* ]] || false
  setup
  STUB_PSQL_EXIT=2 pgb true
  [ "$status" -eq 3 ]
  run ! grep -q '^docker run -d' "$STUB_LOG"
  QG_PGBOUNCER_MAX_PREPARED=-1 pgb true
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$PGB" "$W"
  [ "$status" -eq 2 ]
}

@test "pgbouncer: a database with no login role warns that every client will be refused" {
  PSQL_ROLES='' pgb true
  [ "$status" -eq 0 ]
  [[ "$output" == *"no non-superuser login role"* ]] || false
  [ ! -s "$W/userlist.txt" ]
}
