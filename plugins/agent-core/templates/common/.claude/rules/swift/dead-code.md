---
paths:
  - '**/*.swift'
---

# Dead code (Swift)

Blocking in the Quality Gate, where Periphery scans the build with `--strict`.

- Periphery reports declarations nothing uses: types, functions, properties, protocol members and
  parameters, properties that are only ever assigned, and `public` that nothing outside the module
  needs. The compiler only warns about unused locals.
- A finding is fixed, not silenced. Unused anywhere: delete it. `public` only for nothing: drop it.
  Reached in a way Periphery cannot follow (the Objective-C runtime, a name in a storyboard or a
  property list): keep it with `// periphery:ignore - <who calls it>` on the declaration.
- Never keep a declaration because it "might be used later".
- Unused imports have no working tool: remove one when the file no longer needs it.
