#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit and Serena's writes): format, then lint, the file just written.
# One script, because hooks on one event run in parallel and a separate lint hook would race the
# formatter. A clean file says nothing; a finding reaches Claude as additionalContext.
#
# Every tool is the project's own: node_modules/.bin, .venv/bin, then PATH (resolve_tool). A tool
# the project does not have is skipped, so one copy serves TypeScript and Python repos alike. The
# file comes after `--`, so a name that starts with a dash is never read as an option.
#   *.py, *.pyi                              ruff format, then ruff check
#   *.ts *.tsx *.js *.jsx *.mjs *.cjs        oxfmt, then oxlint and the double-assertion note
#   *.json *.css *.md *.mdx                  oxfmt; *.json is also checked for valid JSON/JSONC
#   *.go                                     golangci-lint fmt, then golangci-lint run on the package of
#                                            the file; without golangci-lint, gofmt -w and go vet
#   *.rs                                     rustfmt on stdin, written back only when it differs (a
#                                            file argument would reformat its child modules too),
#                                            then cargo clippy from a root Cargo.toml, lines on this file
#   *.swift                                  swift-format format (from xcrun first), then swiftlint lint
#   *.xcstrings                              valid JSON, and every key in every locale the catalog
#                                            itself uses, each one translated
#   *.pbxproj                                plutil -lint
# Go and Rust run offline on the toolchain already there: GOTOOLCHAIN=local GOPROXY=off
# GOFLAGS=-mod=readonly, and RUSTUP_AUTO_INSTALL=0 CARGO_NET_OFFLINE=true SQLX_OFFLINE=true.
# Files that change together (localePairs in .claude/agent-config.json, off by default) are noted
# when only one of them changed.
#
# Fails open: feedback on a write that already happened. A missing tool, a payload it cannot read, a
# tool that fails or runs past its cap, a build lock another cargo holds, or a SwiftLint whose
# version differs from the pin in its config means no note, and exit 0.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_start feedback "[post-edit]"
FILE="$(hook_file)"
[[ -n "$FILE" && -f "$FILE" ]] || exit 0
hook_adopt_repo "$FILE"
in_project "$FILE" || exit 0
REL="${FILE#"$ROOT"/}"

NOTES=""
note() {
  NOTES="${NOTES}${NOTES:+$'\n\n'}$*"
}

# Diagnostics are the `path:line:col:` lines, or `path:line:` (the file length of revive has no column).
# Summaries and "All checks passed!" are noise here.
diagnostics() {
  grep -E '^[^[:space:]]+:[0-9]+(:[0-9]+)?:' || true
}

# The diagnostics about this file alone, whether a tool names it by its absolute path or relative to
# the repo, shown relative to the repo. A path with a space survives here.
file_diagnostics() {
  local line rest
  while IFS= read -r line; do
    case "$line" in
    "$FILE:"*) rest="${line#"$FILE:"}" ;;
    "$ROOT/$REL:"*) rest="${line#"$ROOT/$REL:"}" ;;
    "./$REL:"*) rest="${line#"./$REL:"}" ;;
    "$REL:"*) rest="${line#"$REL:"}" ;;
    *) continue ;;
    esac
    [[ "$rest" =~ ^[0-9]+(:[0-9]+)?: ]] && printf '%s:%s\n' "$REL" "$rest"
  done
  return 0
}

# At most 40 lines of findings from one tool: a package-wide run can print hundreds.
capped() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    [[ "$n" -gt 40 ]] || printf '%s\n' "$line"
  done
  [[ "$n" -le 40 ]] || printf '... and %s more\n' "$((n - 40))"
}

# Go and Rust: the toolchain already installed, no network, and no rewrite of go.mod.
case "$REL" in
*.go) export GOTOOLCHAIN=local GOPROXY=off GOFLAGS=-mod=readonly ;;
*.rs) export RUSTUP_AUTO_INSTALL=0 CARGO_NET_OFFLINE=true SQLX_OFFLINE=true CARGO_TERM_COLOR=never ;;
esac

# 1. Format.
case "$REL" in
*.py | *.pyi)
  if RUFF="$(resolve_tool ruff)"; then
    run_capped 15 "$RUFF" format --quiet -- "$REL" >/dev/null 2>&1 || true
  fi
  ;;
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.md | *.mdx)
  if OXFMT="$(resolve_tool oxfmt)"; then
    run_capped 10 "$OXFMT" --write -- "$REL" >/dev/null 2>&1 || true
  fi
  ;;
*.go)
  if GOLANGCI="$(resolve_tool golangci-lint)"; then
    run_capped 10 "$GOLANGCI" fmt -- "$REL" >/dev/null 2>&1 || true
  elif GOFMT="$(resolve_tool gofmt)"; then
    run_capped 10 "$GOFMT" -w -- "$REL" >/dev/null 2>&1 || true
  fi
  ;;
*.rs)
  # Through stdin, so rustfmt formats this file and none of the modules it declares.
  if RUSTFMT="$(resolve_tool rustfmt)" && formatted="$(mktemp "${TMPDIR:-/tmp}/post-edit.XXXXXX" 2>/dev/null)"; then
    if run_capped 5 "$RUSTFMT" --edition 2024 --emit stdout <"$REL" >"$formatted" 2>/dev/null &&
      [[ -s "$formatted" ]] && ! cmp -s "$formatted" "$REL"; then
      cat "$formatted" >"$REL"
    fi
    rm -f "$formatted"
  fi
  ;;
*.swift)
  # The swift-format of Xcode first: the gate runs that one.
  if XCRUN="$(resolve_tool xcrun)" && run_capped 5 "$XCRUN" --find swift-format >/dev/null 2>&1; then
    run_capped 10 "$XCRUN" swift-format format --in-place -- "$REL" >/dev/null 2>&1 || true
  elif SWIFT_FORMAT="$(resolve_tool swift-format)"; then
    run_capped 10 "$SWIFT_FORMAT" format --in-place -- "$REL" >/dev/null 2>&1 || true
  fi
  ;;
esac

# 2. Lint.
case "$REL" in
*.py | *.pyi)
  if RUFF="$(resolve_tool ruff)"; then
    out="$(run_capped 20 "$RUFF" check --output-format concise -- "$REL" 2>&1 | diagnostics)"
    [[ -z "$out" ]] || note "ruff check $REL:"$'\n'"$out"
  fi
  ;;
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs)
  if OXLINT="$(resolve_tool oxlint)"; then
    args=()
    # .oxlintrc.json is found by oxlint itself; oxlint.json has to be named.
    [[ -f oxlint.json ]] && args+=(-c oxlint.json)
    [[ -f .oxlintignore ]] && args+=(--ignore-path=.oxlintignore)
    out="$(run_capped 20 "$OXLINT" ${args[@]+"${args[@]}"} -f unix -- "$REL" 2>&1 | diagnostics)"
    [[ -z "$out" ]] || note "oxlint $REL:"$'\n'"$out"
  fi
  casts="$(grep -nE 'as[[:space:]]+unknown[[:space:]]+as[[:space:]]' -- "$REL" 2>/dev/null)"
  if [[ -n "$casts" ]]; then
    why="A double assertion through unknown hides a type error. Use a real object, a complete fixture, or a narrower parameter"
    [[ -f .claude/rules/typescript/types.md ]] && why="$why (.claude/rules/typescript/types.md)"
    note "$REL has a double assertion through unknown. $why:"$'\n'"$casts"
  fi
  ;;
*.json)
  # tsconfig and oxlint configs are JSONC: comments and trailing commas are valid there. Only an
  # answer of "invalid" makes a note: a python3 that fails says nothing about the file.
  if command -v python3 &>/dev/null; then
    valid="$(python3 -c '
import json, re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    try:
        json.loads(text)
    except ValueError:
        text = re.sub(r"(\"(?:\\.|[^\"\\])*\")|//[^\n]*|/\*.*?\*/", lambda m: m.group(1) or "", text, flags=re.S)
        json.loads(re.sub(r",(\s*[}\]])", r"\1", text))
    print("valid")
except ValueError:
    print("invalid")' "$REL" 2>/dev/null)"
    [[ "$valid" != invalid ]] || note "$REL is not valid JSON."
  fi
  ;;
*.go)
  # A package, not the file: golangci-lint type-checks a lone file without its siblings.
  pkg=.
  [[ "$REL" != */* ]] || pkg="./${REL%/*}"
  if GOLANGCI="$(resolve_tool golangci-lint)"; then
    out="$(run_capped 20 "$GOLANGCI" run --allow-serial-runners --show-stats=false \
      --output.text.print-issued-lines=false --output.text.colors=false -- "$pkg" 2>/dev/null | diagnostics | capped)"
    [[ -z "$out" ]] || note "golangci-lint $pkg:"$'\n'"$out"
  elif GO="$(resolve_tool go)"; then
    out="$(run_capped 20 "$GO" vet "$pkg" 2>&1 | diagnostics | capped)"
    [[ -z "$out" ]] || note "go vet $pkg:"$'\n'"$out"
  fi
  ;;
*.rs)
  # Clippy reports the errors of rustc too. A cold build, or a build lock another cargo holds,
  # outlasts the cap.
  if [[ -f Cargo.toml ]] && CARGO="$(resolve_tool cargo)"; then
    out="$(run_capped 10 "$CARGO" clippy --locked --all-targets --message-format=short 2>&1 | file_diagnostics | capped)"
    [[ -z "$out" ]] || note "cargo clippy $REL:"$'\n'"$out"
  fi
  ;;
*.swift)
  # A SwiftLint other than the swiftlint_version in its config exits 2 with no finding: no note.
  if SWIFTLINT="$(resolve_tool swiftlint)"; then
    out="$(run_capped 10 "$SWIFTLINT" lint --quiet --force-exclude -- "$REL" 2>/dev/null | file_diagnostics | capped)"
    [[ -z "$out" ]] || note "swiftlint $REL:"$'\n'"$out"
  fi
  ;;
*.xcstrings)
  # A String Catalog is JSON. Every key (but one marked shouldTranslate: false) carries every locale
  # the catalog itself uses, and every string in it is translated; the source language may be
  # absent, since the key is its text.
  if command -v python3 &>/dev/null; then
    read -r -d '' CATALOG_PY <<'PY'
import json, sys
try:
    catalog = json.load(open(sys.argv[1], encoding="utf-8"))
except ValueError:
    print("invalid")
    sys.exit()
strings = catalog.get("strings") if isinstance(catalog, dict) else None
if not isinstance(strings, dict):
    sys.exit()
entries = {k: v for k, v in strings.items() if isinstance(v, dict) and v.get("shouldTranslate") is not False}
used = {loc for v in entries.values() if isinstance(v.get("localizations"), dict) for loc in v["localizations"]}
locales = sorted(used - {catalog.get("sourceLanguage")})


def states(node):
    if isinstance(node, dict):
        unit = node.get("stringUnit")
        if isinstance(unit, dict):
            yield unit.get("state") or "no state"
        for key, value in node.items():
            if key != "stringUnit":
                yield from states(value)
    elif isinstance(node, list):
        for value in node:
            yield from states(value)


for key, entry in sorted(entries.items()):
    locs = entry.get("localizations") if isinstance(entry.get("localizations"), dict) else {}
    missing = [loc for loc in locales if loc not in locs]
    if missing:
        print(json.dumps(key) + ": no " + ", ".join(missing))
    for loc in sorted(locs):
        bad = sorted({s for s in states(locs[loc]) if s != "translated"})
        if bad:
            print(json.dumps(key) + ": " + loc + " is " + ", ".join(bad))
PY
    out="$(run_capped 5 python3 -c "$CATALOG_PY" "$REL" 2>/dev/null | capped)"
    if [[ "$out" == invalid ]]; then
      note "$REL is not valid JSON."
    elif [[ -n "$out" ]]; then
      note "$REL has strings that are not translated in every locale the catalog uses:"$'\n'"$out"
    fi
  fi
  ;;
*.pbxproj)
  if PLUTIL="$(resolve_tool plutil)"; then
    # Exit 1 is the verdict of plutil; a cap or a crash says nothing about the file.
    out="$(run_capped 5 "$PLUTIL" -lint -- "$REL" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -ne 1 ]] || note "$REL is not a valid property list, so Xcode cannot open the project:"$'\n'"$out"
  fi
  ;;
esac

# 3. Files that change together, from localePairs: each group is a list of repo-relative files.
changed() {
  git diff --name-only HEAD -- "$1" 2>/dev/null | grep -q . ||
    git diff --cached --name-only -- "$1" 2>/dev/null | grep -q . ||
    git ls-files --others --exclude-standard -- "$1" 2>/dev/null | grep -q .
}
while IFS= read -r line; do
  [[ "$line" == *$'\t'* ]] || continue
  group=()
  mine=""
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    group+=("$member")
    [[ "$member" == "$REL" ]] && mine=1
  done < <(tr '\t' '\n' <<<"$line")
  [[ -n "$mine" ]] || continue
  for other in "${group[@]}"; do
    [[ "$other" != "$REL" ]] || continue
    changed "$other" || note "$REL changed but $other did not. These files change in the same commit (localePairs)."
  done
done < <(hook_config localePairs 2>/dev/null)

# 4. Alembic scaffolding is hand-edited legitimately, but it shapes every future revision.
if [[ -f alembic.ini && "$REL" =~ (^|/)(env\.py|script\.py\.mako)$ && -d "$(dirname "$REL")/versions" ]]; then
  note "$REL is Alembic scaffolding: this change affects every future revision."
fi

report "$NOTES"
exit 0
