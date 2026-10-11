# `encoding/json` accepts unknown keys and matches names without case

**Applies to:** every request body the service decodes, including in code oapi-codegen generates.
**Status:** a standing trap of the standard library (Go 1.27 keeps the old behaviour on the v2
engine).

## Symptom

A client sends `{"title": "a", "Title": "b"}` or a field the API removed last release, and the
request succeeds: the extra key is dropped without a word, and a key in another case lands in the
field. A typo in an optional field (`"discription"`) quietly does nothing.

## Root cause

`go doc encoding/json.Unmarshal`: it matches keys "preferring an exact match but also accepting a
case-insensitive match", and ignores keys the struct does not have. The strict server oapi-codegen
generates decodes with a plain `json.NewDecoder(r.Body).Decode(&body)`, so it inherits both.

## Fix

The spec refuses them, before the generated code decodes anything: every request body object sets
`additionalProperties: false`, and the request validator (`internal/httpapi/validate.go`, on
kin-openapi) answers `VALIDATION_FAILED` with the offending field's pointer. `spec_test.go` fails
on a body schema without `additionalProperties: false`. A body decoded by hand elsewhere uses a
decoder with `DisallowUnknownFields()` and rejects trailing data.

## When to revisit

If oapi-codegen's strict server starts decoding strictly, or `encoding/json` changes its default.
