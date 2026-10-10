#!/usr/bin/env bash
# The Xcode project's build settings live in Config/*.xcconfig, and say what the rules need
# (AGENTS.md Rules 19, 20 and 28; .claude/rules/ios/swiftui.md).
#   X1 project.pbxproj parses (plutil), and each project-level configuration names an xcconfig under
#      Config/ as its base configuration (setup's by-hand step)
#   X2 no build configuration in project.pbxproj sets a SWIFT_* key: the project file keeps target
#      identity, the xcconfig files keep settings
#   X3 through each base xcconfig and its #include files: SWIFT_VERSION 6, approachable concurrency,
#      MainActor default isolation, Swift warnings as errors, SWIFT_PACKAGE_NAME appcore (the app
#      reads the logic package's `package` API), IPHONEOS_DEPLOYMENT_TARGET 17.0 or later
#   X4 no tracked property list turns App Transport Security off (NSAllowsArbitraryLoads*)
#   X5 no xcconfig key that names a secret (token, secret, password, API or private key) holds a
#      value: every build setting can reach the built app
#
#   bash scripts/check/xcode-settings.sh
#
# macOS only: project.pbxproj is an old-style plist that only plutil reads. Exit 0 clean, 1 a
# finding, 2 no plutil or no python3.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

for tool in plutil python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "xcode-settings: $tool not found; this check runs on a Mac" >&2
    exit 2
  }
done

projects=()
plists=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    projects+=("$f")
  done < <(git ls-files -- '*.xcodeproj/project.pbxproj')
  while IFS= read -r f; do
    plists+=("$f")
  done < <(git ls-files -- '*.plist')
else
  while IFS= read -r f; do
    projects+=("${f#./}")
  done < <(find . -path ./.build -prune -o -path '*.xcodeproj/project.pbxproj' -print)
fi
if [ ${#projects[@]} -eq 0 ]; then
  echo "xcode-settings: X1 no *.xcodeproj is tracked; create the app project in Xcode and link Config/*.xcconfig"
  exit 1
fi

status=0
for pbx in "${projects[@]}"; do
  if ! json="$(plutil -convert json -o - -- "$pbx" 2>&1)"; then
    echo "xcode-settings: X1 $pbx does not parse: $json"
    status=1
    continue
  fi
  python3 - "$pbx" "$json" <<'PY' || status=1
import json, os, re, sys

pbx, data = sys.argv[1], json.loads(sys.argv[2])
objects, root = data["objects"], data["objects"][data["rootObject"]]
problems = []

# The path of a file reference: its group chain, joined, from the project folder.
parents = {}
for oid, obj in objects.items():
    for child in obj.get("children", []):
        parents[child] = oid
def path_of(oid):
    parts, node = [], oid
    while node in objects:
        obj = objects[node]
        if obj.get("path"):
            parts.append(obj["path"])
        if obj.get("sourceTree") not in (None, "<group>"):
            break
        node = parents.get(node)
    return os.path.normpath(os.path.join(os.path.dirname(os.path.dirname(pbx)), *reversed(parts)))

# xcconfig KEY = VALUE pairs, following #include (and #include?) relative to the including file.
def settings(path, seen=None):
    seen = seen if seen is not None else set()
    out = {}
    if path in seen or not os.path.isfile(path):
        return out
    seen.add(path)
    for raw in open(path, encoding="utf-8").read().splitlines():
        line = raw.split("//", 1)[0].strip()
        inc = re.match(r'#include\??\s+"([^"]+)"', line)
        if inc:
            out.update(settings(os.path.normpath(os.path.join(os.path.dirname(path), inc.group(1))), seen))
            continue
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?\s*=\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(3).strip()
    return out

def version(value):
    try:
        return tuple(int(x) for x in value.split("."))
    except ValueError:
        return ()

REQUIRED = {
    "SWIFT_VERSION": (lambda v: version(v)[:1] == (6,), "6.0"),
    "SWIFT_APPROACHABLE_CONCURRENCY": (lambda v: v == "YES", "YES"),
    "SWIFT_DEFAULT_ACTOR_ISOLATION": (lambda v: v == "MainActor", "MainActor"),
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": (lambda v: v == "YES", "YES"),
    "SWIFT_PACKAGE_NAME": (lambda v: v == "appcore", "appcore (the app reads Packages/AppCore's package API)"),
    "IPHONEOS_DEPLOYMENT_TARGET": (lambda v: version(v) >= (17,), "17.0 or later"),
}

for cid in objects[root["buildConfigurationList"]]["buildConfigurations"]:
    config = objects[cid]
    name, ref = config.get("name", cid), config.get("baseConfigurationReference")
    if not ref:
        problems.append(f"X1 the project's {name} configuration has no base xcconfig; set Config/{name}.xcconfig")
        continue
    path = path_of(ref)
    if not path.startswith("Config/") or not path.endswith(".xcconfig"):
        problems.append(f"X1 the project's {name} configuration is based on {path}, not an xcconfig under Config/")
        continue
    found = settings(path)
    for key, (ok, want) in REQUIRED.items():
        if not ok(found.get(key, "")):
            problems.append(f"X3 {path} (the project's {name}): {key} is {found.get(key, 'unset')!r}, want {want}")

for oid, obj in sorted(objects.items()):
    if obj.get("isa") != "XCBuildConfiguration":
        continue
    for key in sorted(k for k in obj.get("buildSettings", {}) if k.startswith("SWIFT_")):
        problems.append(f"X2 {pbx}: the {obj.get('name')} configuration {oid} sets {key}; move it to Config/*.xcconfig")

for p in problems:
    print(f"xcode-settings: {p}")
sys.exit(1 if problems else 0)
PY
done

# X4: App Transport Security stays on.
for plist in ${plists[@]+"${plists[@]}"}; do
  json="$(plutil -convert json -o - -- "$plist" 2>/dev/null)" || continue
  if python3 -c '
import json, sys
def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key.startswith("NSAllowsArbitraryLoads") and value is True:
                return True
            if walk(value):
                return True
    elif isinstance(node, list):
        return any(walk(v) for v in node)
    return False
sys.exit(0 if walk(json.loads(sys.argv[1])) else 1)' "$json"; then
    echo "xcode-settings: X4 $plist turns App Transport Security off (NSAllowsArbitraryLoads); use HTTPS"
    status=1
  fi
done

# X5: no secret in a build setting.
while IFS= read -r hit; do
  echo "xcode-settings: X5 $hit: a build setting reaches the built app; keep secrets out of xcconfig files"
  status=1
done < <(find Config -name '*.xcconfig' -type f -exec grep -nHiE '^[[:space:]]*[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY)[A-Z0-9_]*[[:space:]]*=[[:space:]]*[^[:space:]]' {} + 2>/dev/null)

[ "$status" -eq 0 ] && echo "xcode-settings: ${#projects[@]} project(s): settings in Config/, Swift 6, warnings as errors, ATS on"
exit "$status"
