#!/usr/bin/env bats
# The shipped oxlint.json and .oxfmtrc.json against the real tools: the lint config loads (oxlint
# refuses an unknown rule name), fails a page with the problems it exists to catch, passes the same
# page written correctly, and the kit's own check scripts pass both tools, so a fresh setup starts
# with green format and lint gates. Needs oxlint and oxfmt: set FE_STATIC_TOOLS_BIN to a folder
# holding both (a node_modules/.bin), or have them on PATH; skipped otherwise.

load helpers

setup() {
  local dir="${FE_STATIC_TOOLS_BIN:-}"
  OXLINT="${dir:+$dir/oxlint}"
  OXFMT="${dir:+$dir/oxfmt}"
  [ -n "$OXLINT" ] || OXLINT="$(command -v oxlint || true)"
  [ -n "$OXFMT" ] || OXFMT="$(command -v oxfmt || true)"
  [ -x "$OXLINT" ] && [ -x "$OXFMT" ] || skip "oxlint and oxfmt not found (set FE_STATIC_TOOLS_BIN)"
  WORK="$BATS_TEST_TMPDIR/lint"
  mkdir -p "$WORK/app"
  cp "$TEMPLATES/oxlint.json" "$TEMPLATES/.oxfmtrc.json" "$WORK/"
  cd "$WORK" || return 1
}

@test "oxlint.json loads, and fails a page with every problem it is there to catch" {
  cat >app/page.tsx <<'TSX'
export default function Page() {
  return (
    <main>
      <img src="/hero.png" />
      <a href="javascript:void(0)">x</a>
      <a href="https://example.org" target="_blank">out</a>
      <div dangerouslySetInnerHTML={{ __html: '<b>x</b>' }} />
      <div onClick={() => {}}>click</div>
      <h2 />
      <iframe src="/x" />
    </main>
  );
}
TSX
  run -1 "$OXLINT" -c oxlint.json --format unix app
  for rule in 'next(no-img-element)' 'jsx-a11y(alt-text)' 'react(jsx-no-script-url)' 'react(jsx-no-target-blank)' \
    'react(no-danger)' 'jsx-a11y(click-events-have-key-events)' 'jsx-a11y(heading-has-content)' 'jsx-a11y(iframe-has-title)'; do
    [[ "$output" == *"Error/$rule"* ]] || false
  done
  [[ "$output" != *"Failed to parse oxlint configuration"* ]] || false
}

@test "oxlint.json passes the same page written correctly, JSON-LD as a script child included" {
  cat >app/page.tsx <<'TSX'
import Image from 'next/image';

const organization = { '@context': 'https://schema.org', '@type': 'Organization', name: 'Toy' };

export default function Page() {
  return (
    <main>
      <Image src="/hero.png" alt="A toy hero" width={10} height={10} />
      <a href="https://example.org" target="_blank" rel="noopener noreferrer">out</a>
      <h2>Title</h2>
      <iframe src="/x" title="Map" sandbox="" />
      <script type="application/ld+json">{JSON.stringify(organization).replace(/</g, '\\u003c')}</script>
    </main>
  );
}
TSX
  run -0 "$OXLINT" -c oxlint.json --deny-warnings app
}

@test "an unknown rule name makes oxlint refuse the config (so the test above proves every name)" {
  python3 - <<'PY'
import re
t = open("oxlint.json").read()
open("oxlint.json", "w").write(t.replace('"react/no-danger": "error"', '"react/no-danger-at-all": "error"'))
PY
  printf 'export const a = 1;\n' >app/a.ts
  run -1 "$OXLINT" -c oxlint.json app
  [[ "$output" == *"not found"* ]] || false
}

@test "the kit's check scripts pass the shipped format and lint configs" {
  mkdir -p scripts
  cp -R "$CHECKS" scripts/check
  run -0 "$OXFMT" --check scripts
  run -0 "$OXLINT" -c oxlint.json --deny-warnings scripts
}
