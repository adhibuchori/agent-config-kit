# Periphery reads a stale index on a developer's Mac

**Applies to:** the dead-code check (`periphery scan --index-store-path`)
**Status:** Permanent (incremental builds keep old index records)

## Symptom

`periphery scan --strict --index-store-path .build/xcode/Index.noindex/DataStore` reports a property
on a line the file no longer has, after the property was deleted and the app rebuilt. The gate's
macOS job, on the same commit, passes.

## Root cause

An incremental build re-indexes the files it recompiles; records of a package target's earlier
build stay in the store. Periphery reads every record it finds. The gate builds into a fresh
`DerivedData` each time, so it never sees them.

## Fix

Delete the index and the build products, rebuild, then scan:

```bash
rm -rf .build/xcode/Index.noindex .build/xcode/Build
bash scripts/ios/app.sh test
periphery scan --strict --disable-update-check --index-store-path .build/xcode/Index.noindex/DataStore
```

Never cache `DerivedData` in CI for the same reason: an incremental build also drops the warnings
of the files it does not recompile, so the zero-warning check passes on a stale count.

## How to catch it

A finding whose line number points past the end of the declaration, or at a different one.

## Scope

Every local Periphery run over an index an incremental build wrote.
