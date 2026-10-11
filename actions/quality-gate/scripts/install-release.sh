#!/usr/bin/env bash
# Installs the exact releases tools.lock pins for the gate (golangci-lint, squawk, the cargo tools,
# SwiftLint, Periphery) and puts each on the job's PATH. Every download is checked against the
# sha256 in tools.lock before anything in it runs, and the installed binary must then report the
# pinned version; either mismatch stops the job. The pattern is install-gitleaks.sh's.
#
#   install-release.sh <tool>...        (or the tools in $QG_TOOLS, space-separated)
#
# A platform with no row for a tool installs nothing for it and says so: a tool already on PATH is
# used, and otherwise the check that needs it records that it did not run (which fails a strict
# gate). QG_PLATFORM (linux-x64, linux-arm64, darwin-arm64, darwin-x64) and QG_TOOLS_LOCK override
# what is detected and read, for tests.
# Exit 0 installed (or reported as unavailable here), 1 a download, checksum or version failed,
# 2 a tool tools.lock does not know, or an unreadable table.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lock="${QG_TOOLS_LOCK:-$here/tools.lock}"

if [ $# -eq 0 ]; then
  read -r -a tools <<<"${QG_TOOLS:-}"
else
  tools=("$@")
fi
if [ ${#tools[@]} -eq 0 ]; then
  echo "install-release: no tool named; nothing to install"
  exit 0
fi
[ -r "$lock" ] || {
  echo "::error::install-release: cannot read $lock" >&2
  exit 2
}

platform="${QG_PLATFORM:-}"
if [ -z "$platform" ]; then
  case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) platform=linux-x64 ;;
  Linux-aarch64 | Linux-arm64) platform=linux-arm64 ;;
  Darwin-arm64) platform=darwin-arm64 ;;
  Darwin-x86_64) platform=darwin-x64 ;;
  *) platform="unknown-$(uname -s)-$(uname -m)" ;;
  esac
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# version_says <tool> <binary> <version>: the binary runs and reports exactly that version. A cargo
# subcommand binary wants its subcommand name first. The install folder's own name holds the
# version too, so it is cut out of the output before the match (a loader error that prints the path
# must not pass).
version_says() {
  local args=(--version) out rc
  case "$1" in
  golangci-lint | swiftlint | periphery) args=(version) ;;
  cargo-llvm-cov) args=(llvm-cov --version) ;;
  cargo-nextest) args=(nextest --version) ;;
  cargo-deny) args=(deny --version) ;;
  esac
  out=$("$2" "${args[@]}" 2>&1)
  rc=$?
  out=${out//"$(dirname "$2")"/}
  printf '%s\n' "$out" | head -3
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -Eq "(^|[^0-9.])v?${3//./\\.}([^0-9.]|$)"
}

root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
root="${root%/}/quality-gate-tools"
status=0

for tool in "${tools[@]}"; do
  known=0 row=""
  while read -r t v p f s src member _; do
    case "$t" in '' | '#'*) continue ;; esac
    [ "$t" = "$tool" ] || continue
    known=1
    if [ "$p" = "$platform" ] || [ "$p" = any ]; then
      row="$v $f $s $src $member"
      break
    fi
  done <"$lock"
  if [ "$known" -eq 0 ]; then
    echo "::error::install-release: $tool is not in $(basename "$lock")" >&2
    exit 2
  fi
  if [ -z "$row" ]; then
    if command -v "$tool" >/dev/null 2>&1; then
      echo "No pinned $tool build for $platform; using $(command -v "$tool")"
    else
      echo "::warning::no pinned $tool build for $platform and none on PATH; the check that needs it will not run"
    fi
    continue
  fi
  read -r version format sum src member <<<"$row"

  dir="$root/$tool-$version"
  rm -rf "$dir"
  mkdir -p "$dir/unpacked" || exit 1
  bindir="$dir"

  if [ "$format" = cargo ]; then
    if ! command -v cargo >/dev/null 2>&1; then
      echo "::error::$tool $version is built with cargo install, and this runner has no cargo"
      status=1
      continue
    fi
    # --locked: the dependency versions the crate was published with, each checked by cargo
    # against the registry's checksum; --root keeps it out of ~/.cargo.
    if ! cargo install --locked --quiet --root "$dir" "$src" --version "$version" \
      --no-default-features --features "$member"; then
      echo "::error::cargo install of $src $version failed"
      status=1
      continue
    fi
    bindir="$dir/bin"
    probe="$bindir/${src%-cli}"
    [ -x "$probe" ] || probe="$bindir/$src"
  else
    archive="$dir/download"
    if ! curl -sSfL --retry 3 -o "$archive" "$src"; then
      echo "::error::could not download $tool $version ($platform) from $src"
      status=1
      continue
    fi
    got=$(sha256_of "$archive")
    if [ "$got" != "$sum" ]; then
      echo "::error::$tool $version ($platform) has SHA-256 $got, expected $sum; refusing to run it"
      rm -f "$archive"
      status=1
      continue
    fi
    # member: the binary, then any file it loads from its own folder (Periphery's libIndexStore).
    IFS=, read -r -a members <<<"$member"
    case "$format" in
    bin) mv "$archive" "$dir/$tool" ;;
    tar.gz) tar -xzf "$archive" -C "$dir/unpacked" "${members[@]}" ;;
    zip) unzip -q -o "$archive" "${members[@]}" -d "$dir/unpacked" ;;
    *)
      echo "::error::install-release: $tool has an unknown format '$format' in $(basename "$lock")" >&2
      exit 2
      ;;
    esac
    if [ "$format" != bin ]; then
      for m in "${members[@]}"; do
        if [ ! -f "$dir/unpacked/$m" ]; then
          echo "::error::$tool $version: the verified archive has no $m"
          status=1
          continue 2
        fi
      done
      mv "$dir/unpacked/${members[0]}" "$dir/$tool"
      for m in "${members[@]:1}"; do
        mv "$dir/unpacked/$m" "$dir/$(basename "$m")"
      done
    fi
    rm -rf "$archive" "$dir/unpacked"
    chmod +x "$dir/$tool"
    probe="$dir/$tool"
  fi

  if ! version_says "$tool" "$probe" "$version"; then
    echo "::error::the verified $tool does not report version $version"
    status=1
    continue
  fi
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$bindir" >>"$GITHUB_PATH"
  fi
  echo "$tool $version ($platform) verified and installed at $bindir"
done
exit "$status"
