#!/usr/bin/env bash
# The app's error codes agree with the backend's spec (AGENTS.md Rule 12;
# .claude/rules/common/error-codes.md). Reads the spec copy Packages/AppCore/Sources/APIClient/openapi.json
# and Packages/AppCore/Sources/APIClient/AppProblem.swift:
#   E1 ProblemCode's raw values are exactly the spec's inline Problem.code enum: a code the backend
#      added gets its case (and every exhaustive switch then fails to build until it is mapped)
#   E2 AppProblem.typeBase equals the spec's Problem.type x-problem-type-base; a spec that
#      publishes no base passes with a note (problems then resolve by code)
#   E3 every code, and the generic `unknown`, has its message key problem.<CODE> in a tracked
#      String Catalog (i18n-catalog.mjs then checks it has every locale)
#   E4 the base is an absolute https URI ending in "/", without query or fragment, and every code
#      matches ^[A-Z][A-Z0-9_]*$
# Before the first spec copy there is nothing to compare: it says so and passes.
#
#   bash scripts/check/error-codes.sh
#
# Runs on Linux too (bash and python3). Exit 0 clean, 1 a finding, 2 unreadable input.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

SPEC=Packages/AppCore/Sources/APIClient/openapi.json
PROBLEM=Packages/AppCore/Sources/APIClient/AppProblem.swift
command -v python3 >/dev/null 2>&1 || {
  echo "error-codes: python3 not found" >&2
  exit 2
}
if [ ! -f "$SPEC" ]; then
  echo "error-codes: no spec copy at $SPEC yet; nothing to compare (copy the backend's spec first)"
  exit 0
fi
[ -f "$PROBLEM" ] || {
  echo "error-codes: $PROBLEM is missing; the generated client decodes every problem into it" >&2
  exit 1
}

catalogs=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    catalogs+=("$f")
  done < <(git ls-files -- '*.xcstrings')
fi

python3 - "$SPEC" "$PROBLEM" ${catalogs[@]+"${catalogs[@]}"} <<'PY'
import json, re, sys
from urllib.parse import urlsplit

spec_path, problem_path, catalogs = sys.argv[1], sys.argv[2], sys.argv[3:]
CODE = re.compile(r"^[A-Z][A-Z0-9_]*$")
problems = []


def unreadable(msg):
    print(f"error-codes: {msg}", file=sys.stderr)
    sys.exit(2)


try:
    spec = json.load(open(spec_path, encoding="utf-8"))
except (OSError, ValueError) as err:
    unreadable(f"{spec_path} is not readable JSON ({err})")


def resolve(node):
    ref = node.get("$ref", "") if isinstance(node, dict) else ""
    if ref.startswith("#/components/schemas/"):
        return spec.get("components", {}).get("schemas", {}).get(ref.rsplit("/", 1)[1], {})
    return node if isinstance(node, dict) else {}


schema = spec.get("components", {}).get("schemas", {}).get("Problem")
if not isinstance(schema, dict):
    unreadable(f"{spec_path} has no components.schemas.Problem")
props = schema.get("properties", {})
spec_codes = resolve(props.get("code", {})).get("enum")
if not isinstance(spec_codes, list) or not spec_codes:
    unreadable(f"{spec_path}: Problem.code has no enum to compare with")
base = props.get("type", {}).get("x-problem-type-base") if isinstance(props.get("type"), dict) else None

source = open(problem_path, encoding="utf-8").read()
enum = re.search(r"enum\s+ProblemCode\b[^{]*\{(.*?)\n\}", source, re.S)
if not enum:
    unreadable(f"{problem_path} declares no enum ProblemCode")
app_codes = re.findall(r'^\s*case\s+\w+\s*=\s*"([^"]*)"', enum.group(1), re.M)
app_base = re.search(r'static\s+let\s+typeBase\s*=\s*"([^"]*)"', source)
app_base = app_base.group(1) if app_base else None

# E4 the shapes.
for code in sorted(set(spec_codes) | set(app_codes)):
    if not isinstance(code, str) or not CODE.match(code):
        problems.append(f"E4 {code!r} is not a code (^[A-Z][A-Z0-9_]*$)")
for where, value in ((spec_path, base), (problem_path, app_base)):
    if value is None:
        continue
    parts = urlsplit(value)
    if parts.scheme != "https" or not parts.netloc or parts.query or parts.fragment or not value.endswith("/"):
        problems.append(f"E4 {where}: the problem-type base {value!r} is not an https URI ending in '/'")

# E1 the code lists.
for code in sorted(set(spec_codes) - set(app_codes)):
    problems.append(f"E1 the spec lists {code}; add its ProblemCode case and its message problem.{code}")
for code in sorted(set(app_codes) - set(spec_codes)):
    problems.append(f"E1 ProblemCode lists {code}, which the spec does not; remove it, or update the spec copy")

# E2 the base.
if base is None:
    print("error-codes: the spec publishes no problem-type base; problems resolve by code alone")
elif app_base is None:
    problems.append(f"E2 {problem_path} has no `static let typeBase`; the spec's base is {base}")
elif app_base != base:
    problems.append(f"E2 AppProblem.typeBase is {app_base}, the spec's x-problem-type-base is {base}")

# E3 a message for every code.
keys = set()
for path in catalogs:
    try:
        keys |= set(json.load(open(path, encoding="utf-8")).get("strings", {}))
    except (OSError, ValueError) as err:
        unreadable(f"{path} is not readable JSON ({err})")
for code in sorted(set(app_codes) | {"unknown"}):
    if f"problem.{code}" not in keys:
        problems.append(f"E3 no String Catalog has the key problem.{code} (a manual key with the message)")

for p in problems:
    print(f"error-codes: {p}")
if problems:
    print(f"error-codes: {len(problems)} finding(s); see .claude/rules/common/error-codes.md", file=sys.stderr)
    sys.exit(1)
print(f"error-codes: {len(app_codes)} code(s) agree with {spec_path}, each with its message")
PY
