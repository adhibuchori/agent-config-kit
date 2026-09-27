# A Better Auth plugin's list option replaces its defaults, it does not extend them

**Applies to:** Any Better Auth plugin option that takes a list (paths, origins, endpoints), for
example the breached-password plugin's `paths`
**Status:** Permanent (the library works as written)

## Symptom

None, and that is the problem. Adding one route to the breached-password list turns the check off
for every route already covered by default: sign-up, change password and reset now accept a
password from a known breach corpus. Nothing throws, no log line appears, the suite stays green.

## Root cause

The plugin reads `options.paths || [defaults]`: an `||`, not a merge. Worse, an endpoint declared
server-only has no path at all, so the plugin's `if (!c.path || !paths.includes(c.path))` skips it
whatever the list says: listing it reads as protection and provides none.

## Fix

- Restate every default verbatim when you pass the option, so the replacement is a deliberate no-op
  plus your addition.
- For a flow served by a server-only endpoint (setting a first password is the usual one), run the
  same check yourself in the backend route before calling it, failing closed the same way.

## How to catch it

No gate sees this: the list is data and every value in it is valid. Verify by behaviour at every
entry point: a known-breached password must be refused at sign-up, change password, reset and set
password. Before trusting a list entry, check the endpoint has a path at all.

## Scope

Read a plugin's source before passing any list-shaped option, and assume replacement unless the
code shows a merge.
