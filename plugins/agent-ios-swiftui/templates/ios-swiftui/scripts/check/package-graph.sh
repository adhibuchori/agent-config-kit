#!/usr/bin/env bash
# The logic packages keep the shape the rules describe (AGENTS.md Rules 1, 2, 21 and 22;
# .claude/rules/ios/packages.md). Reads each Packages/*/Package.swift through
# `swift package dump-package` (it evaluates the manifest and resolves nothing) and
# scripts/check/package-graph.json:
#   P1 Packages/AppCore/Package.swift exists: the app's logic lives in a package
#   P2 every library target is listed under "layers" and imports only the targets listed for it
#   P3 every library target has a test target that depends on it, named after it (<Target>Tests)
#   P4 every remote package is pinned with `exact:`, and Package.resolved is tracked
#   P5 no build-tool plugin and no macro target unless "plugins" names it with its decision
#   P6 the app project's own pins (*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/
#      Package.resolved, which xcodebuild reads) are tracked and name the same version of every
#      package both files list: `swift test` and the app build then compile the same code
#
#   bash scripts/check/package-graph.sh
#
# macOS (or any machine with a Swift toolchain). Exit 0 clean, 1 a finding, 2 no swift or python3,
# or an unreadable manifest.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

CONFIG=scripts/check/package-graph.json
for tool in swift python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "package-graph: $tool not found" >&2
    exit 2
  }
done
[ -f Packages/AppCore/Package.swift ] || {
  echo "package-graph: P1 Packages/AppCore/Package.swift is missing; the app's logic lives in that package (Rule 1)"
  exit 1
}
[ -f "$CONFIG" ] || {
  echo "package-graph: $CONFIG is missing; it lists each target's allowed imports" >&2
  exit 2
}

status=0
errors="$(mktemp "${TMPDIR:-/tmp}/package-graph.XXXXXX")"
trap 'rm -f "$errors"' EXIT
while IFS= read -r manifest; do
  pkg="$(dirname "$manifest")"
  if ! dump="$(swift package --package-path "$pkg" dump-package 2>"$errors")"; then
    echo "package-graph: $pkg/Package.swift does not evaluate:" >&2
    tail -20 "$errors" >&2
    exit 2
  fi
  resolved=0
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$(git ls-files -- "$pkg/Package.resolved")" ]; then
    resolved=1
  fi
  python3 - "$pkg" "$dump" "$CONFIG" "$resolved" <<'PY' || status=1
import json, sys

pkg, dump, config_path, resolved = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3], sys.argv[4] == "1"
config = json.load(open(config_path, encoding="utf-8"))
layers, plugins = config.get("layers", {}), config.get("plugins", {})
targets = {t["name"]: t for t in dump.get("targets", [])}
problems = []

def internal_deps(target):
    out = []
    for dep in target.get("dependencies", []):
        for kind in ("byName", "target"):
            if kind in dep and dep[kind][0] in targets:
                out.append(dep[kind][0])
    return out

libraries = [n for n, t in targets.items() if t.get("type") == "regular"]
tests = [t for t in targets.values() if t.get("type") == "test"]
for name in sorted(libraries):
    if name not in layers:
        problems.append(f"P2 {pkg}: target {name} is not under \"layers\" in {config_path}; add it with the targets it may import")
        continue
    for dep in internal_deps(targets[name]):
        if dep not in layers[name]:
            problems.append(f"P2 {pkg}: {name} imports {dep}, which {config_path} does not allow it (Rule 2)")
    if not any(t["name"] == f"{name}Tests" and name in internal_deps(t) for t in tests):
        problems.append(f"P3 {pkg}: library target {name} has no test target {name}Tests that depends on it (Rule 22)")

remote = False
for dep in dump.get("dependencies", []):
    for source in dep.get("sourceControl", []):
        remote = True
        if "exact" not in source.get("requirement", {}):
            problems.append(f"P4 {pkg}: {source.get('identity')} is not pinned with exact: (Rule 21)")
if remote and not resolved:
    problems.append(f"P4 {pkg}: Package.resolved is not tracked; commit it so every build resolves the same versions")

for target in targets.values():
    if target.get("type") == "macro" and target["name"] not in plugins:
        problems.append(f"P5 {pkg}: macro target {target['name']} needs a decision under \"plugins\" in {config_path}")
    for usage in target.get("pluginUsages") or []:
        name = next(iter(usage.values()))[0]
        if name not in plugins:
            problems.append(f"P5 {pkg}: {target['name']} runs the build-tool plugin {name}, which no decision under \"plugins\" allows")

for p in problems:
    print(f"package-graph: {p}")
if not problems:
    print(f"package-graph: {pkg}: {len(libraries)} library target(s), each layered and tested; every remote package exact")
sys.exit(1 if problems else 0)
PY
done < <(find Packages -mindepth 2 -maxdepth 2 -name Package.swift | sort)

# P6: the pins xcodebuild resolves from agree with the pins `swift test` resolves from.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pins=()
  while IFS= read -r f; do
    pins+=("$f")
  done < <(git ls-files -- '*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved' \
    'Packages/*/Package.resolved')
  python3 - ${pins[@]+"${pins[@]}"} <<'PY' || status=1
import json, sys

files = sys.argv[1:]
projects = [f for f in files if ".xcodeproj/" in f]
packages = [f for f in files if f not in projects]
def pins(path):
    return {p["identity"]: p.get("state", {}).get("version") or p.get("state", {}).get("revision")
            for p in json.load(open(path, encoding="utf-8")).get("pins", [])}
problems = []
if packages and not projects:
    problems.append("P6 the app project's Package.resolved is not tracked; resolve once (Xcode, or "
                    "xcodebuild -resolvePackageDependencies) and commit it: CI builds only from it")
for project in projects:
    mine = pins(project)
    for package in packages:
        for identity, version in sorted(pins(package).items()):
            if identity in mine and mine[identity] != version:
                problems.append(f"P6 {identity} is {mine[identity]} in {project} and {version} in {package}; "
                                "resolve both again")
for p in problems:
    print(f"package-graph: {p}")
sys.exit(1 if problems else 0)
PY
fi
exit "$status"
