---
description: Smoke-test a live deploy from outside (HTTP 200, canonical URL, robots and sitemap, security headers, a GitHub deployment newer than the merge). Uses the network, and only when you start it
argument-hint: "<live URL> [--pr N | --since TIME] [--expect-noindex] [--environment NAME] [--skip CHECK,...]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git remote get-url:*), Bash(git status:*)
---

# /agent-deploy:verify-deploy — Check That A Deploy Reached Production

Runs `scripts/deploy/verify-deploy.sh` against the live site, from outside, the way a visitor and a
search engine see it. It uses the network, so it runs only because the user started it: Claude
never starts it on its own, and the permission prompt for the script is a second confirmation.

**Arguments:** $ARGUMENTS

## What it contacts

- The URL given: one GET, following at most 5 redirects, then `/robots.txt` and the sitemap on the
  host the page lands on. A sitemap that robots.txt places on another host is named, not fetched.
- With `--pr N` or `--since TIME`: the GitHub API (`https://api.github.com`, or `GITHUB_API_URL`),
  read-only, for the pull request's merge time and the repository's deployments. The token
  (`GH_TOKEN`, else `GITHUB_TOKEN`, else the GitHub CLI's) goes to that API only, over https, from a
  private temporary file, and is never printed.
- Nothing else. The script prints this list before its first request.

## Step 1: Find the script

`scripts/deploy/verify-deploy.sh` is installed by `/agent-deploy:setup`. If the file is missing,
stop and suggest `/agent-deploy:setup`.

## Step 2: Settle the arguments (read-only)

- **URL.** From the arguments; else the live URL in `.claude/OPERATIONS.md` § Deploys; else ask. A
  placeholder such as `https://<app-host>` is not a URL: ask.
- **The merge the deploy must follow.** `--pr N` for a merged pull request, or `--since TIME` (UTC,
  such as `2026-01-31T12:00:00Z`) for a push without one, as after `/agent-deploy:promote-deploy`.
  Without either, the deploy check is skipped and the report says so; offer one when the user wants
  proof that this deploy is new, not only that the site is up.
- **Repository.** The script reads the github.com `origin` remote (`git remote get-url origin`);
  pass `--repo OWNER/REPO` when origin is elsewhere.
- **Staging or preview.** Pass `--expect-noindex`: the target must then not be indexable, the sitemap
  is not checked, and canonical problems are warnings.
- **Environment.** When deployments go to several GitHub environments, `--environment <name>` counts
  only that one.
- **A host that does not report deployments to GitHub.** Pass `--skip deploy`, and confirm the
  deployment in the platform's own list instead: the adapter's `latest` in `.claude/OPERATIONS.md`
  § Deploys.

## Step 3: Run it

Say in one line which hosts it will contact, then run:

```bash
bash scripts/deploy/verify-deploy.sh --url <URL> [--pr N | --since TIME] [other options]
```

The permission prompt for this command is expected: the user approves it to let the requests go
out. With agent-core's Bash sandbox on, Claude Code may also ask before the first request to each
host.

Show the output verbatim. Exit 0: every check passed (warnings allowed). Exit 1: at least one check
failed. Exit 2: a usage error or a missing tool (python3, curl), before any request.

## Step 4: Read the result

| Check | A FAIL means | Where the fix usually lives |
| --- | --- | --- |
| `http` | no 200 after the redirects, a body that did not arrive, or https dropping to http | the host's routing, redirects or TLS |
| `canonical` | missing, relative, more than one, or on another host | the page's metadata (`alternates.canonical` in Next.js) |
| `indexing` | production says noindex, or a staging deploy is indexable | a robots meta tag, `X-Robots-Tag`, or robots.txt per environment |
| `robots` | missing, served as HTML, or `Disallow: /` for every crawler | the robots file or route, per environment |
| `sitemap` | not 200, or not a sitemap | the sitemap file or route, and the `Sitemap:` line in robots.txt |
| `hsts`, `csp`, `nosniff`, `framing`, `referrer` | a security header is missing or weak | the host's header configuration, or `headers()` in `next.config.*` (a static export ignores it, so the host's configuration is the only place) |
| `deploy` | no finished deployment created after the merge, or one of a commit that does not contain it | the deploy pipeline; `/agent-deploy:promote-deploy` Phase 3 |

- A WARN is information: say what it means, and do not call it a failure.
- A FAIL is a finding to fix at its source. Never re-run with `--skip` to turn the report green;
  `--skip` is for a check that does not apply here, and the report says why it was skipped.
- A host behind an access proxy or single sign-on answers an anonymous request with its sign-in page,
  often with a 200. The page checks then describe the sign-in page: say so, and rely on the
  deployment record.
- Accepted is not deployed, and a green CI run is not a deployment. Only the `deploy` check (or the
  platform's own deployment list) shows that production changed.

## Report

Per check: its status and one line of evidence from the output. Name what was skipped and why, the
hosts contacted, and whether the deploy check proved a deployment newer than the merge.
