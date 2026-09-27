# Deleting a `session` row does not end the session

**Applies to:** better-auth with `secondaryStorage` (Redis) configured — any write that ends a
session, and any write that changes a column the session snapshot carries.
**Verified against:** better-auth 1.7.1 (`dist/db/internal-adapter.mjs`: `findSession` reads
secondary storage first; `deleteUserSessions` clears both stores).

## Symptom

An account is banned. The `user` row says `banned = true`,
`SELECT * FROM "session" WHERE user_id = …` returns **zero rows**, and the account's own session
list shows **no devices**.

It stays signed in anyway, indefinitely.

## Root cause

With `secondaryStorage` configured, **Redis holds the session every read actually consults.**
Postgres holds a mirror, kept only because `session.storeSessionInDatabase: true` asks for one.

So a hand-written `db.delete(session)` empties the copy **nothing on the request path reads**:

| store | after a raw row delete |
| --- | --- |
| Postgres `session` | empty — this is the mirror |
| Redis, keyed by the session token | **still there** — this is what `getSession` reads |
| Redis, the per-user index of active sessions | **still there** |

The second failure rides along with the first. A guard on `session.user.banned === true` reads
`session.user`, the snapshot stored **at sign-in** and never rewritten. It says `banned: false` no
matter what the column now holds, so the guard cannot fire either.

## The second window, behind the first

`session.cookieCache` answers `getSession` from a signed cookie without consulting any store. A
banned account keeps access until that cache ages out, and the `banned` guard cannot close it
either: the user object it reads comes from the frozen payload. A shorter `maxAge` shrinks the
window rather than closing it, and nothing an administrator does can reach a cookie. If you enable
it, pair it with a mechanism that can invalidate a live one.

## Fix

Revoke through better-auth, so both stores and the index move together:

```ts
const { internalAdapter } = await auth.$context;
await internalAdapter.deleteUserSessions(userId);
```

That is what `auth.api.revokeUserSessions` calls, minus the admin middleware that a service-token
path cannot satisfy. Where a real session is in hand, prefer the public `auth.api.*` endpoints.

## A role change is a session change

Any column the session snapshot carries is stale from the moment it is written: `banned`, `role`,
a status column a role guard reads, `twoFactorEnabled`. A role guard that reads
`session.user.role` passes on the old value until the session ends, and `updateAge` slides the
idle timeout forward on every request, so an account in use loses nothing until the absolute
session lifetime. Changing one of those columns is half the operation; ending the account's
sessions is the other half. It applies in the granting direction too, where the account is refused
the role it was just given.

## The test trap, which is the worse half

A test that asserts the session row was deleted passes against an implementation that leaves every
banned account signed in. Asserting the mirror was written proves nothing about the store that
decides access.

Assert the adapter call instead, and pin the negative separately: **no session row is ever deleted
directly.** The two failures are indistinguishable from the outside — an account that stays signed
in — and only the second names the cause.

## Scope

Any write that ends or invalidates a session — ban, forced sign-out, account removal, a "sign out
all devices" action — and any write that changes a column the session snapshot carries. Reads are
unaffected.
