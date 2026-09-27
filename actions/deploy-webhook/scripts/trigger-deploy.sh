#!/usr/bin/env bash
# trigger-deploy.sh: start a deploy by POSTing to the deploy platform's webhook, and fail loudly
# when the platform declines it.
#
# Usage: bash scripts/deploy/trigger-deploy.sh <ref>
#   ref  what to deploy: refs/heads/<branch> or refs/tags/<tag>, or $DEPLOY_REF when the argument
#        is absent. There is no default: the branch a deploy takes is always named.
#
# It uses the network, and only when you run it: one POST (plus retries) to DEPLOY_WEBHOOK_URL.
# Run it in your own terminal, where the secret URL is exported; never paste the URL into a prompt.
#
# Environment:
#   DEPLOY_WEBHOOK_URL      required, https only. It is a secret: whoever holds it can deploy.
#                           This script never prints it and never puts it on a command line.
#   DEPLOY_RETRY_DELAYS     seconds to wait before each retry (default "30 90 180": a platform that
#                           is busy building refuses connections for a few minutes). "" = no retry.
#   DEPLOY_WEBHOOK_TIMEOUT  seconds per attempt (default 60)
#
# Exit: 0 the platform accepted the deploy (HTTP 2xx); 1 it declined (3xx or 4xx, never retried)
# or stayed unreachable (no answer or 5xx after every retry); 2 usage or configuration error.
#
# Accepted is not deployed. Confirm a deployment newer than the merge afterwards: the platform's
# deployment list, or verify-deploy.sh --pr <n> where the host reports deployments to GitHub.
set -uo pipefail

err() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::error::%s\n' "$*"
  else
    printf 'trigger-deploy: %s\n' "$*" >&2
  fi
}

REF="${1:-${DEPLOY_REF:-}}"
if [ -z "$REF" ]; then
  err "name the ref to deploy: trigger-deploy.sh refs/heads/<branch> (or set DEPLOY_REF)"
  exit 2
fi
case "$REF" in
  refs/heads/?* | refs/tags/?*) ;;
  *)
    err "the ref must look like refs/heads/<branch> or refs/tags/<tag>"
    exit 2
    ;;
esac
case "$REF" in
  *[!A-Za-z0-9._/-]* | *..* | *//* | */)
    err "the ref holds characters a git ref cannot carry"
    exit 2
    ;;
esac

url="${DEPLOY_WEBHOOK_URL:-}"
if [ -z "$url" ]; then
  err "DEPLOY_WEBHOOK_URL is not set; refusing to skip the deploy silently."
  exit 2
fi
case "$url" in
  https://?*) ;;
  *)
    err "DEPLOY_WEBHOOK_URL must be an https:// URL: the webhook is a secret and never travels in plain text."
    exit 2
    ;;
esac
case "$url" in
  *[[:space:]\"\\]*)
    err "DEPLOY_WEBHOOK_URL holds whitespace, a quote or a backslash."
    exit 2
    ;;
esac

timeout="${DEPLOY_WEBHOOK_TIMEOUT:-60}"
case "$timeout" in
  '' | *[!0-9]*)
    err "DEPLOY_WEBHOOK_TIMEOUT must be whole seconds."
    exit 2
    ;;
esac

read -r -a delays <<<"${DEPLOY_RETRY_DELAYS-30 90 180}"
for delay in ${delays[@]+"${delays[@]}"}; do
  case "$delay" in
    *[!0-9]*)
      err "DEPLOY_RETRY_DELAYS must be whole seconds separated by spaces."
      exit 2
      ;;
  esac
done
attempts=$((${#delays[@]} + 1))

tmp="$(mktemp -d "${TMPDIR:-/tmp}/trigger-deploy.XXXXXX")" || {
  err "cannot create a temporary folder"
  exit 2
}
trap 'rm -rf "$tmp"' EXIT
# The URL goes to curl through a config file in a private folder, not argv: argv is visible to
# every user of the machine.
(
  umask 077
  printf 'url = "%s"\n' "$url" >"$tmp/curl.cfg"
)

# Webhooks that read the branch from a GitHub push payload need this header and ref; without them
# some answer with a 3xx that deploys nothing.
payload="{\"ref\":\"${REF}\",\"commits\":[]}"

attempt=1
while :; do
  code="$(curl -q -sS --config "$tmp/curl.cfg" --proto '=https' \
    --max-time "$timeout" -o "$tmp/body" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H 'X-GitHub-Event: push' \
    --data "$payload" 2>/dev/null)"
  rc=$?
  case "$code" in
    [0-9][0-9][0-9]) ;;
    *) code=000 ;;
  esac
  # The platform's answer, bounded and stripped of control characters. curl's own error text is
  # not shown: it can repeat the host of the secret URL.
  body=""
  if [ -f "$tmp/body" ]; then
    body="$(head -c 300 "$tmp/body" | LC_ALL=C tr -c '[:print:]' ' ')"
    rm -f "$tmp/body"
  fi
  if [ "$code" = "000" ]; then
    echo "attempt ${attempt}/${attempts}: no answer (curl exit ${rc})"
  else
    echo "attempt ${attempt}/${attempts}: HTTP ${code} ${body}"
  fi

  case "$code" in
    2??)
      echo "The deploy platform accepted the deploy of ${REF}. Accepted is not deployed: confirm a deployment newer than the merge."
      exit 0
      ;;
    000 | 5??) ;;
    *)
      # A 3xx is the platform declining on purpose, and curl's --fail flags let 3xx pass as
      # success, so the status is checked here. Retrying a refusal cannot help.
      err "The deploy platform declined the deploy of ${REF} (HTTP ${code})."
      exit 1
      ;;
  esac

  if [ "$attempt" -ge "$attempts" ]; then
    break
  fi
  wait_s="${delays[$((attempt - 1))]}"
  echo "No answer from the deploy platform; retrying in ${wait_s}s."
  sleep "$wait_s"
  attempt=$((attempt + 1))
done

err "The deploy platform did not accept the deploy of ${REF} after ${attempts} attempts."
exit 1
