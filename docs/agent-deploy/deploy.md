# deploy

Workflow · agent-deploy · `.github/workflows/deploy.yml` · optional: setup question `deploy-on-merge` (recommended no) · runs when a pull request into `prod` is merged · needs the secret `DEPLOY_WEBHOOK_URL`

## What it does

`.github/workflows/deploy.yml` starts a deploy when a pull request is merged into `prod`: it calls agent-config-kit's `deploy-webhook.yml` reusable workflow, which POSTs to your deploy platform's webhook for `refs/heads/prod`. A pull request closed without merging runs nothing.

It uses the same rules as `scripts/deploy/trigger-deploy.sh`: an https URL only, a 3xx or 4xx answer is a refusal and fails the job, no answer or a 5xx is retried after 30, 90 and 180 seconds. The URL never appears in the log. Deploys queue one at a time and are never cancelled.

## When to reach for it

When your platform builds from git and deploys on a webhook:

```text
/agent-deploy:setup --answer deploy-on-merge=yes
```

Add the repository secret `DEPLOY_WEBHOOK_URL`. To tell a docs site built with agent-docs-nextra that the app shipped, uncomment `docs-repository` in the file and add a `DOCS_DISPATCH_TOKEN` secret that may send events to that repository; its `changelog.yaml` answers the `app-deployed` event.

**Not for:** a platform that deploys on every push by itself; a second trigger would deploy twice.

## Prerequisites

- A deploy webhook URL, saved as the secret `DEPLOY_WEBHOOK_URL`. Without it the job fails and says so: a deploy is never skipped in silence.
- A caller pinned to a released commit (setup holds a placeholder-pinned one back).

## Common questions

**Accepted is not deployed, right?**
Right. A green run means the platform accepted the request. Confirm the deployment with
[/agent-deploy:verify-deploy](verify-deploy.md).

**My production branch is not `prod`.**
Change `branches:` in the file; the reusable workflow deploys the branch the pull request merged into.

## It's working if

- Merging a pull request into `prod` runs **Deploy**, whose log ends with `The deploy platform accepted the deploy of refs/heads/prod`.

## Where it fits

The CI half of the release path; [/agent-deploy:promote-deploy](promote-deploy.md) is the fallback
when CI cannot run. See [CI/CD at a glance](../../README.md#cicd-at-a-glance).
