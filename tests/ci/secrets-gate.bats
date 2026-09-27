#!/usr/bin/env bats
# scripts/check/secrets.sh, agent-core's pre-commit secret scan: the staged changes through gitleaks
# with the repo's .gitleaks.toml. It fails, never skips, when gitleaks or the config is missing; a
# release other than CI's pin warns and still scans. Stubs stand in for gitleaks except where a real
# one proves the scan itself.

load helpers

SECRETS="$KIT_ROOT/plugins/agent-core/templates/common/scripts/check/secrets.sh"

setup() {
  ci_isolate
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/check"
  git init -q "$REPO"
  git -C "$REPO" commit -q --allow-empty -m init
  cp -p "$SECRETS" "$REPO/scripts/check/secrets.sh"
  cp "$KIT_ROOT/plugins/agent-core/templates/common/.gitleaks.toml" "$REPO/.gitleaks.toml"
}

# fake_gitleaks <version>: a gitleaks on PATH that reports <version> and logs every scan it runs.
fake_gitleaks() {
  mkdir -p "$BATS_TEST_TMPDIR/fake"
  cat >"$BATS_TEST_TMPDIR/fake/gitleaks" <<FAKE
#!/usr/bin/env bash
[ "\$1" = version ] && { echo "$1"; exit 0; }
printf 'gitleaks %s\n' "\$*" >>"$BATS_TEST_TMPDIR/scans.log"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/fake/gitleaks"
  PATH="$BATS_TEST_TMPDIR/fake:$PATH"
}

pin() { sed -n 's/^PIN=//p' "$SECRETS"; }

@test "secrets: the pin is the release the reusable quality gate installs" {
  [ -n "$(pin)" ]
  [ "$(pin)" = "$(sed -n 's/^VERSION=//p' "$QG/install-gitleaks.sh")" ]
}

@test "secrets: without gitleaks it fails, never skips, and names the release to install" {
  run --separate-stderr env PATH="$(path_without gitleaks)" bash "$REPO/scripts/check/secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gitleaks is not installed; install release $(pin)"* ]]
}

@test "secrets: CI's release scans the staged changes with the repo's config, quietly" {
  fake_gitleaks "$(pin)"
  run -0 --separate-stderr bash "$REPO/scripts/check/secrets.sh"
  [ -z "$stderr" ]
  [ "$(cat "$BATS_TEST_TMPDIR/scans.log")" = "gitleaks git --staged --no-banner --redact --config .gitleaks.toml" ]
}

@test "secrets: another release warns on stderr and still scans" {
  fake_gitleaks 8.18.0
  run -0 --separate-stderr bash "$REPO/scripts/check/secrets.sh"
  [[ "$stderr" == *"gitleaks 8.18.0 found; CI pins $(pin). Scanning with it anyway"* ]]
  grep -q '^gitleaks git --staged ' "$BATS_TEST_TMPDIR/scans.log"
}

@test "secrets: a repo that runs its own gate is held to its GITLEAKS_VERSION" {
  mkdir -p "$REPO/.github/scripts"
  printf '#!/usr/bin/env bash\nGITLEAKS_VERSION=9.1.0\n' >"$REPO/.github/scripts/quality-gate.sh"
  fake_gitleaks "$(pin)"
  run -0 --separate-stderr bash "$REPO/scripts/check/secrets.sh"
  [[ "$stderr" == *"CI pins 9.1.0"* ]]
}

@test "secrets: without .gitleaks.toml it fails and scans nothing" {
  rm "$REPO/.gitleaks.toml"
  fake_gitleaks "$(pin)"
  run --separate-stderr bash "$REPO/scripts/check/secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *".gitleaks.toml is missing"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/scans.log" ]
}

@test "secrets: a staged token fails the gate; a clean staged change passes (real gitleaks)" {
  command -v gitleaks >/dev/null || skip "gitleaks is not installed"
  cd "$REPO"
  echo "notes" >notes.txt
  git add notes.txt
  run -0 --separate-stderr bash scripts/check/secrets.sh
  # A random token, so no allowlist of documented examples lets it through.
  python3 -c 'import secrets, string; a = string.ascii_letters + string.digits; print("token = \"ghp_" + "".join(secrets.choice(a) for _ in range(36)) + "\"")' >conf.txt
  git add conf.txt
  run --separate-stderr bash scripts/check/secrets.sh
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"leaks found: 1"* ]]
}
