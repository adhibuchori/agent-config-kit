#!/usr/bin/env bash
# Foreign-key index gate (AGENTS.md §H Rule 32).
#
# Postgres creates an index for a PRIMARY KEY but NOT for a REFERENCES column,
# so an unindexed FK turns every join and every ON DELETE CASCADE into a
# sequential scan. This checks that each column carrying `.references(` also
# appears in an `index(`/`uniqueIndex(`/`primaryKey(` declaration in the same
# schema file, or carries a column-level `.unique()` or `.primaryKey()` —
# Postgres implements both constraints with an index, so such a column is
# already covered.
#
# Deliberately a heuristic: it reads the Drizzle schema source, not the
# database. It cannot see an index declared in a different file, and it does
# not judge composite index column order — that is the agent-be-hono:reviewer subagent's job.
# It exists to catch the one mistake that is both common and expensive.
set -euo pipefail
# From the repo root whatever the caller's directory: elsewhere the schema paths match nothing and
# the check would report "nothing to check" and pass.
cd "$(dirname "$0")/../.." || exit 2

SCHEMA_PATHS=("src/db/schema.ts" "src/db/schema")

FILES=()
for path in "${SCHEMA_PATHS[@]}"; do
  if [ -f "$path" ]; then
    FILES+=("$path")
  elif [ -d "$path" ]; then
    while IFS= read -r found; do
      FILES+=("$found")
    done < <(find "$path" -name '*.ts' -not -name 'index.ts')
  fi
done

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No Drizzle schema files found - nothing to check"
  exit 0
fi

FAILED=0

for file in "${FILES[@]}"; do
  # Track the property name most recently opened, then emit it when a
  # `.references(` shows up — a column definition may span several lines, so a
  # fixed context window would attribute the FK to the wrong property.
  while IFS=$'\t' read -r column is_indexed; do
    [ -z "$column" ] && continue

    # A column-level `.unique()` or `.primaryKey()` is already an index; a table-level one is
    # caught below.
    [ "$is_indexed" = "indexed" ] && continue

    if grep -qE "\.on\([^)]*\b${column}\b|columns:[^]]*\b${column}\b" "$file"; then
      continue
    fi

    echo "::error file=${file}::column '${column}' has .references() but no index in this file - Postgres does not index a REFERENCES column (AGENTS.md §H Rule 32)"
    FAILED=1
  done < <(awk '
    function flush(   ) {
      if (current != "" && buf ~ /\.references\(/)
        printf "%s\t%s\n", current, (buf ~ /\.(unique|primaryKey)\(\)/ ? "indexed" : "-")
      buf = ""
    }
    # A column definition spans several lines, so its whole block is buffered: `.unique()` or
    # `.primaryKey()` may sit either side of `.references(`, and a fixed window would attribute
    # either to the wrong column.
    match($0, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) {
      flush()
      current = $0
      sub(/^[[:space:]]*/, "", current)
      sub(/[[:space:]]*:.*$/, "", current)
    }
    { buf = buf $0 }
    END { flush() }
  ' "$file" | sort -u)
done

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Add an index for each foreign key column, e.g.:"
  echo "  (table) => [index(\"things_owner_idx\").on(table.ownerId)]"
  exit 1
fi

echo "✓ Every foreign key column has an index"
