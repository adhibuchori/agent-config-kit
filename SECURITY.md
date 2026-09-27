# Security policy

## Supported versions

| Component | Supported |
| --- | --- |
| Each plugin, latest 1.x release (`<plugin>--v1.*`) | yes |
| Reusable workflows and actions, latest `v1.x.y` (and the moving `v1` tag) | yes |
| Anything older than the latest release of the same major version | no: update first |

Fixes ship as a new patch or minor version of the affected plugin, and a new `v1.x.y` release for
the workflows.

## Reporting a vulnerability

Report privately through GitHub:
**<https://github.com/adhibuchori/agent-config-kit/security/advisories/new>**.

Please do not open a public issue, pull request or discussion for a vulnerability. If you cannot
use private reporting, contact the maintainer through their GitHub profile
(<https://github.com/adhibuchori>) and ask for a private channel, without details.

**By email:** no public security address is published yet. Until one is listed here, use private
reporting or the profile route above. The plugin READMEs point here as the security contact.

Include what you can: the plugin and version, your OS, shell and the versions of bash, python3 and
jq, the exact hook input (the JSON a hook receives) or command, what happened, and what you
expected.

## What happens next

- **Acknowledgement within 7 days** of your report.
- An assessment and a fix plan as soon as the problem is confirmed; you are kept informed.
- **Disclosure within 90 days** of the report, or earlier once a fixed release is out, with credit
  to you unless you prefer otherwise.

## Scope

In scope:

- **Hook bypasses count.** A command, file write, MCP call or SQL statement that a guard documents
  as refused but lets through; a way for the agent to open an unlock, forge an unlock file, or read
  a real `.env*` value through the shell; a guard that fails open.
- The setup engine writing outside the project, following a symlink out of it, overwriting a file,
  or writing something the draft did not show.
- Script injection, token exposure or excessive permissions in the reusable workflows, the
  composite actions or the CI templates.
- A hook, `bin/` or `libexec/` file that opens a network connection or downloads code.

Out of scope:

- The limits documented in [docs/unlock.md](docs/unlock.md) ("What the lock does not stop"), such
  as a script Claude writes and then runs, or an application printing its own environment.
- Behaviour after you widen a rule yourself (for example an empty `protectedBranches`).
- Vulnerabilities in Claude Code itself or in third-party tools: report those to their owners.
