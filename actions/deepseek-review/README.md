# deepseek-review action

An AI review of each pull request by [DeepSeek](https://api-docs.deepseek.com/), a model whose API
is cheap enough to run on every pull request. It posts one comment and updates that comment on every
later run, so a pull request never fills up with reviews.

A stack plugin's `/<plugin>:setup` installs a caller when you answer `deepseek-review=yes`. The
caller runs the reusable workflow
[`.github/workflows/deepseek-review.yml`](../../.github/workflows/deepseek-review.yml), which runs
this action. This page is the reference for what it sends, what it costs and what it posts.

## What it does

1. Reads the pull request and its changed files over the GitHub REST API. It never checks the code
   out, so nothing from the pull request runs on the runner.
2. Skips, and passes, when the API key is empty, the pull request comes from a fork, is a draft (on
   the `pull_request` event; `/ask-deepseek` still reviews a draft), is closed, or has nothing left
   to review.
3. Leaves out lockfiles, minified files, source maps and snapshots, plus your `exclude` patterns.
4. Adds whole files to the diff until the next one would pass `max-diff-bytes`, and lists the rest
   in the comment.
5. Sends the diff, the title and the first 4,000 bytes of the description to DeepSeek's chat API,
   with a system prompt that treats all three as data, never as instructions, and your
   `instructions` as project notes.
6. Posts the answer as one comment marked `<!-- agent-config-kit:deepseek-review -->`, or updates the
   comment a bot wrote before. A `@mention` in the answer becomes code, so nobody is notified by it.

## What it costs

DeepSeek bills tokens in and out, with lower prices off-peak. The caps bound every review:
`max-diff-bytes` (100,000 bytes, roughly 25,000 to 30,000 tokens) and `max-tokens` (16,384 tokens
of answer, reasoning included). With `deepseek-v4-pro` a review at both caps costs about a dime at
peak prices; a typical pull request costs a cent or two, and `deepseek-flash` about a quarter of
that. Every comment ends with the tokens that review used, and the job summary repeats them. Check
DeepSeek's pricing page for today's prices.

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `api-key` | empty | The DeepSeek API key; empty skips the review with a notice |
| `github-token` | the job's token | Reads the pull request, writes its comment |
| `pull-request` | the event's | The pull request number (from `pull_request`, or the issue a comment is on) |
| `model` | `deepseek-v4-pro` | The model; `deepseek-flash` is cheaper |
| `base-url` | `https://api.deepseek.com` | The API's base URL, https only; the key goes to this host only |
| `instructions` | empty | Project notes for the reviewer, written by you |
| `exclude` | empty | More patterns to leave out: with a slash they match the path, without one the file name; `*` matches anything |
| `max-diff-bytes` | `100000` | The most diff to send |
| `max-tokens` | `16384` | The most the model may write, reasoning included |
| `reasoning-effort` | `low` | `none`, `low`, `high` or `max`; empty leaves the API's default |
| `request-timeout` | `300` | Seconds to wait for the answer |

## Exit status

| Result | Job |
| --- | --- |
| Reviewed, or skipped with a notice | passes |
| DeepSeek busy: no answer, 429 or 5xx (retried twice, within the timeout) | passes with a warning |
| DeepSeek refused the request (400-level: the key, the balance, the model) | fails |
| The GitHub API refused a read or the comment | fails |

## Why it is safe behind a comment

The reusable workflow also runs on `issue_comment`, for `/ask-deepseek`. That event runs with the
repository's secrets and a write token, even for a pull request from a fork, so the caller keeps one
narrow shape, and `scripts/workflow-policy.py` fails any other (ADR 0004):

- the job runs only for a comment on a pull request by the repository's owner, a member or a
  collaborator;
- it holds `contents: read` and `pull-requests: write`, nothing more;
- nothing is checked out: the diff is read over the API as data;
- GitHub runs the comment trigger from the default branch's copy of the workflow, so a pull request
  cannot change it;
- a fork's pull request is skipped on every event.

What the model reads can still steer what it writes; it has no tools and never sees a secret, and
the comment says it is advisory.
