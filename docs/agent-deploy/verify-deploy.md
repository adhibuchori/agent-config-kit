# verify-deploy

Command · agent-deploy · `/agent-deploy:verify-deploy <live URL> [--pr N | --since TIME]` · only you start it · uses the network (the live site; GitHub with `--pr` or `--since`)

## What it does

`/agent-deploy:verify-deploy` smoke-tests a live deploy from outside, the way a visitor and a search
engine see it: HTTP 200, the canonical URL, robots and the sitemap, five security headers, and (with
`--pr` or `--since`) a GitHub deployment newer than the merge. It prints every host it will contact
before the first request.

## When to reach for it

After a deploy, on any host:

```text
/agent-deploy:verify-deploy https://www.example.com --pr 42
```

Only you can start it (`disable-model-invocation: true`), and the script's own permission prompt is
a second confirmation.

**Not for:** a site behind sign-in or an access proxy, whose page checks would read the sign-in
page; confirm the deployment in your platform's own list instead.

## Prerequisites

- `scripts/deploy/verify-deploy.sh`, which [/agent-deploy:setup](setup.md) installs, with `curl`
  and python3.
- Network access to the live site.
- For `--pr` or `--since`: a github.com `origin` remote (or `--repo OWNER/REPO`), and for a private
  repository a GitHub token (`GH_TOKEN`, `GITHUB_TOKEN`, or the GitHub CLI `gh` signed in).

## Common questions

**Where does my GitHub token go?**
Only to the GitHub API, over https, from a private temporary file. It is never printed.

**Does it follow a sitemap on another host?**
No. It names it and does not fetch it.

## It's working if

- The script exits 0 and ends with `result: pass (…)`: no check shows `FAIL` (a `WARN` is allowed).
- With `--pr` or `--since`, the `deploy` check shows `PASS`: a finished deployment created after the
  merge.

## Where it fits

The outside check after [/agent-core:promote](../agent-core/promote.md) or [/agent-deploy:promote-deploy](promote-deploy.md).
