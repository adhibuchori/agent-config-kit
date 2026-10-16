# shellcheck shell=bash
# ios-swiftui (agent-ios-swiftui): a SwiftUI app with its logic in Packages/AppCore. Sourced by
# gate.sh after lib.sh.
#
# The gate runs in two jobs (QG_PHASE), so a failure that needs no Mac costs Linux minutes only:
#   static  Linux: the gates.list lines whose command starts with an IOS_LINUX_GATES entry, exactly
#           as written, then the pull-request checks: a committed .env, gitleaks over the PR's
#           commits, a changed skill. Every other gates.list line, SwiftLint's included, is printed
#           as running in the macOS job.
#   build   macOS, after the static job passed: Xcode must be the pinned release; the whole
#           gates.list; the coverage floor from coverage/lcov.info; xcodebuild test on the newest iOS
#           simulator (unit and UI tests, the accessibility audits among them) with zero build
#           warnings; the string-catalog checks that need a build (I3, I4); Periphery; the API client
#           regenerated with no diff.
#   all     both, in that order (a Mac by hand: QG_STACK=ios-swiftui bash gate.sh).

# The gates.list commands that need no Mac: node and bash checks. Not swiftlint: swiftlint-static
# aborts ("SourceKit is disabled by configuration") on any custom rule a file triggers, even in
# swiftsyntax mode, so SwiftLint runs on macOS with the rest of the list. A line runs on Linux only
# when its command is one of these or starts with one and a space, so flags added to a line still
# match and an unknown line never runs there.
IOS_LINUX_GATES=(
  'node scripts/check/i18n-catalog.mjs'
  'node scripts/check/folder-shape.mjs'
  'node scripts/check/coverage-policy.mjs'
  'node scripts/check/payload-registry.mjs'
  'bash scripts/check/lint-suppressions.sh'
  'bash scripts/check/error-codes.sh'
  'bash scripts/check/privacy-manifest.sh'
  'bash scripts/check/secrets.sh'
  'bash scripts/check/ai-config.sh'
)

ios_linux_gate() { # $1 a gates.list command
  local e
  for e in "${IOS_LINUX_GATES[@]}"; do
    case "$1" in "$e" | "$e "*) return 0 ;; esac
  done
  return 1
}

ios_static_gates() {
  local kinds cmd later="" n=0
  qg_step "Repo Gates, the Linux part (scripts/check/gates.list)"
  if [ ! -f scripts/check/gates.list ]; then
    qg_skip "Repo Gates" "scripts/check/gates.list is missing: run /agent-core:setup and /agent-ios-swiftui:setup"
    return
  fi
  while IFS=$'\t' read -r kinds cmd || [ -n "${kinds:-}" ]; do
    case "$kinds" in '' | '#'*) continue ;; esac
    if [ -z "$cmd" ]; then
      qg_fail "scripts/check/gates.list has a line without a TAB-separated command"
      continue
    fi
    if ios_linux_gate "$cmd"; then
      # </dev/null: the loop reads gates.list on stdin, and a gate that reads stdin would eat it.
      qg_run "$cmd" bash -c "$cmd" </dev/null
      n=$((n + 1))
    else
      later="${later}  ${cmd}"$'\n'
    fi
  done <scripts/check/gates.list
  qg_step "Repo Gates for the macOS job"
  echo "$n gates.list line(s) ran here. The macOS job runs the whole list, so these run there:"
  if [ -n "$later" ]; then
    printf '%s' "$later" | qg_quote
  else
    echo "  (none)"
  fi
}

# The Xcode the workflow selected (DEVELOPER_DIR) must be the release the caller pinned: a runner
# image that moved its default never changes the compiler under the gate.
ios_xcode() {
  local first
  qg_step "Xcode ${QG_XCODE_VERSION:-(any)}"
  if ! command -v xcodebuild >/dev/null 2>&1; then
    qg_fail "the build phase needs macOS with Xcode, and this runner has no xcodebuild"
    return 1
  fi
  first=$(xcodebuild -version 2>&1 | head -1)
  echo "$first (DEVELOPER_DIR=${DEVELOPER_DIR:-unset})"
  if [ -n "${QG_XCODE_VERSION:-}" ] && [ "$first" != "Xcode ${QG_XCODE_VERSION}" ]; then
    qg_fail "the runner's Xcode is '${first}', not the pinned Xcode ${QG_XCODE_VERSION}: install it, or change xcode-version"
    return 1
  fi
}

# The simulator: the first iPhone of the newest iOS runtime installed, by its UDID (device names
# differ between runner images).
ios_simulator() {
  xcrun simctl list devices available -j | node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const ver = (k) => (k.match(/SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$/) || []).slice(1).map((n) => Number(n || 0));
      const runtimes = Object.entries(JSON.parse(s).devices || {})
        .filter(([k]) => ver(k).length)
        .sort(([a], [b]) => { const x = ver(a), y = ver(b); return y[0] - x[0] || y[1] - x[1] || y[2] - x[2]; });
      for (const [, devices] of runtimes) {
        const phone = devices.find((d) => d.isAvailable !== false && /^iPhone/.test(d.name));
        if (phone) { console.log(phone.udid); return; }
      }
      process.exit(1);
    });'
}

ios_build_test() {
  local name="Build and Test (xcodebuild test, zero warnings)" projs=() p proj scheme udid out
  IOS_BUILT=0
  qg_step "$name"
  for p in *.xcodeproj; do
    [ -d "$p" ] && projs+=("$p")
  done
  if [ ${#projs[@]} -ne 1 ]; then
    qg_skip "$name" "the repository root holds ${#projs[@]} .xcodeproj folders; the build needs exactly one"
    return
  fi
  proj="${projs[0]}"
  scheme="${QG_IOS_SCHEME:-$(basename "$proj" .xcodeproj)}"
  if ! udid=$(ios_simulator); then
    qg_skip "$name" "no available iPhone simulator on this runner"
    return
  fi
  out="$QG_TMP/ios"
  rm -rf "$out" && mkdir -p "$out"
  # Never -retry-tests-on-failure: a test that passes on the second try is a failing test.
  if ! xcodebuild test -project "$proj" -scheme "$scheme" -destination "id=$udid" \
    -derivedDataPath "$out/DerivedData" -resultBundlePath "$out/test.xcresult" \
    -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=YES; then
    qg_fail "xcodebuild test failed (scheme $scheme, simulator $udid)"
    return
  fi
  IOS_BUILT=1
  # The warning count of the build, read from the result bundle: one warning fails the gate.
  if ! xcrun xcresulttool get build-results --path "$out/test.xcresult" --compact >"$out/build.json"; then
    qg_fail "xcresulttool could not read the build results"
    return
  fi
  # shellcheck disable=SC2016 # JavaScript, not shell
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const n = r.warningCount ?? (r.warnings || []).length;
    for (const w of (r.warnings || []).slice(0, 20)) console.log(`  ${w.sourceURL || w.targetName || ""}: ${w.message}`);
    console.log(`${n} build warning(s)`);
    process.exit(n > 0 ? 1 : 0);
  ' "$out/build.json" | qg_quote
  [ "${PIPESTATUS[0]}" -eq 0 ] || qg_fail "the build has warnings; the gate allows none"
}

# I3 and I4: every key the code uses is in the catalog and no key is stale. They need the
# .stringsdata files the build wrote, so they run here; I1, I2 and I5 run in gates.list.
ios_strings_built() {
  local name="String Catalog Check, built (I3, I4)"
  qg_step "$name"
  if [ ! -f scripts/check/i18n-catalog.mjs ]; then
    qg_skip "$name" "scripts/check/i18n-catalog.mjs is missing: run /agent-ios-swiftui:setup"
    return
  fi
  if [ "${IOS_BUILT:-0}" -ne 1 ]; then
    qg_skip "$name" "the build did not finish"
    return
  fi
  node scripts/check/i18n-catalog.mjs --stringsdata "$QG_TMP/ios/DerivedData" ||
    qg_fail "the string catalog is missing a key the code uses, or keeps one it no longer uses"
}

# Periphery reads the index the test build wrote, so it builds nothing again; .periphery.yml names
# the project and schemes.
ios_periphery() {
  local name="Dead Code (periphery scan --strict)"
  qg_step "$name"
  if [ ! -f .periphery.yml ]; then
    qg_skip "$name" ".periphery.yml is missing: run /agent-ios-swiftui:setup"
    return
  fi
  if ! command -v periphery >/dev/null 2>&1; then
    qg_skip "$name" "periphery is not installed on this runner"
    return
  fi
  if [ "${IOS_BUILT:-0}" -ne 1 ]; then
    qg_skip "$name" "the build did not finish"
    return
  fi
  periphery scan --strict --disable-update-check \
    --index-store-path "$QG_TMP/ios/DerivedData/Index.noindex/DataStore" ||
    qg_fail "Periphery found unused code"
}

# The generated API client is committed; regenerating it from the committed openapi.json must change
# nothing (swift-openapi-generator's command plugin, at the version Package.resolved pins).
ios_client_drift() {
  local pkg=Packages/AppCore src=Packages/AppCore/Sources/APIClient
  qg_step "API Client Drift (regenerate, then compare)"
  if [ ! -f "$src/openapi-generator-config.yaml" ]; then
    echo "No $src/openapi-generator-config.yaml; this app generates no API client"
    return
  fi
  if ! swift package --package-path "$pkg" --force-resolved-versions \
    --allow-writing-to-package-directory generate-code-from-openapi --target APIClient; then
    qg_fail "the API client generator failed"
  elif [ -n "$(git status --porcelain -- "$src")" ]; then
    git status --porcelain -- "$src" | head -20 | qg_quote
    qg_fail "the committed API client differs from what openapi.json generates: regenerate it and commit"
  else
    echo "Clean"
  fi
}

ios_static() {
  ios_static_gates
  qg_env_committed
  qg_gitleaks
  qg_skill_scan
}

ios_build() {
  ios_xcode || return 0
  qg_gates
  qg_coverage_floor
  ios_build_test
  ios_strings_built
  ios_periphery
  ios_client_drift
}

stack_gate() {
  case "$QG_PHASE" in
  static) ios_static ;;
  build) ios_build ;;
  *)
    ios_static
    ios_build
    ;;
  esac
}
