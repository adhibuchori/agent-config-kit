#!/usr/bin/env bats
# check:i18n's missing-key detection, proven both ways. (check:soc needs the typescript package, so
# its frame-loop rule is proven in a project, not here.)

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
  mkdir -p "$REPO/scripts/check" "$REPO/src/messages" "$REPO/src/components/nav"
  printf '{ "name": "toy", "private": true, "type": "module" }\n' >"$REPO/package.json"
  cp "$STACK_DIR/scripts/check/i18n.ts" "$REPO/scripts/check/"
  printf '{ "nav": { "home": "Home", "about": "About" } }\n' >"$REPO/src/messages/en.json"
  cp "$REPO/src/messages/en.json" "$REPO/src/messages/id.json"
}

check() { run --separate-stderr bash -c 'cd "$1" && shift && "$@"' _ "$REPO" "${TS[@]}" "scripts/check/$1.ts"; }

@test "i18n: every literal key a scoped translator uses exists, so the check passes" {
  printf "const t = useTranslations('nav');\nexport const Nav = () => [t('home'), t('about')];\n" \
    >"$REPO/src/components/nav/nav.tsx"
  check i18n
  [ "$status" -eq 0 ]
  [[ "$output" == *"Every literal key a scoped translator uses exists in en.json"* ]]
}

@test "i18n: a key the namespace does not hold fails; a key built at runtime is listed, not failed" {
  printf "const t = useTranslations('nav');\nexport const Nav = (x: string) => [t('home'), t('about'), t('contact'), t(\`\${x}.label\`)];\n" \
    >"$REPO/src/components/nav/nav.tsx"
  check i18n
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"src/components/nav/nav.tsx: 'contact' is in none of 'nav'"* ]]
  [[ "$stderr" == *"Keys built at runtime, not checked (1)"* ]]
}
