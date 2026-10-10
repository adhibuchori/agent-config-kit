#!/usr/bin/env bats
# The Swift half of the payload contract against the shared vectors (the template's Rule 33): the
# seeded wire-format and crypto files and PayloadVectorsTests build in a package of their own, with
# no dependency to fetch, and `swift test` passes; a changed AAD or a changed HKDF label fails it.
# The package says swift-tools-version 6.0, so the Xcode 16 of the macos-15 runner compiles the
# files too. macOS only: CryptoKit is Apple's.

load helpers

# The files the vectors test compiles: everything below the middleware, which needs the client
# runtime and is proven by the template's own tests in a set-up app.
CORE_FILES="PayloadBase64URL PayloadCipher PayloadCodec PayloadEnvelope PayloadError PayloadKeyAgreement"

setup() {
  ios_setup_env
  [ "$(uname -s)" = Darwin ] || skip "CryptoKit and swift test need macOS; on Linux this file has nothing to run"
  command -v swift >/dev/null 2>&1 || skip "no Swift toolchain on this Mac (install Xcode)"
  ROOT="$BATS_TEST_TMPDIR/repo"
  local src="$ROOT/Packages/AppCore/Sources/APIClient" tests="$ROOT/Packages/AppCore/Tests/APIClientTests" f
  mkdir -p "$src" "$tests" "$ROOT/scripts/check"
  for f in $CORE_FILES; do
    cp "$TPL/Packages/AppCore/Sources/APIClient/$f.swift" "$src/"
  done
  cp "$TPL/Packages/AppCore/Tests/APIClientTests/PayloadVectorsTests.swift" \
    "$TPL/Packages/AppCore/Tests/APIClientTests/PayloadVectorFile.swift" "$tests/"
  cp "$TPL/scripts/check/payload-vectors.json" "$ROOT/scripts/check/"
  cat >"$ROOT/Packages/AppCore/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "APIClient", swiftSettings: strict),
        .testTarget(name: "APIClientTests", dependencies: ["APIClient"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
SWIFT
}

vectors_test() {
  run --separate-stderr swift test --package-path "$ROOT/Packages/AppCore" --filter PayloadVectorsTests
}

@test "the shared vectors carry the key agreement and the points to refuse" {
  run -0 python3 - "$ROOT/scripts/check/payload-vectors.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
assert v["agreements"] and v["pointRejects"], sorted(v)
assert all(a["info"] == "payload-envelope/v1/browser" for a in v["agreements"])
print("ok")
PY
}

@test "the cipher, its AAD and the key agreement pass the shared vectors, with no warning" {
  vectors_test
  echo "$output" "$stderr" | tail -40
  [ "$status" -eq 0 ]
  [[ "$output" == *"Suite \"Payload vectors\" passed"* ]] || false
  run grep -E '(warning|error):' <<<"$output
$stderr"
  [ "$status" -eq 1 ]
}

@test "a request AAD with the method in lower case fails the vectors" {
  sed -i '' 's/method\.uppercased()/method.lowercased()/' "$ROOT/Packages/AppCore/Sources/APIClient/PayloadEnvelope.swift"
  grep -q 'method.lowercased()' "$ROOT/Packages/AppCore/Sources/APIClient/PayloadEnvelope.swift"
  vectors_test
  [ "$status" -ne 0 ]
  [[ "$output" == *"builds every vector's AAD byte for byte"*"failed"* ]] || false
}

@test "an HKDF label other than the browser hop's fails the key agreement" {
  sed -i '' 's|"payload-envelope/v1/browser"|"payload-envelope/v1/app"|' \
    "$ROOT/Packages/AppCore/Sources/APIClient/PayloadKeyAgreement.swift"
  grep -q 'payload-envelope/v1/app' "$ROOT/Packages/AppCore/Sources/APIClient/PayloadKeyAgreement.swift"
  vectors_test
  [ "$status" -ne 0 ]
  [[ "$output" == *"agrees the secret and the key from either side"*"failed"* ]] || false
}
