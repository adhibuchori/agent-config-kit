# A custom BullMQ job id with a `:` in it is never queued

**Applies to:** every `queue.add(name, data, { jobId })` call that sets a custom id.
**Verified against:** BullMQ 6.3.8 (`dist/cjs/classes/job.js`, `validateOptions`).

## The trap

BullMQ refuses a custom job id containing a colon — that character is the separator in its own
Redis key names — and it throws from `add`, before anything reaches Redis:

```
Error: Custom Id cannot contain :
    at Job.validateOptions (bullmq/dist/cjs/classes/job.js)
```

`<entity>:${id}` reads like every other namespaced Redis key in a codebase, which is exactly why it
gets written. Use a hyphen: `<entity>-${id}`.

Two details from the same check. An id that splits into exactly three parts on `:` is accepted, for
compatibility with old repeatable jobs, so `a:b:c` passes while `a:b` throws; do not rely on it. And
an id that is an integer string (`"123"`) is refused too (`Custom Id cannot be integers`).

## Why it ships green

Three things hide it, and each is worth checking on its own:

1. **Producers that must never fail the request wrap the enqueue in try/catch.** The throw becomes
   a log line nobody reads, and the endpoint still answers 2xx.
2. **A queue double that accepts any id.** If the test double records whatever it is handed, the
   producer's tests pass against a producer that cannot enqueue. Make the double refuse what BullMQ
   refuses; `.claude/test-preload.example.ts` does.
3. **A missing job looks like a disabled worker.** If a worker switch is parsed as
   `value !== 'false'`, an **empty** value means the worker is **on**, so an empty `.env` line is
   not a diagnosis. Check the queue itself before blaming config.

## How to see it

The queue tells the truth in a few seconds. With the development `REDIS_URL` exported in your shell
(never read out of a `.env` file by the agent):

```bash
redis-cli -u "$REDIS_URL" --scan --pattern 'bull:<queue>:*'
redis-cli -u "$REDIS_URL" zrange 'bull:<queue>:failed' 0 -1
```

No job key for the id you expect, and nothing in `failed`, means the job was never added — the
producer threw and swallowed it. A job key that exists and sits in `failed` is the opposite
problem, and its `failedReason` field says what happened.
