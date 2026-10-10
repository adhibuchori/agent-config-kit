#!/usr/bin/env bats
# actions/quality-gate/scripts/install-release.sh and its pin table tools.lock: each format installs
# exactly the named member, a wrong checksum or version refuses the tool, a platform without a row
# installs nothing, and the table pins the releases the plan names. Downloads are file:// URLs to
# archives the test builds, so nothing touches the network.

load helpers

INSTALL="$QG/install-release.sh"
LOCK="$QG/tools.lock"

setup() {
  ci_isolate
  F="$BATS_TEST_TMPDIR/files"
  mkdir -p "$F/pkg" "$BATS_TEST_TMPDIR/runner"
  # A tool that reports version 1.2.3 (or FAKE_VERSION) and a library it would load beside itself.
  printf '#!/usr/bin/env bash\necho "fake ${FAKE_VERSION:-1.2.3}"\n' >"$F/pkg/fake"
  chmod +x "$F/pkg/fake"
  printf 'library\n' >"$F/pkg/libfake.dylib"
  cp "$F/pkg/fake" "$F/fake-bin"
  tar -czf "$F/fake.tar.gz" -C "$F" pkg/fake pkg/libfake.dylib
  (cd "$F" && zip -q -r fake.zip pkg)
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner" GITHUB_PATH="$BATS_TEST_TMPDIR/github_path"
  export QG_TOOLS_LOCK="$BATS_TEST_TMPDIR/tools.lock" QG_PLATFORM=test-plat
  : >"$GITHUB_PATH"
}

sum() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# lock_row <tool> <format> <file> <member> [sum]: one row for test-plat, version 1.2.3.
lock_row() {
  printf '%s 1.2.3 test-plat %s %s file://%s %s\n' "$1" "$2" "${5:-$(sum "$F/$3")}" "$F/$3" "$4" >>"$QG_TOOLS_LOCK"
}

install_tools() { run --separate-stderr bash "$INSTALL" "$@"; }

@test "install-release: a raw binary, a tar.gz member and a zip member install under the tool's name" {
  printf '# comment line\n\n' >"$QG_TOOLS_LOCK"
  lock_row rawtool bin fake-bin -
  lock_row tartool tar.gz fake.tar.gz pkg/fake
  lock_row ziptool zip fake.zip pkg/fake,pkg/libfake.dylib
  install_tools rawtool tartool ziptool
  [ "$status" -eq 0 ]
  local t
  for t in rawtool tartool ziptool; do
    [ -x "$RUNNER_TEMP/quality-gate-tools/$t-1.2.3/$t" ]
    grep -qx "$RUNNER_TEMP/quality-gate-tools/$t-1.2.3" "$GITHUB_PATH"
    [[ "$output" == *"$t 1.2.3 (test-plat) verified and installed"* ]] || false
  done
  # The zip's second member lands beside the binary; nothing else of the archive stays.
  [ -f "$RUNNER_TEMP/quality-gate-tools/ziptool-1.2.3/libfake.dylib" ]
  [ ! -e "$RUNNER_TEMP/quality-gate-tools/ziptool-1.2.3/download" ]
  [ ! -e "$RUNNER_TEMP/quality-gate-tools/tartool-1.2.3/libfake.dylib" ]
}

@test "install-release: the tools can come from QG_TOOLS instead of arguments" {
  lock_row rawtool bin fake-bin -
  QG_TOOLS="rawtool" install_tools
  [ "$status" -eq 0 ]
  [ -x "$RUNNER_TEMP/quality-gate-tools/rawtool-1.2.3/rawtool" ]
  QG_TOOLS="" install_tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tool named"* ]] || false
}

@test "install-release: a wrong checksum refuses the tool and puts nothing on PATH" {
  lock_row tartool tar.gz fake.tar.gz pkg/fake "$(printf '0%.0s' {1..64})"
  install_tools tartool
  [ "$status" -eq 1 ]
  [[ "$output" == *"tartool 1.2.3 (test-plat) has SHA-256 $(sum "$F/fake.tar.gz"), expected 000"*"refusing to run it"* ]] || false
  [ ! -s "$GITHUB_PATH" ]
  [ ! -e "$RUNNER_TEMP/quality-gate-tools/tartool-1.2.3/tartool" ]
}

@test "install-release: a binary that reports another version, or fails to run, is refused" {
  lock_row rawtool bin fake-bin -
  FAKE_VERSION=1.2.4 install_tools rawtool
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not report version 1.2.3"* ]] || false
  [ ! -s "$GITHUB_PATH" ]
  # A loader error that prints the binary's path, whose folder name holds the version, still fails.
  printf '#!/usr/bin/env bash\necho "cannot load a library for $0" >&2\nexit 1\n' >"$F/fake-bin"
  : >"$QG_TOOLS_LOCK"
  lock_row rawtool bin fake-bin -
  install_tools rawtool
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not report version 1.2.3"* ]] || false
}

@test "install-release: an archive without the member fails" {
  lock_row ziptool zip fake.zip pkg/fake,pkg/missing.dylib
  install_tools ziptool
  [ "$status" -eq 1 ]
  [[ "$output" == *"the verified archive has no pkg/missing.dylib"* ]] || false
}

@test "install-release: no row for this platform installs nothing; an unknown tool exits 2" {
  lock_row rawtool bin fake-bin -
  QG_PLATFORM=other-plat install_tools rawtool
  [ "$status" -eq 0 ]
  [[ "$output" == *"no pinned rawtool build for other-plat and none on PATH"* ]] || false
  [ ! -s "$GITHUB_PATH" ]
  install_tools ghosttool
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"ghosttool is not in tools.lock"* ]] || false
}

@test "install-release: a cargo row builds the crate with cargo install --locked into its own root" {
  mkdir -p "$BATS_TEST_TMPDIR/stubs"
  cat >"$BATS_TEST_TMPDIR/stubs/cargo" <<'EOF'
#!/usr/bin/env bash
printf 'cargo %s\n' "$*" >"$BATS_TEST_TMPDIR/cargo.log"
root=""
while [ $# -gt 0 ]; do [ "$1" = --root ] && root="$2"; shift; done
mkdir -p "$root/bin"
printf '#!/usr/bin/env bash\necho "fakecrate-cli 1.2.3"\n' >"$root/bin/fakecrate"
chmod +x "$root/bin/fakecrate"
EOF
  chmod +x "$BATS_TEST_TMPDIR/stubs/cargo"
  printf 'fakecrate-cli 1.2.3 any cargo - fakecrate-cli tls,postgres\n' >"$QG_TOOLS_LOCK"
  PATH="$BATS_TEST_TMPDIR/stubs:$PATH" install_tools fakecrate-cli
  [ "$status" -eq 0 ]
  local root="$RUNNER_TEMP/quality-gate-tools/fakecrate-cli-1.2.3"
  [ "$(cat "$BATS_TEST_TMPDIR/cargo.log")" = "cargo install --locked --quiet --root $root fakecrate-cli --version 1.2.3 --no-default-features --features tls,postgres" ]
  grep -qx "$root/bin" "$GITHUB_PATH"
  rm "$BATS_TEST_TMPDIR/stubs/cargo"
  PATH="$(path_without cargo)" install_tools fakecrate-cli
  [ "$status" -eq 1 ]
  [[ "$output" == *"this runner has no cargo"* ]] || false
}

# ── tools.lock itself ────────────────────────────────────────────────────────────────────────

# rows <tool>: that tool's rows in the real table.
rows() { grep -E "^$1 " "$LOCK"; }

@test "tools.lock: the releases the plan pins, every row complete and checksummed" {
  local t v p f s src member extra
  while read -r t v p f s src member extra; do
    case "$t" in '' | '#'*) continue ;; esac
    [ -n "$member" ] && [ -z "$extra" ] || { echo "malformed row: $t $v $p" >&2; return 1; }
    case "$f" in
    cargo) [ "$s" = - ] && [ "$p" = any ] ;;
    bin | tar.gz | zip)
      [[ "$s" =~ ^[0-9a-f]{64}$ ]] || { echo "bad sum for $t $p" >&2; return 1; }
      [[ "$src" == https://github.com/*/releases/download/*"$v"* ]] || { echo "bad url for $t $p" >&2; return 1; }
      ;;
    *) echo "bad format $f" >&2 && return 1 ;;
    esac
  done <"$LOCK"
  [ "$(rows golangci-lint | awk '{print $2}' | sort -u)" = 2.14.0 ]
  [ "$(rows squawk | awk '{print $2}' | sort -u)" = 2.68.0 ]
  [ "$(rows cargo-llvm-cov | awk '{print $2}' | sort -u)" = 0.9.1 ]
  [ "$(rows cargo-nextest | awk '{print $2}' | sort -u)" = 0.9.148 ]
  [ "$(rows cargo-deny | awk '{print $2}' | sort -u)" = 0.20.2 ]
  [ "$(rows swiftlint | awk '{print $2}' | sort -u)" = 0.65.1 ]
  [ "$(rows periphery | awk '{print $2}' | sort -u)" = 3.8.0 ]
  [ "$(rows sqlx-cli)" = "sqlx-cli 0.9.0 any cargo - sqlx-cli rustls,postgres" ]
}

@test "tools.lock: the Linux and macOS runners each get every tool their gate installs" {
  local t p
  for t in golangci-lint squawk cargo-llvm-cov cargo-nextest cargo-deny swiftlint; do
    for p in linux-x64 linux-arm64 darwin-arm64 darwin-x64; do
      [ "$(rows "$t" | awk -v p="$p" '$3 == p' | wc -l | tr -d ' ')" = 1 ] || { echo "$t has no single $p row" >&2; return 1; }
    done
  done
  # Periphery runs only in the macOS job, and needs the libIndexStore it ships beside it.
  [ "$(rows periphery | awk '{print $3}' | sort | tr '\n' ' ')" = "darwin-arm64 darwin-x64 " ]
  [ "$(rows periphery | awk '{print $7}' | sort -u)" = periphery,libIndexStore.dylib ]
}

@test "tools.lock: SwiftLint on Linux is swiftlint-static (no SourceKit); on macOS the portable build" {
  [ "$(rows swiftlint | awk '$3 ~ /^linux/ {print $7}' | sort -u)" = swiftlint-static ]
  [ "$(rows swiftlint | awk '$3 ~ /^darwin/ {print $7}' | sort -u)" = swiftlint ]
  [ "$(rows swiftlint | awk '$3 == "linux-x64" {print $5}')" = caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d ]
  [ "$(rows swiftlint | awk '$3 == "linux-arm64" {print $5}')" = 9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8 ]
  [ "$(rows swiftlint | awk '$3 == "darwin-arm64" {print $5}')" = c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0 ]
}

@test "tools.lock: the pins match what the stack templates ask for, once those templates exist" {
  local tpl="$KIT_ROOT/plugins/agent-ios-swiftui/templates/ios-swiftui/.swiftlint.yml" pin
  local tools_env="$KIT_ROOT/plugins/agent-be-go/templates/be-go/scripts/check/tools.env" checked=0
  if [ -f "$tpl" ]; then
    pin=$(sed -n 's/^swiftlint_version:[[:space:]]*\([0-9.]*\).*/\1/p' "$tpl")
    [ "$pin" = "$(rows swiftlint | awk 'NR == 1 {print $2}')" ]
    checked=1
  fi
  if [ -f "$tools_env" ]; then
    pin=$(grep -i golangci "$tools_env" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ "$pin" = "$(rows golangci-lint | awk 'NR == 1 {print $2}')" ]
    checked=1
  fi
  [ "$checked" -eq 1 ] || skip "the ios-swiftui and be-go templates are not in this tree yet"
}
