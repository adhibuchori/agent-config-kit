# post-commit

Hook · agent-core · PostToolUse on `Bash` · feedback only, never blocks · timeout 20 s · no network · fails open

## What it does

post-commit shows Claude what a commit actually carried, right after it lands, and says so when the
commit holds paths its pathspec did not name.

Sessions that share one checkout share one git index, so another session's staged work can ride
along. Reading the committed file list is the one check that binds.

## When to reach for it

It runs by itself after every `Bash` call and speaks only when a `git commit` in that call created a
commit. You never call it. Claude uses its report to tell you what landed.

**Not for:** stopping a commit that would carry the wrong files, since it never blocks; stage by
name with [/agent-core:commit](commit.md) instead.

## What it blocks

Nothing: it only adds context. It always exits 0, so it can never stop a tool call or erase a prompt.

### How to disable

This hook never blocks, so there is nothing to turn off for a single command. To silence it with
the rest of agent-core:

- **This repo, for you only:** disable the plugins at local scope. A stack plugin depends on
  agent-core, so disable it first:

  ```bash
  claude plugin disable agent-fe-nextjs@agent-config-kit --scope local   # your stack plugin
  claude plugin disable agent-core@agent-config-kit --scope local
  ```

- **Everywhere:** the same two commands without `--scope local`.
- **This repo, for everyone:** the same commands with `--scope project` in place of `--scope local`,
  then commit `.claude/settings.json`. Deleting `.claude/agent-config-kit.lock` and
  `.claude/agent-config.json` is no off switch: a machine that saw the repo opted in keeps guarding
  it (the plugin remembers the opt-in) and says so.

### Check it yourself

Run this from a clone of agent-config-kit. `CLAUDE_PLUGIN_ROOT` is unset there, so the opt-in gate
does not apply (a hook runs as if the project had opted in).

```bash
d=$(mktemp -d) && git -C "$d" init -q \
  && git -C "$d" -c user.name=demo -c user.email=demo@example.invalid commit -q --allow-empty -m init \
  && echo a >"$d/a.txt" && git -C "$d" add a.txt \
  && p='{"session_id":"demo","tool_use_id":"t1","tool_name":"Bash","tool_input":{"command":"git commit -m add-a -- a.txt"}}' \
  && printf '%s' "$p" | CLAUDE_PROJECT_DIR="$d" AGENT_HOOK_STATE_DIR="$d/.state" bash plugins/agent-core/scripts/safety-check.sh \
  && (cd "$d" && git -c user.name=demo -c user.email=demo@example.invalid commit -q -m add-a -- a.txt) \
  && printf '%s' "$p" | CLAUDE_PROJECT_DIR="$d" AGENT_HOOK_STATE_DIR="$d/.state" bash plugins/agent-core/scripts/post-commit.sh
echo "exit=$?"
# expect: exit=0, and one JSON line on stdout whose additionalContext reads
# "Committed in <temp dir>:\n<sha> add-a\n\n a.txt | 1 +\n 1 file changed, 1 insertion(+).
```

## Common questions

**Why does safety-check run first in the example?**
safety-check records the HEAD each commit started from; post-commit reports only commits past that point. That is how a failed or piped commit stays silent.

**Does it need python3?**
Yes. Without it, it says nothing and exits 0.

## It's working if

- After Claude commits, its reply names the commit's hash and files, matching
  `git show --stat HEAD`.
- When a commit carried a file nobody named, that reply says so.

## Where it fits

Feedback half of the commit flow in [agent-core](../../plugins/agent-core/README.md):
[/agent-core:commit](commit.md) drafts the message and stages by name; this hook confirms what landed.
