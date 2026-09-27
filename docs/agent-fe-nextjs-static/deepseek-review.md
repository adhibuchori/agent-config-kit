# deepseek-review

Workflow · agent-fe-nextjs-static · `.github/workflows/deepseek-review.yml` · optional: setup question `deepseek-review` (recommended no) · runs when a pull request into `dev`, `main` or `master` opens, reopens or is marked ready, and on a `/ask-deepseek` comment · uses the DeepSeek API (paid per token)

## What it does

`.github/workflows/deepseek-review.yml` asks DeepSeek for a review of a pull request's diff and posts it as one comment, which later runs update in place. It calls agent-config-kit's `deepseek-review.yml` reusable workflow with notes about this static Next.js site and the default list of files to leave out (lockfiles, minified files and source maps).

It reads the pull request over the GitHub API and never checks the code out, so nothing from the pull request runs. The diff it sends is capped (100 KB by default) and the answer too (16,384 tokens), so one review costs about ten US cents at most at peak prices, and usually a cent or two.

## When to reach for it

When you want a second reader on every pull request for little money:

```text
/agent-fe-nextjs-static:setup --answer deepseek-review=yes
```

Then add the repository secret `DEEPSEEK_API_KEY` (Settings, Secrets and variables, Actions). Comment `/ask-deepseek` on a pull request to review it again after new commits; only the repository's owner, members and collaborators can.

**Not for:** replacing a human review or the quality gate. The model reads the diff only, not the rest of the code.

## Prerequisites

- A DeepSeek API key with a balance, saved as the secret `DEEPSEEK_API_KEY`. Without it the job passes with a notice and sends nothing.
- A caller pinned to a released commit (setup holds a placeholder-pinned one back).

## Common questions

**What does it cost?**
DeepSeek bills tokens in and out. With the defaults, `deepseek-v4-pro`, a 100 KB diff cap and a 16,384-token answer, a review at both caps costs about ten US cents at peak prices (half that off-peak), and a typical pull request a cent or two. Set `model: deepseek-flash` under `with:` for a cheaper model, or lower `max-diff-bytes`. Every comment ends with the tokens that review used.

**Does a fork's pull request get reviewed?**
No. GitHub gives a fork's run no secrets, and the action also skips a fork when someone comments `/ask-deepseek`.

**Why not on every push?**
Each review costs money. It runs when the pull request opens and when you ask; the comment is updated, not repeated.

## It's working if

- A pull request into `dev` gets one comment headed **DeepSeek review**, ending with the model, the commit and the tokens used.
- Without the secret, the run passes and its log says `DEEPSEEK_API_KEY is not set`.

## Where it fits

An optional reviewer next to the [quality gate](quality-gate.md). The
[CI/CD at a glance](../../README.md#cicd-at-a-glance) table shows when each workflow runs and what it costs.
