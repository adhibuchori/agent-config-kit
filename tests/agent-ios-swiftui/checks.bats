#!/usr/bin/env bats
# The ios-swiftui check scripts against a probe app: for each check, a probe that must block and
# one that must pass. The Linux-safe checks run as they are; the ones that call Xcode's tools get
# stubs (swift, xcrun, xcodebuild, xcode-select), except xcode-settings.sh, which needs the real
# plutil and skips without it.

load helpers

setup() {
  ios_setup_env
  make_app
}

# ── lint-suppressions.sh ─────────────────────────────────────────────────────────────────────

@test "lint-suppressions: the six seeded cases fail, each with its code" {
  mkdir -p "$REPO/Packages/AppCore/Sources/Domain" "$REPO/Packages/AppCore"
  cat >"$REPO/Packages/AppCore/Sources/Domain/Bad.swift" <<'EOF'
// swiftlint:disable:next force_cast
let a = 1
// swiftlint:disable:next force_try - why
let b = 2
// swiftlint:disable all
let c = 3
// swift-format-ignore: NeverForceUnwrap
let d = 4
@diagnose(DeprecatedDeclaration, as: ignored)
func e() {}
EOF
  printf 'disabled_rules: [force_cast]\n' >"$REPO/Packages/AppCore/.swiftlint.yml"
  commit_all "suppressions"
  in_repo bash scripts/check/lint-suppressions.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Bad.swift:1: S1 "* ]] || false
  [[ "$output" == *"Bad.swift:3: S1 "* ]] || false
  [[ "$output" == *"Bad.swift:5: S2 swiftlint:disable all"* ]] || false
  [[ "$output" == *"Bad.swift:7: S3 swift-format-ignore"* ]] || false
  [[ "$output" == *"Bad.swift:9: S4 @diagnose"* ]] || false
  [[ "$output" == *"Packages/AppCore/.swiftlint.yml: S2 a nested SwiftLint config"* ]] || false
}

@test "lint-suppressions: a reasoned disable:next and a raising @diagnose pass; generated code is skipped" {
  mkdir -p "$REPO/Packages/AppCore/Sources/Domain" "$REPO/Packages/AppCore/Sources/APIClient/GeneratedSources"
  cat >"$REPO/Packages/AppCore/Sources/Domain/Good.swift" <<'EOF'
// swiftlint:disable:next force_cast - the SDK boxes this value as Int
let a = 1
@diagnose(DeprecatedDeclaration, as: error)
func e() {}
EOF
  printf '// swiftlint:disable all\n' >"$REPO/Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift"
  commit_all "good suppressions"
  in_repo bash scripts/check/lint-suppressions.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "lint-suppressions: clean ("* ]] || false
  # One file named on the command line: what a post-edit hook would pass.
  in_repo bash scripts/check/lint-suppressions.sh Packages/AppCore/Sources/Domain/Good.swift
  [ "$status" -eq 0 ]
}

# ── i18n-catalog.mjs ─────────────────────────────────────────────────────────────────────────

@test "i18n-catalog: the probe app's catalog is clean in both locales, and manual keys are listed" {
  printf '{"locales": ["en", "id"]}\n' >"$REPO/scripts/check/i18n-catalog.json"
  in_repo node scripts/check/i18n-catalog.mjs
  [ "$status" -eq 0 ]
  [[ "$output" == *"I5 4 manual key(s)"* ]] || false
  [[ "$output" == *"1 catalog(s) clean (locales: en, id)"* ]] || false
}

@test "i18n-catalog: a missing locale, unfinished states, a plural leaf and a stale key each fail" {
  printf '{"locales": ["en", "id"]}\n' >"$REPO/scripts/check/i18n-catalog.json"
  cp "$FIXTURES/catalogs/defects.xcstrings" "$REPO/App/Localizable.xcstrings"
  commit_all "defects"
  in_repo node scripts/check/i18n-catalog.mjs
  [ "$status" -eq 1 ]
  [[ "$output" == *'I1 "orders.empty" has no id'* ]] || false
  [[ "$output" == *'I2 "orders.title" id is new'* ]] || false
  [[ "$output" == *'I2 "orders.review" id is needs_review'* ]] || false
  [[ "$output" == *'I2 "orders.count" id/plural.other is new'* ]] || false
  [[ "$output" == *'I3 "orders.old" is stale'* ]] || false
  [[ "$output" != *'brand.name'* ]] || false
}

@test "i18n-catalog: without a locale list each catalog is checked against its source language" {
  rm -f "$REPO/scripts/check/i18n-catalog.json"
  cp "$FIXTURES/catalogs/defects.xcstrings" "$REPO/App/Localizable.xcstrings"
  commit_all "defects, English only"
  in_repo node scripts/check/i18n-catalog.mjs
  [ "$status" -eq 1 ]
  [[ "$output" != *"I1 "* ]] || false
  [[ "$output" == *'I3 "orders.old" is stale'* ]] || false
}

@test "i18n-catalog --stringsdata: a key the build used but the catalog lacks fails, and so does an unused one" {
  local sd="$BATS_TEST_TMPDIR/DerivedData/Build/Intermediates.noindex/Orders.build/Objects-normal/arm64"
  mkdir -p "$sd"
  python3 - "$REPO" "$sd" <<'PY'
import json, os, sys
repo, sd = sys.argv[1], sys.argv[2]
def write(name, source, keys):
    json.dump({"source": os.path.join(repo, source), "version": 1,
               "tables": {"Localizable": [{"key": k} for k in keys]}}, open(os.path.join(sd, name), "w"))
write("OrdersApp.stringsdata", "App/OrdersApp.swift", ["orders.title", "orders.new"])
write("Tests.stringsdata", "UITests/AuditTests.swift", ["ui.only"])
PY
  in_repo node scripts/check/i18n-catalog.mjs --stringsdata "$BATS_TEST_TMPDIR/DerivedData"
  [ "$status" -eq 1 ]
  [[ "$output" == *'I4 "orders.new" is used in App/OrdersApp.swift but missing from the catalog'* ]] || false
  [[ "$output" == *'I4 "orders.empty" was extracted from code, yet no code uses it now'* ]] || false
  [[ "$output" != *"ui.only"* ]] || false
  [[ "$output" != *'"problem.NOT_FOUND"'* ]] || false
}

@test "i18n-catalog --stringsdata: the build's keys and the catalog agree" {
  local sd="$BATS_TEST_TMPDIR/DerivedData/x"
  mkdir -p "$sd"
  python3 - "$REPO" "$sd" <<'PY'
import json, os, sys
repo, sd = sys.argv[1], sys.argv[2]
keys = [k for k, v in json.load(open(os.path.join(repo, "App/Localizable.xcstrings")))["strings"].items()
        if v.get("extractionState") != "manual"]
json.dump({"source": os.path.join(repo, "App/OrdersApp.swift"), "version": 1,
           "tables": {"Localizable": [{"key": k} for k in keys]}}, open(os.path.join(sd, "a.stringsdata"), "w"))
PY
  in_repo node scripts/check/i18n-catalog.mjs --stringsdata "$BATS_TEST_TMPDIR/DerivedData"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked against the build"* ]] || false
}

# ── error-codes.sh ───────────────────────────────────────────────────────────────────────────

@test "error-codes: the seeded codes, the base and every message agree with the probe spec" {
  in_repo bash scripts/check/error-codes.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 code(s) agree with Packages/AppCore/Sources/APIClient/openapi.json, each with its message"* ]] || false
}

@test "error-codes: a code the spec adds fails until ProblemCode has it" {
  python3 - "$REPO/Packages/AppCore/Sources/APIClient/openapi.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["components"]["schemas"]["Problem"]["properties"]["code"]["enum"].append("RATE_LIMITED")
json.dump(d, open(p, "w"), indent=2)
PY
  in_repo bash scripts/check/error-codes.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"E1 the spec lists RATE_LIMITED; add its ProblemCode case and its message problem.RATE_LIMITED"* ]] || false
}

@test "error-codes: a different base, a malformed base and a missing message each fail" {
  sed -i.bak 's#"x-problem-type-base": "https://example.invalid/problems/"#"x-problem-type-base": "http://example.invalid/errors"#' \
    "$REPO/Packages/AppCore/Sources/APIClient/openapi.json"
  rm -f "$REPO/Packages/AppCore/Sources/APIClient/openapi.json.bak"
  python3 - "$REPO/App/Localizable.xcstrings" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["strings"]["problem.NOT_FOUND"]
json.dump(d, open(p, "w"), indent=2)
PY
  commit_all "drift"
  in_repo bash scripts/check/error-codes.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"E2 AppProblem.typeBase is https://example.invalid/problems/, the spec's x-problem-type-base is http://example.invalid/errors"* ]] || false
  [[ "$output" == *"E4 "*"is not an https URI ending in '/'"* ]] || false
  [[ "$output" == *"E3 no String Catalog has the key problem.NOT_FOUND"* ]] || false
}

@test "error-codes: before the first spec copy there is nothing to compare, and it says so" {
  rm "$REPO/Packages/AppCore/Sources/APIClient/openapi.json"
  in_repo bash scripts/check/error-codes.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no spec copy at Packages/AppCore/Sources/APIClient/openapi.json yet"* ]] || false
}

# ── privacy-manifest.sh ──────────────────────────────────────────────────────────────────────

@test "privacy-manifest: UserDefaults and @AppStorage without a declared reason fail" {
  mkdir -p "$REPO/App/Screens"
  printf 'import SwiftUI\nstruct S: View {\n    @AppStorage("seen") private var seen = false\n    var body: some View { Text("x") }\n}\n' \
    >"$REPO/App/Screens/S.swift"
  printf 'import Foundation\nlet store = UserDefaults.standard\n' >"$REPO/App/Store.swift"
  commit_all "defaults"
  in_repo bash scripts/check/privacy-manifest.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"M2 App/Screens/S.swift:3 uses a UserDefaults API"* ]] || false
  [[ "$output" == *"M2 App/Store.swift:2 uses a UserDefaults API"* ]] || false
}

@test "privacy-manifest: a declared reason passes, also from a binary plist; a model's own creationDate is no file API" {
  printf 'import Foundation\nlet store = UserDefaults.standard\nstruct Order { let creationDate: Date }\n' >"$REPO/App/Store.swift"
  python3 - "$REPO/App/PrivacyInfo.xcprivacy" <<'PY'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, "rb"))
d["NSPrivacyAccessedAPITypes"] = [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                                   "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]
plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)
PY
  commit_all "declared"
  in_repo bash scripts/check/privacy-manifest.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"every required-reason API in use is declared"* ]] || false
}

@test "privacy-manifest: a missing manifest and an entry without a reason fail" {
  python3 - "$REPO/App/PrivacyInfo.xcprivacy" <<'PY'
import plistlib, sys
p = sys.argv[1]
d = plistlib.load(open(p, "rb"))
d["NSPrivacyAccessedAPITypes"] = [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace"}]
plistlib.dump(d, open(p, "wb"))
PY
  in_repo bash scripts/check/privacy-manifest.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"M1 App/PrivacyInfo.xcprivacy: NSPrivacyAccessedAPICategoryDiskSpace lists no reason"* ]] || false
  rm "$REPO/App/PrivacyInfo.xcprivacy"
  in_repo bash scripts/check/privacy-manifest.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"M1 App/PrivacyInfo.xcprivacy is missing"* ]] || false
}

# ── package-graph.sh (swift replaced by a stub that prints dump-package JSON) ────────────────

# graph_stub [python edit of `d`]: a swift stub serving the clean graph, changed by the edit.
graph_stub() {
  python3 - "$FIXTURES/packages/clean.json" "$BATS_TEST_TMPDIR/dump.json" "${1:-pass}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"))
PY
  stub swift <<EOF
[ "\$*" = "package --package-path Packages/AppCore dump-package" ] || { echo "unexpected: swift \$*" >&2; exit 64; }
cat "$BATS_TEST_TMPDIR/dump.json"
EOF
  mkdir -p "$REPO/Orders.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
  printf '{"pins": [{"identity": "swift-openapi-runtime", "state": {"version": "1.13.0"}}]}\n' >"$REPO/Packages/AppCore/Package.resolved"
  cp "$REPO/Packages/AppCore/Package.resolved" "$REPO/Orders.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  commit_all "pins"
}

@test "package-graph: layered, tested, exact and pinned passes" {
  graph_stub
  in_repo bash scripts/check/package-graph.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Packages/AppCore: 3 library target(s), each layered and tested; every remote package exact"* ]] || false
}

@test "package-graph: Domain importing APIClient fails P2, an untested target fails P3" {
  graph_stub 'd["targets"][0]["dependencies"] = [{"byName": ["APIClient", None]}]; d["targets"] = [t for t in d["targets"] if t["name"] != "DomainTests"]'
  in_repo bash scripts/check/package-graph.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"P2 Packages/AppCore: Domain imports APIClient"* ]] || false
  [[ "$output" == *"P3 Packages/AppCore: library target Domain has no test target DomainTests"* ]] || false
}

@test "package-graph: a range, a build-tool plugin and an unlisted target fail P4, P5 and P2" {
  graph_stub 'd["dependencies"][0]["sourceControl"][0]["requirement"] = {"range": [{"lowerBound": "1.0.0", "upperBound": "2.0.0"}]}; d["targets"][1]["pluginUsages"] = [{"plugin": ["OpenAPIGenerator", "swift-openapi-generator"]}]; d["targets"].append({"name": "Persistence", "type": "regular", "dependencies": []})'
  in_repo bash scripts/check/package-graph.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"P4 Packages/AppCore: swift-openapi-runtime is not pinned with exact:"* ]] || false
  [[ "$output" == *"P5 Packages/AppCore: APIClient runs the build-tool plugin OpenAPIGenerator"* ]] || false
  [[ "$output" == *'P2 Packages/AppCore: target Persistence is not under "layers"'* ]] || false
}

@test "package-graph: the app's pins must agree with the package's (P6)" {
  graph_stub
  printf '{"pins": [{"identity": "swift-openapi-runtime", "state": {"version": "1.12.0"}}]}\n' \
    >"$REPO/Orders.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  commit_all "drifted pins"
  in_repo bash scripts/check/package-graph.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"P6 swift-openapi-runtime is 1.12.0 in Orders.xcodeproj"* ]] || false
}

# ── coverage.sh (swift, xcrun and xcode-select replaced by stubs) ────────────────────────────

# coverage_stubs <lcov body>: swift test "passes", and llvm-cov exports the given report.
coverage_stubs() {
  printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/lcov.txt"
  mkdir -p "$BATS_TEST_TMPDIR/products/Debug/codecov" "$BATS_TEST_TMPDIR/products/Debug/APIClientTests.xctest/Contents/MacOS"
  touch "$BATS_TEST_TMPDIR/products/Debug/APIClientTests.xctest/Contents/MacOS/APIClientTests"
  stub swift <<EOF
case "\$*" in
*--show-codecov-path*) echo "$BATS_TEST_TMPDIR/products/Debug/codecov/AppCore.json" ;;
--version) echo "Apple Swift version 6.4 (stub)" ;;
*) echo "swift \$*" >>"$BATS_TEST_TMPDIR/swift.log" ;;
esac
EOF
  stub xcrun <<EOF
echo "xcrun \$*" >>"$BATS_TEST_TMPDIR/xcrun.log"
cat "$BATS_TEST_TMPDIR/lcov.txt"
EOF
  stub xcode-select <<'EOF'
echo /Applications/Xcode.app/Contents/Developer
EOF
}

@test "coverage: every file at 100% passes; the exempt list reaches llvm-cov" {
  coverage_stubs "SF:$REPO/Packages/AppCore/Sources/APIClient/AppProblem.swift
FNF:3
FNH:3
LF:20
LH:20
end_of_record"
  in_repo bash scripts/check/coverage.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage-per-file: 1 file(s), each at 100% (lines, functions)"* ]] || false
  grep -q 'swift test --package-path Packages/AppCore --enable-code-coverage' "$BATS_TEST_TMPDIR/swift.log"
  grep -q "llvm-cov export -format=lcov -instr-profile $BATS_TEST_TMPDIR/products/Debug/codecov/default.profdata" "$BATS_TEST_TMPDIR/xcrun.log"
  grep -q 'GeneratedSources' "$BATS_TEST_TMPDIR/xcrun.log"
  [ -f "$REPO/coverage/lcov.info" ]
}

@test "coverage: a file below 100% of its functions fails and is named" {
  coverage_stubs "SF:$REPO/Packages/AppCore/Sources/Features/OrderListModel.swift
FNF:4
FNH:3
LF:30
LH:30
end_of_record"
  in_repo bash scripts/check/coverage.sh
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Packages/AppCore/Sources/Features/OrderListModel.swift: lines 30/30, functions 3/4"* ]] || false
}

# ── scripts/ios (Xcode replaced by stubs) ────────────────────────────────────────────────────

@test "api-client: no spec copy is a usage error; --check fails when regeneration changes the client" {
  rm "$REPO/Packages/AppCore/Sources/APIClient/openapi.json"
  in_repo bash scripts/ios/api-client.sh --check
  [ "$status" -eq 2 ]
  git -C "$REPO" checkout -q -- Packages/AppCore/Sources/APIClient/openapi.json
  stub swift <<EOF
echo "swift \$*" >>"$BATS_TEST_TMPDIR/swift.log"
EOF
  in_repo bash scripts/ios/api-client.sh --check
  [ "$status" -eq 0 ]
  grep -qx 'swift package --package-path Packages/AppCore --force-resolved-versions --allow-writing-to-package-directory generate-code-from-openapi --target APIClient' "$BATS_TEST_TMPDIR/swift.log"
  stub swift <<EOF
mkdir -p Packages/AppCore/Sources/APIClient/GeneratedSources
echo 'struct Client {}' >Packages/AppCore/Sources/APIClient/GeneratedSources/Client.swift
EOF
  in_repo bash scripts/ios/api-client.sh --check
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the committed client differs from what"* ]] || false
}

# app_stubs <warning count>: xcodebuild records its arguments; xcresulttool reports the count.
app_stubs() {
  stub xcodebuild <<EOF
case "\$1" in
-list) echo '{"project": {"targets": ["Orders", "OrdersUITests"]}}' ;;
*) echo "xcodebuild \$*" >>"$BATS_TEST_TMPDIR/xcodebuild.log" ;;
esac
EOF
  stub xcrun <<EOF
case "\$*" in
"simctl list devices available -j")
  echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-0": [{"name": "iPhone 16", "udid": "OLD-UDID"}], "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPad Air", "udid": "IPAD"}, {"name": "iPhone 17 Pro", "udid": "BOOTED-UDID", "state": "Booted"}, {"name": "iPhone 17", "udid": "NEW-UDID", "state": "Shutdown"}]}}' ;;
*build-results*) echo '{"errorCount": 0, "warningCount": $1, "warnings": [{"message": "var never mutated", "sourceURL": "App/OrdersApp.swift"}]}' ;;
*test-results*) echo '{"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0, "testFailures": []}' ;;
esac
EOF
}

@test "app.sh ui-test: the newest iPhone by udid, the UI test target, no signing, resolved pins only" {
  app_stubs 0
  in_repo bash scripts/ios/app.sh ui-test
  [ "$status" -eq 0 ]
  run cat "$BATS_TEST_TMPDIR/xcodebuild.log"
  [[ "$output" == "xcodebuild test -project Orders.xcodeproj -scheme Orders -derivedDataPath .build/xcode -resultBundlePath .build/xcode/results/ui-test-"*".xcresult -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO -destination id=NEW-UDID -only-testing:OrdersUITests -quiet" ]] || false
  [[ "$output" != *"retry"* ]] || false
}

@test "app.sh test: a booted iPhone is skipped for one not in use; IOS_SIMULATOR_ID wins over both" {
  app_stubs 0
  in_repo bash scripts/ios/app.sh test
  [ "$status" -eq 0 ]
  grep -q -- '-destination id=NEW-UDID' "$BATS_TEST_TMPDIR/xcodebuild.log"
  run ! grep -q 'BOOTED-UDID' "$BATS_TEST_TMPDIR/xcodebuild.log"
  : >"$BATS_TEST_TMPDIR/xcodebuild.log"
  IOS_SIMULATOR_ID=PICKED-UDID in_repo bash scripts/ios/app.sh test
  [ "$status" -eq 0 ]
  grep -q -- '-destination id=PICKED-UDID' "$BATS_TEST_TMPDIR/xcodebuild.log"
}

@test "app.sh build: one warning in the result bundle fails the build" {
  app_stubs 1
  in_repo bash scripts/ios/app.sh build
  [ "$status" -eq 1 ]
  [[ "$output" == *"warning: var never mutated App/OrdersApp.swift"* ]] || false
  [[ "$output" == *"app: 0 error(s), 1 warning(s)"* ]] || false
  grep -q 'generic/platform=iOS Simulator' "$BATS_TEST_TMPDIR/xcodebuild.log"
}

# ── xcode-settings.sh (the real plutil: macOS only) ──────────────────────────────────────────

@test "xcode-settings: the probe project, based on Config/*.xcconfig, passes" {
  command -v plutil >/dev/null 2>&1 || skip "plutil is macOS-only; xcode-settings.sh runs in the macOS job"
  in_repo bash scripts/check/xcode-settings.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings in Config/, Swift 6, warnings as errors, ATS on"* ]] || false
}

@test "xcode-settings: a SWIFT_ key in the project, Swift 5, ATS off and a secret in an xcconfig each fail" {
  command -v plutil >/dev/null 2>&1 || skip "plutil is macOS-only; xcode-settings.sh runs in the macOS job"
  # shellcheck disable=SC2016 # $(TARGET_NAME) is Xcode's, not the shell's
  sed -i.bak 's/PRODUCT_NAME = "$(TARGET_NAME)";/PRODUCT_NAME = "$(TARGET_NAME)"; SWIFT_VERSION = 5.0;/' "$REPO/Orders.xcodeproj/project.pbxproj"
  sed -i.bak 's/^SWIFT_VERSION = 6.0$/SWIFT_VERSION = 5.0/' "$REPO/Config/Base.xcconfig"
  printf 'API_KEY = abc123\n' >>"$REPO/Config/Release.xcconfig"
  python3 -c 'import plistlib, sys; plistlib.dump({"NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True}}, open(sys.argv[1], "wb"))' "$REPO/App/Info.plist"
  rm -f "$REPO"/Orders.xcodeproj/*.bak "$REPO"/Config/*.bak
  commit_all "regressions"
  in_repo bash scripts/check/xcode-settings.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"X2 Orders.xcodeproj/project.pbxproj: the Debug configuration"*"sets SWIFT_VERSION"* ]] || false
  [[ "$output" == *"X3 Config/Debug.xcconfig (the project's Debug): SWIFT_VERSION is '5.0', want 6.0"* ]] || false
  [[ "$output" == *"X4 App/Info.plist turns App Transport Security off"* ]] || false
  [[ "$output" == *"X5 Config/Release.xcconfig:"*"API_KEY"* ]] || false
}

@test "xcode-settings: a project configuration without a base xcconfig fails X1" {
  command -v plutil >/dev/null 2>&1 || skip "plutil is macOS-only; xcode-settings.sh runs in the macOS job"
  python3 - "$REPO/Orders.xcodeproj/project.pbxproj" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("baseConfigurationReference = B10000000000000000000008 /* Debug.xcconfig */;\n", "", 1)
open(p, "w").write(s)
PY
  commit_all "unlinked"
  in_repo bash scripts/check/xcode-settings.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"X1 the project's Debug configuration has no base xcconfig"* ]] || false
}
