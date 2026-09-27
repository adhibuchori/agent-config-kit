#!/usr/bin/env bats
# check:dockerfile (fe-nextjs and be-hono) and check:skeleton-pairs (the skeletons module), each
# proven both ways on a toy repo: what it must fail, what it must pass, and the skip it must say.

load helpers

setup() {
  if command -v bun >/dev/null 2>&1; then
    TS=(bun)
  elif node -e 'process.exit(process.features.typescript ? 0 : 1)' 2>/dev/null; then
    TS=(node --no-warnings --import "$KIT_ROOT/tests/helpers/ts-resolve.mjs")
  else
    skip "neither bun nor a node that strips TypeScript types is installed"
  fi
  REPO="$BATS_TEST_TMPDIR/app"
  mkdir -p "$REPO/scripts/check" "$REPO/src/lib"
  printf '{ "name": "toy", "private": true, "type": "module" }\n' >"$REPO/package.json"
  printf 'export const one = 1;\n' >"$REPO/src/lib/one.ts"
}

check() { run --separate-stderr bash -c 'cd "$1" && shift && "$@"' _ "$REPO" "${TS[@]}" "scripts/check/$1.ts"; }

# ── dockerfile ─────────────────────────────────────────────────────────────────────────────────

docker_repo() {
  cp "$STACK_DIR/scripts/check/dockerfile.ts" "$REPO/scripts/check/"
  mkdir -p "$REPO/src/hooks"
  printf "import { getNotes } from '@/lib/api/generated/notes';\nexport const use = getNotes;\n" \
    >"$REPO/src/hooks/useNotes.ts"
}

@test "dockerfile: the fe-nextjs and be-hono copies are the same file" {
  cmp "$STACK_DIR/scripts/check/dockerfile.ts" \
    "$KIT_ROOT/plugins/agent-be-hono/templates/be-hono/scripts/check/dockerfile.ts"
}

@test "dockerfile: generating the client before the build, with versioned pins, passes" {
  docker_repo
  printf 'FROM node:22.20-slim@sha256:%064d AS build\nRUN npm run generate:api\nRUN npm run build\n' 0 \
    >"$REPO/Dockerfile"
  check dockerfile
  [ "$status" -eq 0 ]
  [[ "$output" == *"the image builds what the gate validated"* ]]
}

@test "dockerfile: a generated client the image never generates, or generates after the build, fails" {
  docker_repo
  printf 'FROM node:22-slim\nRUN npm run build\n' >"$REPO/Dockerfile"
  check dockerfile
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"D1 1 file(s) import api/generated"* ]]
  printf 'FROM node:22-slim\nRUN npm run build\nRUN npm run generate:api\n' >"$REPO/Dockerfile"
  check dockerfile
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"generates the client after the build on line 2"* ]]
}

@test "dockerfile: a type-only import of the client does not count" {
  docker_repo
  printf "import type { Note } from '@/lib/api/generated/notes';\nexport type N = Note;\n" >"$REPO/src/hooks/useNotes.ts"
  printf 'FROM node:22-slim\nRUN npm run build\n' >"$REPO/Dockerfile"
  check dockerfile
  [ "$status" -eq 0 ]
}

@test "dockerfile: a digest pin whose tag names no version fails" {
  docker_repo
  rm "$REPO/src/hooks/useNotes.ts"
  printf 'FROM node:slim@sha256:%064d\n' 0 >"$REPO/Dockerfile"
  check dockerfile
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"D2 Dockerfile:1 pins node by digest with no version in the tag"* ]]
}

@test "dockerfile: no Dockerfile says so and passes; a Dockerfile with no source fails" {
  docker_repo
  check dockerfile
  [ "$status" -eq 0 ]
  [[ "$output" == *"No Dockerfile"* ]]
  rm -r "$REPO/src"
  printf 'FROM node:22-slim\n' >"$REPO/Dockerfile"
  check dockerfile
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"no source files under src/"* ]]
}

# ── skeleton-pairs ─────────────────────────────────────────────────────────────────────────────

skeleton_repo() {
  cp "$STACK_DIR/scripts/check/skeleton-pairs.ts" "$REPO/scripts/check/"
  mkdir -p "$REPO/src/components/notes" "$REPO/src/app/[locale]/dev/measure"
  printf 'export const NotesSkeleton = () => null;\n' >"$REPO/src/components/notes/notes-skeleton.tsx"
  printf "import { NotesSkeleton } from './notes-skeleton';\nexport const Notes = NotesSkeleton;\n" \
    >"$REPO/src/components/notes/notes-screen.tsx"
  printf '/* nothing registered yet */\nexport default function Page() { return null; }\n' \
    >"$REPO/src/app/[locale]/dev/measure/page.tsx"
}

@test "skeleton-pairs: a skeleton a screen renders and the harness never reaches fails" {
  skeleton_repo
  check skeleton-pairs
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"src/components/notes/notes-skeleton.tsx: rendered by src/components/notes/notes-screen.tsx"* ]]
}

@test "skeleton-pairs: a registered pair passes, and so does a listed one with a reason" {
  skeleton_repo
  printf "import { NotesSkeleton } from '@/components/notes/notes-skeleton';\nexport default function Page() { return NotesSkeleton; }\n" \
    >"$REPO/src/app/[locale]/dev/measure/page.tsx"
  check skeleton-pairs
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 paired"* ]]
}

@test "skeleton-pairs: the not-yet list needs a reason, and an entry that is paired now fails" {
  skeleton_repo
  mkdir -p "$REPO/scripts/measure"
  printf '[{ "path": "src/components/notes/notes-skeleton.tsx", "reason": "" }]\n' >"$REPO/scripts/measure/unmeasured-skeletons.json"
  check skeleton-pairs
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"has no reason"* ]]
  printf '[{ "path": "src/components/notes/notes-skeleton.tsx", "reason": "needs a signed-in fixture" }]\n' \
    >"$REPO/scripts/measure/unmeasured-skeletons.json"
  check skeleton-pairs
  [ "$status" -eq 0 ]
  printf "import { NotesSkeleton } from '@/components/notes/notes-skeleton';\nexport const x = NotesSkeleton;\n" \
    >"$REPO/src/app/[locale]/dev/measure/page.tsx"
  check skeleton-pairs
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is paired now; drop the entry"* ]]
}

@test "skeleton-pairs: no harness says so and passes, unless the measurer exists without it" {
  cp "$STACK_DIR/scripts/check/skeleton-pairs.ts" "$REPO/scripts/check/"
  check skeleton-pairs
  [ "$status" -eq 0 ]
  [[ "$output" == *"No measuring harness"* ]]
  mkdir -p "$REPO/scripts/measure" && : >"$REPO/scripts/measure/skeletons.ts"
  check skeleton-pairs
  [ "$status" -eq 1 ]
}
