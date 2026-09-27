#!/usr/bin/env bash
# notify-docs.sh: after a deploy was accepted, tell a docs site that the application shipped, by
# sending the repository_dispatch event `app-deployed` to the docs repository. agent-docs-nextra's
# changelog.yaml answers that event by regenerating its pages.
#
# Environment:
#   DOCS_REPOSITORY      owner/name of the docs repository. Empty: nothing to do (exit 0).
#   DOCS_DISPATCH_TOKEN  a token that may send events to that repository (contents: write on it).
#                        Empty while DOCS_REPOSITORY is set: a warning, and nothing is sent.
#   GITHUB_API_URL       default https://api.github.com
#
# Exit: 0 sent, or nothing to send; 1 GitHub refused the event; 2 usage.
set -uo pipefail

err() { if [ "${GITHUB_ACTIONS:-}" = "true" ]; then printf '::error::%s\n' "$*"; else printf 'notify-docs: %s\n' "$*" >&2; fi; }
warn() { if [ "${GITHUB_ACTIONS:-}" = "true" ]; then printf '::warning::%s\n' "$*"; else printf 'notify-docs: warning: %s\n' "$*" >&2; fi; }

repo="${DOCS_REPOSITORY:-}"
[ -n "$repo" ] || exit 0
case "$repo" in
  */*/* | /* | */ | .* | */.* | *..* | *[!A-Za-z0-9._/-]*)
    err "docs-repository must be owner/name"
    exit 2
    ;;
  */*) ;;
  *)
    err "docs-repository must be owner/name"
    exit 2
    ;;
esac
token="${DOCS_DISPATCH_TOKEN:-}"
if [ -z "$token" ]; then
  warn "docs-repository is $repo but DOCS_DISPATCH_TOKEN is not set; the docs site was not told about this deploy."
  exit 0
fi
case "$token" in
  *[[:space:]\"\\]*)
    err "DOCS_DISPATCH_TOKEN holds whitespace, a quote or a backslash"
    exit 2
    ;;
esac
api="${GITHUB_API_URL:-https://api.github.com}"
case "$api" in
  https://?*) ;;
  *)
    err "GITHUB_API_URL must be an https:// URL"
    exit 2
    ;;
esac

tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/notify-docs.XXXXXX")" || {
  err "cannot create a temporary folder"
  exit 2
}
trap 'rm -rf "$tmp"' EXIT
# The token reaches curl through a config file in a private folder, never through argv.
(
  umask 077
  printf 'header = "Authorization: Bearer %s"\n' "$token" >"$tmp/curl.cfg"
)
code="$(curl -q -sS --proto '=https' --max-time 30 --config "$tmp/curl.cfg" -X POST \
  -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
  -H 'Content-Type: application/json' --data '{"event_type":"app-deployed"}' \
  -o "$tmp/body" -w '%{http_code}' "$api/repos/$repo/dispatches" 2>/dev/null)"
case "$code" in
  204)
    echo "Sent app-deployed to $repo."
    exit 0
    ;;
  *)
    err "GitHub did not accept app-deployed for $repo (HTTP ${code:-000}): $(head -c 200 "$tmp/body" 2>/dev/null | LC_ALL=C tr -c '[:print:]' ' '). The deploy itself was accepted."
    exit 1
    ;;
esac
