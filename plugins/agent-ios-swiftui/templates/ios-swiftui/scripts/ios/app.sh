#!/usr/bin/env bash
# Builds and tests the app target for the simulator, and never signs (CODE_SIGNING_ALLOWED=NO).
# Picks an iPhone of the newest installed iOS runtime by its id, one that is not booted first
# (IOS_SIMULATOR_ID overrides the choice), resolves packages only from
# the committed Package.resolved, writes a result bundle under .build/xcode/results/, and fails when
# the build reports any warning (AGENTS.md Rule 19): some Swift 6 concurrency warnings stay warnings
# even with warnings-as-errors on, so the count in the result bundle is what decides. Tests never
# retry on failure.
#
#   bash scripts/ios/app.sh build                  build for any iOS simulator
#   bash scripts/ios/app.sh test [ID...]           run the scheme's tests (ID: Target[/Class[/test]])
#   bash scripts/ios/app.sh ui-test [ID...]        the UI test target only (default: *UITests)
#
# The project is the one *.xcodeproj at the repo root (IOS_PROJECT overrides it) and the scheme is
# its name (IOS_SCHEME overrides it). Exit 0 clean, 1 a failed build, test or a warning, 2 a usage
# problem or no simulator.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2

usage() {
  echo "usage: bash scripts/ios/app.sh build | test [ID...] | ui-test [ID...]" >&2
  exit 2
}
ACTION="${1:-}"
[ $# -gt 0 ] && shift
case "$ACTION" in build | test | ui-test) ;; *) usage ;; esac

project="${IOS_PROJECT:-}"
if [ -z "$project" ]; then
  for p in *.xcodeproj; do
    [ -d "$p" ] || continue
    [ -z "$project" ] || {
      echo "app: several projects here; set IOS_PROJECT to one of them" >&2
      exit 2
    }
    project="$p"
  done
fi
[ -n "$project" ] && [ -d "$project" ] || {
  echo "app: no *.xcodeproj at the repo root; create the app project in Xcode first" >&2
  exit 2
}
scheme="${IOS_SCHEME:-$(basename "$project" .xcodeproj)}"

# IOS_SIMULATOR_ID when set; otherwise an iPhone of the newest iOS runtime, by udid (device names
# differ between Xcode images), one that is not booted first: a booted simulator is likely the one
# someone is using, and this unsigned test build would replace their signed app (its Keychain then
# refuses every write, errSecMissingEntitlement).
simulator() {
  if [ -n "${IOS_SIMULATOR_ID:-}" ]; then echo "$IOS_SIMULATOR_ID"; return 0; fi
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
runtimes = json.load(sys.stdin).get("devices", {})
def version(key):
    m = re.search(r"iOS-(\d+)-(\d+)", key)
    return (int(m.group(1)), int(m.group(2))) if m else None
for key in sorted((k for k in runtimes if version(k)), key=version, reverse=True):
    phones = [d for d in runtimes[key] if d.get("isAvailable", True) and d.get("name", "").startswith("iPhone")]
    phones.sort(key=lambda d: d.get("state") == "Booted")
    if phones:
        print(phones[0]["udid"])
        sys.exit(0)
sys.exit(1)'
}

results=".build/xcode/results"
mkdir -p "$results"
bundle="$results/$ACTION-$(date +%Y%m%d-%H%M%S).xcresult"
args=(-project "$project" -scheme "$scheme" -derivedDataPath .build/xcode -resultBundlePath "$bundle"
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO)

if [ "$ACTION" = build ]; then
  args=(build "${args[@]}" -destination "generic/platform=iOS Simulator")
else
  udid="$(simulator)" || {
    echo "app: no available iPhone simulator; add an iOS runtime in Xcode's Components settings" >&2
    exit 2
  }
  args=(test "${args[@]}" -destination "id=$udid")
  ids=("$@")
  if [ "$ACTION" = ui-test ] && [ ${#ids[@]} -eq 0 ]; then
    while IFS= read -r target; do
      ids+=("$target")
    done < <(xcodebuild -list -json -project "$project" | python3 -c '
import json, sys
for t in json.load(sys.stdin).get("project", {}).get("targets", []):
    if t.endswith("UITests"):
        print(t)')
    [ ${#ids[@]} -gt 0 ] || {
      echo "app: the project has no *UITests target" >&2
      exit 2
    }
  fi
  for id in ${ids[@]+"${ids[@]}"}; do
    args+=("-only-testing:$id")
  done
fi

status=0
xcodebuild "${args[@]}" -quiet || status=1

# What the result bundle says, whatever xcodebuild's exit code: warnings fail the run too.
summary="$(xcrun xcresulttool get build-results --path "$bundle" 2>/dev/null || echo '{}')"
python3 -c '
import json, sys
data = json.loads(sys.argv[1] or "{}")
for kind in ("error", "warning"):
    for issue in data.get(kind + "s", []):
        message, where = issue.get("message", issue), issue.get("sourceURL", "")
        print(f"{kind}: {message} {where}".rstrip())
errors, warnings = data.get("errorCount", "?"), data.get("warningCount", "?")
print(f"app: {errors} error(s), {warnings} warning(s)")
sys.exit(0 if errors == 0 and warnings == 0 else 1)' "$summary" || status=1

if [ "$ACTION" != build ]; then
  tests="$(xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null || echo '{}')"
  python3 -c '
import json, sys
data = json.loads(sys.argv[1] or "{}")
for failure in data.get("testFailures", []):
    name = failure.get("testIdentifierString") or failure.get("testName", "?")
    text = failure.get("failureText", "")
    print(f"failed: {name}: {text}")
result, passed = data.get("result", "?"), data.get("passedTests", 0)
failed, skipped = data.get("failedTests", 0), data.get("skippedTests", 0)
print(f"app: tests {result}: {passed} passed, {failed} failed, {skipped} skipped")' "$tests"
fi
echo "app: result bundle $bundle"
exit "$status"
