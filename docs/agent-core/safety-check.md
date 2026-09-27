# safety-check

Hook · agent-core · PreToolUse on `Bash` · blocks with exit 2 · timeout 10 s · no network · fails closed

## What it does

safety-check reads every shell command Claude is about to run and refuses the ones an agent should
never run on its own: destructive deletes, commands that wipe uncommitted work, pushes to protected
branches, skipping the pre-commit gate, and any shell read or write of a real `.env*` file.

It reads the command the way a shell does (quotes, heredocs, `$( )`, `bash -c`, wrappers such as
`sudo` or `timeout`, package runners such as `npx`) instead of matching substrings. When it cannot
tell what a command touches, it refuses and says so. When a refused command is really meant, you run
it yourself with `!` in front.

## When to reach for it

It runs by itself before every `Bash` tool call, in a repo that has opted in
(`.claude/agent-config-kit.lock` or `.claude/agent-config.json`). You never call it.

When it refuses, Claude sees the reason and a safer way to do the job, and usually takes that way.
If the command was right after all, type it yourself with `!`:

```text
! git push origin main
```

**Not for:** stopping a script Claude writes and then runs, since it reads command text only; use
the Bash sandbox that setup can turn on instead.

## What it blocks

The settings that shape it live in `.claude/agent-config.json`: `protectedBranches`,
`protectedPaths` and `commandWrappers`. Every rule has probes that prove it both ways: 808 rows in
`scripts/check/hook-probes.tsv` (540 must block, 268 must pass), run by
[tests/hooks/safety-probes.bats](../../tests/hooks/safety-probes.bats).

| What | Why it is blocked | Do this instead |
| --- | --- | --- |
| Recursive delete of a protected path, the repo, a parent or your home folder (`rm -rf src`) | It deletes work git may not hold | `git rm -r <path>`; a throwaway named `zz-*` or `*-probe` stays deletable |
| `find` that deletes (`-delete`, `-exec rm`) outside a temp folder | The deleted paths are never shown | `find … -print`, check the list, then delete named paths |
| Commands that wipe uncommitted work: `reset --hard`, `clean -f` without a path, `checkout .`, `restore .`, `stash` without a path, `stash clear` | They wipe other sessions' work in a shared checkout too | Name your own paths: `git stash push -- <paths>`, `git checkout -- <file>` |
| Skipping the pre-commit gate: `--no-verify`, `commit -n`, `HUSKY=0`, `SKIP=` | The gate is what a change must pass | Fix what the gate reports |
| A push to, or deletion of, a protected branch (`dev`, `prod`, `main`, `master`), also by `--all`, `--mirror` or the checked-out branch | Protected branches change through pull requests | Push a work branch and open a PR; a release push is yours, with `!` |
| `gh pr merge --delete-branch` | It can delete a protected head branch | Merge, then delete the work branch by name |
| Any shell read or write of a real `.env*` file (`cat`, `grep`, `source`, redirects, copies, `python -c`, `bun -e 'console.log(process.env)'`) | Secret values would land in the transcript | `bash scripts/env/show.sh <file>` (secrets masked); `scripts/env/set.sh` after you run `! bun unlock env` |
| Claude running the unlock script or its `unlock` package script, or touching `.claude/state/unlock/` | Only you may unlock | Claude asks you to run `! bun unlock env` (or `db`) |
| Changing `scripts/env/` or `scripts/ops/unlock.sh` from the shell | Those files are the lock itself | Change them with the Edit tool, which asks you first |
| Changing, moving, linking or deleting the files that turn the guards on from the shell: `.claude/settings.json`, `settings.local.json`, `agent-config.json`, `agent-config-kit.lock`, and the plugin's record of opted-in projects (`rm`, `mv`, `ln`, `cp` over, redirects, `truncate`, `sed -i`, `chmod`, `git rm`/`checkout`/`restore`) | Claude could switch its own guards off | Read them freely (`cat`, `jq`, `git diff`); change them with the Edit tool, which asks you first |
| Changing the guard scripts from the shell: the hooks (the plugin's own `scripts/` and `hooks/`, the plugins in `~/.claude/plugins/`, any `.claude/hooks/`), `scripts/check/hook-probes.*` and `scripts/ops/unlock.sh`, or a folder that holds them (`rm`, `mv`, `ln`, `cp` over, redirects, `tee`, `truncate`, `sed -i`, `perl -i`, `chmod`, `git rm`/`checkout`/`restore`/`stash`/`mv`) | A guard Claude can rewrite guards nothing | Read, run and copy them out freely; change one with the Edit tool, or run the command yourself with `!` |
| A program that names the file it writes, reads or runs inside its own code: a `sed` `w`, `r` or `e`, an `awk` `print >`, `getline <` or `system()`, inline `python -c` or `node -e` that changes a file or runs a command | The file it reaches is in the program, not on the command line | Use the plain command (`rm`, `mv`, `cp`, a redirect), which the hook can read |
| A command that changes files, handed its paths by `xargs`, `$( )` or `find -exec` (`find . -name '*.sh' \| xargs chmod 000`) | Which files it reaches cannot be checked | List the paths, check them, then name them; `rm $(git ls-files '*.orig')` still works |
| Git settings that change what git runs or loads (`-c alias.*`, `core.sshCommand`, `core.fsmonitor`, a credential helper, `url.*.insteadOf`, a proxy) | They can run any program behind a harmless-looking git command | Plain settings (`user.*`, `color.*`) stay open; run the rest yourself with `!` |
| `alembic downgrade`, where `alembic.ini` exists | It drops columns and the data in them | Write a new forward revision |
| A command it cannot resolve: computed code in `eval`, a decoded payload run by a shell, `curl … \| bash`, a script name built at run time | Fail closed: an unread command is not a safe command | Run it yourself with `!` if it is meant |

### How to disable

- **One rule:** most rules take a setting in `.claude/agent-config.json` (listed above the table
  or in [agent-core's configuration](../../plugins/agent-core/README.md#configuration)). A key you set
  replaces its default whole, so list the defaults you still want.
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
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | CLAUDE_PROJECT_DIR="$PWD" bash plugins/agent-core/scripts/safety-check.sh; echo "exit=$?"
# expect: exit=2, and on stderr:
# [safety] BLOCKED: pushing to a protected branch (dev/prod/main/master) is not allowed. Push your
# work branch and open a PR; when a release needs this push, the user runs it with `!`.
```

## Common questions

**It blocked a command I really want. Can Claude get past it?**
No, and that is the point: no hook reads permission from the chat. Run the command yourself with `!` in front. It runs as you, outside the hooks.

**Does it work without python3?**
Partly. Without python3 only plain-text rules run: protected-branch pushes, recursive deletes of protected paths, a hard reset, forced `clean`, `--no-verify`, `HUSKY=0`, any real `.env*` name, the unlock script, `scripts/env/`, the files that turn the guards on and the guard scripts themselves. Install python3 3.8 or newer for the full analyzer.

**A wrapper I use hides the real command (`dotenvx run -- …`).**
Add it to `commandWrappers` in `.claude/agent-config.json`, for example `"dotenvx run -f= --env-file="`. The wrapper is then peeled off and the inner command is judged.

**Is this a security boundary?**
No. It reads command text, so a script Claude writes and then runs is executed, not read. It is a guardrail against slips and against instructions hidden in files. It does refuse every shell change it can read to the hooks themselves, since a guard Claude could rewrite would guard nothing; a change goes through the Edit tool, where you see the diff, or your own `!`. The Bash sandbox that setup can turn on is the layer the operating system enforces.

## It's working if

- `git status` runs without a word from the hook.
- `git push origin main` from Claude is refused with a `[safety] BLOCKED:` line, and Claude pushes a
  work branch instead.
- `cat .env` is refused and Claude uses `bash scripts/env/show.sh .env`.

## Where it fits

The main guard of [agent-core](../../plugins/agent-core/README.md). It works with the `deny` rules
setup installs in `.claude/settings.json` (such as `Bash(git push origin main:*)`) and with the
[unlock](../unlock.md) mechanism. [mcp-guard](mcp-guard.md) covers the same protected branches for
GitHub MCP writes; [db-guard](db-guard.md) covers production SQL.
