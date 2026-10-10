# serde accepts fields the type does not have

**Applies to:** every request type deserialized with serde
**Status:** A standing trap

## Symptom

A client sends `{"name": 1, "extra": "x"}` and gets 200. A misspelled field (`"emial"`) is dropped
without a word, so the client believes it set a value the service never stored. A field the
service drops today and reads tomorrow changes behaviour for clients that sent it all along.

## Root Cause

serde ignores unknown fields by default; only `#[serde(deny_unknown_fields)]` refuses them
(reproduced in the research sample: `{"name":1,"extra":"x"}` answered 200).

## Fix

Put `#[serde(deny_unknown_fields)]` on every request type, and read the body through `ValidJson`,
which turns the refusal into a 422 that names the field. Response types do not need it.

## When to revisit

Never: the default is deliberate in serde. A versioned API that must accept newer clients' fields
says so in its own rule, per type.
