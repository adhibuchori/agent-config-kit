#!/usr/bin/env bash
# PgBouncer for the optional pooler check of be-go and be-axum (input pgbouncer-tests): starts the
# pinned image on 127.0.0.1:6432 in transaction mode, in front of the gate's PostgreSQL on
# 127.0.0.1:5432, runs one command while it is up, and always removes the container.
#
#   pgbouncer.sh <work-dir> <command...>
#
# The image is CloudNativePG's build of PgBouncer (Apache-2.0, from the PostgreSQL project's apt
# package), pinned by its multi-arch index digest, and it is used only if `pgbouncer --version` in it
# says the pinned release. Should CloudNativePG stop publishing, build the same release from the
# official tarball instead: https://www.pgbouncer.org/downloads/files/1.26.0/pgbouncer-1.26.0.tar.gz,
# sha256 afd25dd61ee6775d37b40629b87ce08736b3e6955f3057bb212e410fbf21c71d.
#
# pgbouncer.ini is written fresh into <work-dir> each run: every database name forwards to
# 127.0.0.1:5432; pool_mode = transaction; max_prepared_statements from QG_PGBOUNCER_MAX_PREPARED
# (default 200, PgBouncer's own default since 1.24; 0 copies a pooler that disables it);
# default_pool_size = 2, fewer server connections than client tasks, so clients share them. Auth is
# trust, and userlist.txt holds every non-superuser login role of the CI database (trust still needs
# the name listed), so no password exists anywhere. ignore_startup_parameters stays empty, as on a
# fresh install: a driver that sends a startup parameter PgBouncer refuses fails here as in
# production. Migrations never go through it (migrators hold session-level advisory locks).
#
# Reads QG_PG_ADMIN_URL (lib.sh), QG_PGBOUNCER_MAX_PREPARED and QG_PGBOUNCER_WAIT (seconds to wait
# for the port, default 30).
# Exit: the command's result (0 passed, 1 failed), 2 bad usage, 3 PgBouncer could not start (no
# docker, another release in the image, the roles could not be read, or the port never opened).
set -uo pipefail

QG_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$QG_HERE/lib.sh"

PGBOUNCER_VERSION=1.26.0
PGBOUNCER_IMAGE="ghcr.io/cloudnative-pg/pgbouncer:${PGBOUNCER_VERSION}@sha256:ce54f1133c509f1db8a8092c3f1c761d8c9292065ed6b6698786bb966da4dab9"
PORT=6432

if [ $# -lt 2 ]; then
  echo "usage: pgbouncer.sh <work-dir> <command...>" >&2
  exit 2
fi
work="$1"
shift
max="${QG_PGBOUNCER_MAX_PREPARED:-200}"
wait_s="${QG_PGBOUNCER_WAIT:-30}"
case "$max" in '' | *[!0-9]*)
  echo "::error::pgbouncer-max-prepared-statements must be a whole number of 0 or more (got '${max}')" >&2
  exit 2
  ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "::error::PgBouncer runs as a container, and this runner has no docker"
  exit 3
fi

# The pinned digest must hold the pinned release: a pasted wrong digest fails here, before any test.
said=$(docker run --rm "$PGBOUNCER_IMAGE" --version 2>&1 | head -1)
if [ "$said" != "PgBouncer $PGBOUNCER_VERSION" ]; then
  echo "::error::the pinned PgBouncer image reports '${said}', expected PgBouncer ${PGBOUNCER_VERSION}; refusing to use it"
  exit 3
fi

if ! roles=$(psql "$QG_PG_ADMIN_URL" -X -q -A -t -v ON_ERROR_STOP=1 \
  -c 'select rolname from pg_roles where rolcanlogin and not rolsuper order by 1'); then
  echo "::error::could not read the login roles of the CI database for PgBouncer's userlist"
  exit 3
fi
mkdir -p "$work" || exit 3
: >"$work/userlist.txt"
n=0
while IFS= read -r role; do
  [ -n "$role" ] || continue
  # userlist.txt quotes each name; a double quote inside one is written twice.
  printf '"%s" ""\n' "${role//\"/\"\"}" >>"$work/userlist.txt"
  n=$((n + 1))
done <<<"$roles"
[ "$n" -gt 0 ] || echo "::warning::the CI database has no non-superuser login role, so PgBouncer will refuse every client (db/roles.sql creates them)"

cat >"$work/pgbouncer.ini" <<EOF
[databases]
* = host=127.0.0.1 port=5432

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = ${PORT}
unix_socket_dir =
auth_type = trust
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_prepared_statements = ${max}
default_pool_size = 2
EOF
# The image runs as its own pgbouncer user, which must be able to read the mounted folder.
chmod 755 "$work" && chmod 644 "$work/pgbouncer.ini" "$work/userlist.txt"

name="qg-pgbouncer-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
show_log() {
  echo "PgBouncer's last 40 log lines:"
  docker logs --tail 40 "$name" 2>&1 | qg_quote
}

if ! docker run -d --name "$name" --network host -v "$work:/etc/pgbouncer:ro" \
  "$PGBOUNCER_IMAGE" /etc/pgbouncer/pgbouncer.ini >/dev/null; then
  echo "::error::the PgBouncer container did not start"
  exit 3
fi

# Up means the port answers; pg_isready counts any reply, even a refusal, as an answer.
answers() {
  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -q -h 127.0.0.1 -p "$PORT" -t 1
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null
  fi
}
up=0 waited=0
while [ "$waited" -lt "$wait_s" ]; do
  if answers; then
    up=1
    break
  fi
  # A container that already exited (a bad config) never opens the port.
  [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ] || break
  sleep 1
  waited=$((waited + 1))
done
if [ "$up" -ne 1 ]; then
  echo "::error::PgBouncer did not answer on 127.0.0.1:${PORT}"
  show_log
  exit 3
fi

echo "PgBouncer ${PGBOUNCER_VERSION} on 127.0.0.1:${PORT}: pool_mode transaction, max_prepared_statements ${max}, default_pool_size 2, ${n} login role(s)"
if "$@"; then
  exit 0
fi
show_log
exit 1
