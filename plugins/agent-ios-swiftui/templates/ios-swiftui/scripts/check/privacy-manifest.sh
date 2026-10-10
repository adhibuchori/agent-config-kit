#!/usr/bin/env bash
# The privacy manifest names a reason for every required-reason API the app's code uses (AGENTS.md
# Rule 25). App Store Connect refuses an upload that uses one of these APIs without a reason in
# App/PrivacyInfo.xcprivacy; this finds the use first.
#   M1 App/PrivacyInfo.xcprivacy exists and is a plist (XML or binary) whose NSPrivacyAccessedAPITypes
#      entries each name a category and at least one reason
#   M2 every category the tracked Swift code uses (tests and generated code aside) is declared
# The API names per category are Apple's NSPrivacyAccessedAPIType reference (Swift and Objective-C
# spellings; @AppStorage reads UserDefaults). A declared category no code uses is listed, never
# failed: a linked SDK may use it.
#
#   bash scripts/check/privacy-manifest.sh
#
# Reads the plist with python3's plistlib, so it runs on Linux too. Exit 0 clean, 1 a finding,
# 2 unreadable input.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

MANIFEST=App/PrivacyInfo.xcprivacy
command -v python3 >/dev/null 2>&1 || {
  echo "privacy-manifest: python3 not found" >&2
  exit 2
}
files=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    case "$f" in */Tests/* | UITests/* | */UITests/* | */GeneratedSources/*) continue ;; esac
    files+=("$f")
  done < <(git ls-files -- '*.swift')
fi

python3 - "$MANIFEST" ${files[@]+"${files[@]}"} <<'PY'
import plistlib, re, sys

manifest, sources = sys.argv[1], sys.argv[2:]
PREFIX = "NSPrivacyAccessedAPICategory"
# FileAttributeKey members are matched as keys (FileAttributeKey.x, or .x inside a subscript or a
# list), so a model's own `creationDate` property is not taken for the file attribute.
APIS = {
    "FileTimestamp": r"(FileAttributeKey\.|[\[,]\s*\.)(creationDate|modificationDate)\b"
                     r"|\b(fileModificationDate|contentModificationDateKey|creationDateKey"
                     r"|NSFileCreationDate|NSFileModificationDate|NSURLContentModificationDateKey|NSURLCreationDateKey)\b"
                     r"|\b(getattrlist|getattrlistbulk|fgetattrlist|getattrlistat|stat|fstat|fstatat|lstat)\s*\(",
    "SystemBootTime": r"\bsystemUptime\b|\bmach_absolute_time\s*\(",
    "DiskSpace": r"(FileAttributeKey\.|[\[,]\s*\.)(systemFreeSize|systemSize)\b"
                 r"|\b(volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey"
                 r"|volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey"
                 r"|NSURLVolumeAvailableCapacityKey|NSFileSystemFreeSize|NSFileSystemSize)\b"
                 r"|\b(statfs|statvfs|fstatfs|fstatvfs|getattrlist|fgetattrlist|getattrlistat)\s*\(",
    "ActiveKeyboards": r"\bactiveInputModes\b",
    "UserDefaults": r"\b(UserDefaults|NSUserDefaults)\b|@AppStorage\b",
}
# getattrlist and its siblings read timestamps or disk space: either declared category covers them.
EITHER = re.compile(r"\b(getattrlist|fgetattrlist|getattrlistat)\s*\(")
problems = []

try:
    with open(manifest, "rb") as fh:
        data = plistlib.load(fh)
except FileNotFoundError:
    print(f"privacy-manifest: M1 {manifest} is missing; the app target ships a privacy manifest")
    sys.exit(1)
except Exception as err:  # plistlib raises several types for a malformed file
    print(f"privacy-manifest: M1 {manifest} is not a readable plist ({err})")
    sys.exit(1)

declared = set()
entries = data.get("NSPrivacyAccessedAPITypes", []) if isinstance(data, dict) else None
if not isinstance(entries, list):
    problems.append(f"M1 {manifest}: NSPrivacyAccessedAPITypes is not a list")
    entries = []
for i, entry in enumerate(entries):
    kind = entry.get("NSPrivacyAccessedAPIType") if isinstance(entry, dict) else None
    reasons = entry.get("NSPrivacyAccessedAPITypeReasons") if isinstance(entry, dict) else None
    if not isinstance(kind, str) or not kind.startswith(PREFIX):
        problems.append(f"M1 {manifest}: entry {i} names no NSPrivacyAccessedAPIType category")
        continue
    if not isinstance(reasons, list) or not reasons or not all(isinstance(r, str) and r for r in reasons):
        problems.append(f"M1 {manifest}: {kind} lists no reason (NSPrivacyAccessedAPITypeReasons)")
    declared.add(kind[len(PREFIX):])

used = {}
for path in sources:
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for n, line in enumerate(lines, 1):
        code = line.split("//", 1)[0]
        for category, pattern in APIS.items():
            if re.search(pattern, code):
                used.setdefault(category, []).append((path, n, line.strip()))

for category, places in sorted(used.items()):
    if category in declared:
        continue
    for path, n, text in places:
        if EITHER.search(text) and declared & {"FileTimestamp", "DiskSpace"}:
            continue
        problems.append(f"M2 {path}:{n} uses a {category} API ({text[:80]}); declare {PREFIX}{category} "
                        f"with its reason in {manifest}")

for category in sorted(declared - set(used)):
    print(f"privacy-manifest: {PREFIX}{category} is declared, and no tracked code uses it (an SDK may)")
for p in problems:
    print(f"privacy-manifest: {p}")
if problems:
    sys.exit(1)
print(f"privacy-manifest: {len(sources)} Swift file(s) read; every required-reason API in use is declared")
PY
