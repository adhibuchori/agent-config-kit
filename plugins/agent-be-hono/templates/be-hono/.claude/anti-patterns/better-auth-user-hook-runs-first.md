# better-auth runs your `hooks.after` first, then lets a plugin overwrite it

**Applies to:** anything registered in `betterAuth({ hooks: { after } })` that must decide the
response — a refusal, a redirect, a rewritten body. Counting, logging and other write-only work is
safe there and belongs there.
**Verified against:** better-auth 1.7.1 (`dist/api/dispatch.mjs`, `getHooks` and the after-hook
loop).

## Symptom

A sign-in guard refuses the right accounts and logs every refusal, and the browser is sent on to
the second-factor screen anyway. The unit tests of the guard are green and its logic is correct.

## Root cause

In `getHooks`, the user slot is pushed before every plugin's after-hook:

```js
const afterHookHandler = authContext.options.hooks?.after;
if (afterHookHandler) afterHooks.push({ matcher: () => true, handler: afterHookHandler });
/* … */
if (pluginAfterHooks.length) afterHooks.push(...pluginAfterHooks);
```

**The user slot runs FIRST.** And each hook's result is written to `context.returned`:

```js
const result = await hook.handler(context).catch((e) => {
  if (isAPIError(e)) return { response: e, headers: mergeAPIErrorHeaders(e) };
  throw e;
});
if (result.response !== void 0) context.context.returned = result.response;
```

A thrown `APIError` is **caught and assigned**, not propagated. So it is an ordinary value that the
next hook overwrites. A two-factor plugin's own after-hook answers "go to the second factor" on a
correct password — it runs second, and the refusal is gone.

| Account | Refusal produced | What the caller got |
| --- | --- | --- |
| no second factor | `APIError` | `403` — correct, nothing ran after it |
| second factor enrolled | `APIError` | the plugin's redirect to the second factor |

## Fix

Register the decision as a **plugin**, declared after every plugin whose response it may need to
override:

```ts
plugins: [
  /* … */
  twoFactor({ issuer: '<app-name>' }),
  signInGuardPlugin(), // LAST — its APIError is the last thing written to `context.returned`
],
```

Pin that position with a test; nothing in the type system expresses it, and an alphabetical
tidy-up of the array breaks the guard in silence.

Keep in `hooks.after` only what must run **before** any plugin can end the request — recording a
sign-in outcome, for example, which must happen even when a later guard turns the sign-in away.

## The signal

**A guard that logs its decision while the caller sees the opposite.** When a refusal appears in
the log and not in the response, stop reading the refusal and start asking who wrote
`context.returned` last.

**And the testing half, which is the more general lesson.** A test that calls the hook function
directly and asserts it throws proves the FUNCTION, and says nothing about whether the library
propagates the throw, which is the part that breaks. Drive a hook through `auth.api.*` with a
real account, or over HTTP.

Related: [session-rows-are-a-mirror-not-the-session.md](session-rows-are-a-mirror-not-the-session.md)
— the other half of why a suspension can appear to do nothing.
