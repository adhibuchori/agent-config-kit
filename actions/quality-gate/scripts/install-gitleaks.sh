#!/usr/bin/env bash
# Installs one exact gitleaks release for the gate's secret scan and puts it on the job's PATH. The
# archive is checked against the SHA-256 the release's own checksums file lists; a mismatch stops the
# job. A runner with no pinned build here uses a gitleaks already on PATH, and without one the gate
# records its secret scan as a check that did not run (which fails a strict gate).
#
# To move the pin: take the new release's gitleaks_<version>_checksums.txt and replace VERSION and
# the four sums below in one pull request.
set -euo pipefail

VERSION=8.30.1
case "$(uname -s)-$(uname -m)" in
Linux-x86_64) asset=linux_x64 sum=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;;
Linux-aarch64 | Linux-arm64) asset=linux_arm64 sum=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 ;;
Darwin-arm64) asset=darwin_arm64 sum=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5 ;;
Darwin-x86_64) asset=darwin_x64 sum=dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709 ;;
*) asset="" sum="" ;;
esac

if [ -z "$asset" ]; then
  if command -v gitleaks >/dev/null 2>&1; then
    echo "No pinned gitleaks build for $(uname -sm); using $(command -v gitleaks)"
  else
    echo "::warning::no pinned gitleaks build for $(uname -sm) and none on PATH; the secret scan will not run"
  fi
  exit 0
fi

dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/quality-gate-gitleaks-${VERSION}"
mkdir -p "$dir"
archive="$dir/gitleaks.tar.gz"
curl -sSfL --retry 3 -o "$archive" \
  "https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_${asset}.tar.gz"

if command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$archive" | cut -d' ' -f1)
else
  got=$(shasum -a 256 "$archive" | cut -d' ' -f1)
fi
if [ "$got" != "$sum" ]; then
  echo "::error::gitleaks ${VERSION} (${asset}) has SHA-256 ${got}, expected ${sum}; refusing to run it"
  exit 1
fi

tar -xzf "$archive" -C "$dir" gitleaks
rm -f "$archive"
installed=$("$dir/gitleaks" version)
if [ "$installed" != "$VERSION" ] && [ "$installed" != "v$VERSION" ]; then
  echo "::error::the verified archive reports gitleaks '${installed}', expected ${VERSION}"
  exit 1
fi
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$dir" >>"$GITHUB_PATH"
fi
echo "gitleaks ${VERSION} (${asset}) verified and installed at $dir"
