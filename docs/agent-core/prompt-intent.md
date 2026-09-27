# prompt-intent

Hook · agent-core · UserPromptSubmit · feedback only, never blocks · timeout 10 s · no network · fails open

## What it does

prompt-intent points a `/debug` shorthand at the kit's reproduction-first debugging command
(`/agent-core:rca`, or your project's own `/rca`), and prunes the hooks' state of sessions idle for
two days.

It never reads permission from your prompt: a refused command stays refused whoever asks.

## When to reach for it

It runs by itself each time you send a prompt. Type `/debug` followed by the symptom and Claude
is pointed at `/agent-core:rca` instead of the built-in `debug` skill, which debugs Claude Code
itself.

**Not for:** granting permission, since it never reads permission from your prompt; run a refused
command yourself with `!` instead.

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
d=$(mktemp -d) && mkdir -p "$d/.claude" && echo '{}' >"$d/.claude/agent-config.json" \
  && printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"demo","prompt":"/debug the login page returns 500"}' \
  | CLAUDE_PROJECT_DIR="$d" CLAUDE_PLUGIN_ROOT="$PWD/plugins/agent-core" CLAUDE_PLUGIN_DATA="$d/.data" \
    bash plugins/agent-core/scripts/prompt-intent.sh; echo "exit=$?"
# expect: exit=0, and on stdout a JSON line whose additionalContext begins
# "The user's /debug means the /agent-core:rca command, a reproduction-first debugging protocol".
```

## Common questions

**Why does this example set CLAUDE_PLUGIN_ROOT?**
`/agent-core:rca` is found in the plugin folder. With the plugin root set, the project gate applies, so the example opts a temp project in with an empty `.claude/agent-config.json`.

**Can an exit code here erase my prompt?**
No. It is wired with `|| true`; an exit 2 on this event would erase the prompt, so it can never return one.

## It's working if

- `/debug checkout fails` starts a reproduction-first debugging pass (`/agent-core:rca`).

## Where it fits

Feedback hook of [agent-core](../../plugins/agent-core/README.md), next to
[/agent-core:rca](rca.md).
