#!/usr/bin/env bash
# Migration drift gate. Regenerates the migrations from the current schema (`bun run db:generate`,
# which reads drizzle.config.ts: schema under src/db/schema/, output in src/db/migrations/) and
# fails if the migrations directory then differs from what is committed, i.e. the schema changed
# but the generated migration was never run or committed.
set -euo pipefail
# From the repo root whatever the caller's directory, so git status reads the right folder.
cd "$(dirname "$0")/../.." || exit 2

MIGRATIONS_DIR="src/db/migrations"

echo "Generating migrations..."
if ! bun run db:generate; then
  echo "Error: Failed to generate migrations (schema syntax error?)"
  exit 1
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Error: Not in a git repository"
  exit 1
fi

STATUS=$(git status --porcelain "$MIGRATIONS_DIR/" 2>&1) || {
  echo "Error: git status failed"
  exit 1
}

if [ -n "$STATUS" ]; then
  echo "Error: Migrations are out of date!"
  echo ""
  echo "The following migration files need to be committed:"
  echo "$STATUS"
  echo ""

  echo "=== Migration file contents ==="
  echo "$STATUS" | while read -r line; do
    file=$(echo "$line" | awk '{print $2}')
    if [ -f "$file" ] && [[ "$file" == *.sql ]]; then
      echo ""
      echo "--- $file ---"
      cat "$file"
    fi
  done
  echo ""
  echo "==============================="
  echo ""
  echo "Run 'bun run db:generate' locally and commit the generated migrations."
  exit 1
fi

echo "✓ Migrations are up to date"
