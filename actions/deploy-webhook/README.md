# deploy-webhook action

Starts a deploy from CI by POSTing to your deploy platform's webhook, and fails when the platform
declines it. For platforms that build from git and deploy when a webhook is called.

agent-deploy's `/agent-deploy:setup` installs a caller when you answer `deploy-on-merge=yes`. The
caller runs the reusable workflow
[`.github/workflows/deploy-webhook.yml`](../../.github/workflows/deploy-webhook.yml) when a pull
request is merged into the production branch, and that workflow runs this action.

## What it does

1. `scripts/trigger-deploy.sh`, the same file agent-deploy installs as
   `scripts/deploy/trigger-deploy.sh` (a test keeps the two identical): one POST with a push-shaped
   payload (`{"ref": "refs/heads/<branch>", "commits": []}` and the header `X-GitHub-Event: push`),
   which platforms that read the branch from a GitHub push need. https only; the URL reaches curl
   through a private file, never the command line, and is never printed. A 2xx is accepted. A 3xx
   or 4xx is a refusal and fails the job at once (a bare curl reports a 3xx as success). No answer
   or a 5xx is retried after 30, 90 and 180 seconds.
2. `scripts/notify-docs.sh`, when `docs-repository` is set: sends the `repository_dispatch` event
   `app-deployed` to that repository, which agent-docs-nextra's `changelog.yaml` answers by
   regenerating its pages. Without `docs-token` it warns and sends nothing.

Accepted is not deployed: confirm the deployment with `/agent-deploy:verify-deploy`, or in your
platform's own list.

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `webhook-url` | (required) | The deploy webhook URL; a secret |
| `ref` | (required) | `refs/heads/<branch>` or `refs/tags/<tag>` |
| `retry-delays` | `30 90 180` | Seconds before each retry; empty turns retries off |
| `webhook-timeout` | `60` | Seconds per attempt |
| `docs-repository` | empty | `owner/name` to send `app-deployed` to |
| `docs-token` | empty | A token that may send events to `docs-repository` |

The reusable workflow maps `DEPLOY_WEBHOOK_URL` and `DOCS_DISPATCH_TOKEN` to these, deploys the
branch the pull request merged into unless you set `ref`, and adds `runs-on` (empty uses the
repository variable `CI_RUNNER`, then `ubuntu-latest`) and `timeout-minutes` (12, above the retry
window).
