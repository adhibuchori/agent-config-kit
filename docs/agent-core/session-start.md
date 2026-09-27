# session-start

Hook · agent-core · SessionStart · feedback only, never blocks · timeout 10 s · no network · fails open

## What it does

session-start makes the zsh that runs Claude's shell commands behave like bash on three common traps:
an unmatched glob aborts the command, `=word` expands to a path, and `$var` does not word-split.

It writes one line to `$CLAUDE_ENV_FILE`, which Claude Code sources before every Bash command. Under
bash that line does nothing.

## When to reach for it

It runs by itself when a session starts. You never call it.

**Not for:** the zsh in your own terminal, which it never touches; put the same `setopt` line in
your own shell profile instead if you want it there.

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
f=$(mktemp) && printf '%s' '{"session_id":"demo","source":"startup"}' \
  | CLAUDE_PROJECT_DIR="$PWD" CLAUDE_ENV_FILE="$f" bash plugins/agent-core/scripts/session-start.sh
echo "exit=$?"; cat "$f"
# expect: exit=0, and the file holds:
# [ -n "${ZSH_VERSION:-}" ] && setopt NO_NOMATCH NO_EQUALS SH_WORD_SPLIT 2>/dev/null
```

## Common questions

**Does it change my own terminal?**
No. It reaches only the shell Claude Code starts for its Bash tool.

## It's working if

- A command such as `ls *.nothing` in Claude's shell fails the way it would in bash, instead of
  aborting with `zsh: no matches found`.

## Where it fits

Feedback hook of [agent-core](../../plugins/agent-core/README.md). agent-core also wires
`setup-check.sh` on SessionStart; it is not a component and has no page (see the plugin README).
