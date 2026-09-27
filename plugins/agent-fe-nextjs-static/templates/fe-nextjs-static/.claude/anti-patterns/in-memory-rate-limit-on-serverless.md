# A rate limit kept in memory does not limit a serverless endpoint

**Applies to:** A contact or newsletter endpoint that runs as a serverless function, or on more than
one instance
**Status:** Permanent (how serverless and multi-instance hosting work)

## Symptom

The form endpoint has a rate limit, with a test that proves the sixth request in a minute is
refused. In production a bot sends hundreds of messages an hour, and the logs show the limit never
triggered.

## Root cause

The counter lives in the function's memory (a `Map` of client address to count). A serverless
platform starts a fresh instance whenever it wants, runs several at once under load, and throws
instances away when idle. Each one starts with an empty map, so each client gets a fresh allowance
from every instance it happens to reach. The unit test passes because it runs one instance.

## Fix

Keep the count where every instance sees it:

- the host's own rate limiting or firewall rules in front of the endpoint, or
- a shared store with an atomic increment and an expiry (a key-value store, a database row).

Keep the honeypot and the minimum-time check as well
(`.claude/rules/web/forms-on-static-hosting.md`): they stop most bots before any counter is
needed.

## How to catch it

Look for a module-level `Map`, object or array in a route handler or function that is read and
written per request. Anything that must hold across requests does not belong there.

## Scope

Any per-client state in a serverless or multi-instance endpoint: rate limits, once-per-visitor
checks, cached challenges.
