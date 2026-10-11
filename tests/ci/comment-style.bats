#!/usr/bin/env bats
# scripts/check-comment-style.mjs: JavaScript and TypeScript comments are block comments, `//` is
# kept for tool directives, and --fix rewrites the rest without changing what the code does.
# shellcheck disable=SC2016 # the expected output holds literal backticks

load helpers

setup() {
  ci_isolate
  need_node
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R"
  git -C "$R" init -q -b main
}

style() { node "$KIT_ROOT/scripts/check-comment-style.mjs" --root "$R" "$@"; }
track() { git -C "$R" add -A; }

@test "a stray // comment fails, named by file and line" {
  printf 'const a = 1;\n// a note\nexport { a };\n' >"$R/a.mjs" && track
  run -1 style
  [[ "$output" == *'a.mjs:2 — stray `//` comment: // a note'* ]] || false
}

@test "block comments, directives and // inside strings, templates and regexes pass" {
  cat >"$R/ok.ts" <<'EOF'
/** A file header. */
// @ts-expect-error a directive the compiler reads
const url = 'https://example.invalid/a';
const tpl = `see //${url}// here`;
const re = /https?:\/\/[^/]+/;
/* A note. */
// oxlint-disable-next-line no-console
console.log(url, tpl, re);
EOF
  printf '/// <reference types="node" />\nexport const x = 1;\n' >"$R/ref.ts" && track
  run -0 style
  [[ "$output" == *"2 file(s), no stray"* ]] || false
}

@test "--fix makes a header and a declaration note /** */, other notes /* */, and the code still runs" {
  cat >"$R/fix.mjs" <<'EOF'
#!/usr/bin/env node
// What this file does,
// in two lines.
import { strictEqual } from 'node:assert';

// The answer.
export function answer() {
  // An inner note.
  return 42; // a trailing note
}
strictEqual(answer(), 42);
EOF
  track
  run -0 style --fix
  [[ "$output" == *"rewrote 1 file(s)"* ]] || false
  run -0 cat "$R/fix.mjs"
  [[ "$output" == *$'/**\n * What this file does,\n * in two lines.\n */'* ]] || false
  [[ "$output" == *$'/**\n * The answer.\n */\nexport function'* ]] || false
  [[ "$output" == *'  /* An inner note. */'* ]] || false
  [[ "$output" == *'return 42; /* a trailing note */'* ]] || false
  run -0 node "$R/fix.mjs"
  run -0 style
}

@test "--fix leaves a run whose line holds */ whole, and reports it" {
  printf '// files under\n// plugins/*/bin are executable\nexport const a = 1;\n' >"$R/b.mjs" && track
  cp "$R/b.mjs" "$R/b.orig"
  run -1 style --fix
  [[ "$output" == *'b.mjs:2 — holds "*/", rewrite it by hand'* ]] || false
  run -0 cmp "$R/b.mjs" "$R/b.orig"
}

@test "installed packages and generated files are not read" {
  mkdir -p "$R/node_modules/x" "$R/src/generated"
  printf '// vendor\n' >"$R/node_modules/x/i.js"
  printf '// generated\n' >"$R/src/generated/api.ts"
  printf '// generated\n' >"$R/src/endpoints.generated.ts"
  printf '/** Ours. */\nexport const a = 1;\n' >"$R/src/a.ts"
  git -C "$R" add -f -A
  run -0 style
  [[ "$output" == *"1 file(s), no stray"* ]] || false
}

@test "a checkout with no JavaScript or TypeScript file is bad usage, not a pass" {
  printf 'x\n' >"$R/README.md" && track
  run -2 style
  [[ "$output" == *"no JavaScript or TypeScript file found"* ]] || false
}
