# help

Command · agent-core · `/agent-core:help [what you want to do]` · reads only · no network

## What it does

`/agent-core:help` tells you which kit command to run next. With no question it prints the everyday
flow (plan → review → commit → create-pr → merge-pr) and every command of every installed kit
plugin. It also explains how you unlock `.env` files and database writes.

## When to reach for it

When you are not sure which command fits, or right after you install the kit:

```text
/agent-core:help
/agent-core:help I want to ship this branch to production
```

**Not for:** learning what a hook blocks; read that hook's page, such as
[safety-check](safety-check.md), instead.

## Common questions

**It lists a command as "not installed".**
That command belongs to a plugin that is not enabled in this session. The line names the plugin; install it with `/plugin install <plugin>@agent-config-kit`.

**Is the list up to date?**
CI fails when a plugin gains a command that help.md does not name (`node scripts/catalog.mjs --check`).

## It's working if

- It answers with one command and why, or prints the flow and the full table.

## Where it fits

The router of [agent-core](../../plugins/agent-core/README.md). It names every kit command. Hooks,
agents and skills have their own pages on this site too, but they are not commands, so help does
not list them.
