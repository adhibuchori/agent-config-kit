# A payment gateway's cancel result is not the state of the payment

**Applies to:** Code that closes or supersedes a pending payment (or any external resource) by
calling the provider's cancel endpoint and acting on its response
**Status:** Permanent (how remote state machines answer)

## Symptom

A warning says an unpaid request was left live at the gateway, or a second charge is raised for
something the customer has just paid. The cancel call's own result said something else.

## Root cause

The result of a cancel call is not an answer, in either direction:

- **A timeout is not a failure.** The request often lands and cancels while the response is lost.
- **A refusal is not a failure either.** An already-closed request answers "not cancellable in this
  state", the ordinary answer after the timeout above, and treating it as an error reads like a
  live code left behind.
- **The same refusal covers the dangerous case.** A request that has just been **paid** is also not
  cancellable, so the identical refusal can mean the customer paid a moment ago.

## Fix

Never read the error. Read the resource back and map its status through the same function the
webhook and the status poll use:

- expired, failed or cancelled: the job is done; log it as information;
- paid: expire nothing and refuse to raise a new charge; the settlement about to arrive makes that
  true;
- anything else, or a read that fails too: keep the warning, because only a person reconciling it
  against the provider can tell.

## How to catch it

In the provider's sandbox, cancel with a short client timeout, retry, and read the request back:
the second call is refused while the read shows it cancelled all along.

## Scope

Every "cancel then act" against a remote state machine: payments, subscriptions, shipments.
