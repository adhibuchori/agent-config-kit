---
paths:
  - 'src/**/__tests__/**'
  - 'src/test/**'
  - 'bunfig.toml'
---

# Testing Requirements

> Two tiers run in this repo — unit (`bun test src`, no DB/Redis/network) and integration
> (`bun run test:integration`, real Postgres + Redis). The tier rules, the
> `shouldRunIntegrationTests()` gate, the shared doubles, and how to test a query live in
> [../backend/testing.md](../backend/testing.md). This file covers the practices common to both.

## Coverage: 100% per file

The policy is `.claude/rules/typescript/coverage.md`: 100% per file, lines and functions, over every
file in `src/**` outside the closed exemption list in `bunfig.toml`. Bun reports only files a test
loaded, so `bun run test:coverage` also runs `scripts/check/coverage-files.mjs`.

## Test-Driven Development

MANDATORY workflow:

1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Verify coverage: `bun run test:coverage` (100%, every file loaded)

## Troubleshooting Test Failures

1. Check test isolation
2. Verify mocks are correct — a result identical across cases that script different inputs means
   something other than your steering is answering (see
   `.claude/anti-patterns/bun-mock-module-is-process-wide.md`)
3. Fix implementation, not tests (unless tests are wrong)

## Test Structure (AAA Pattern)

Prefer Arrange-Act-Assert structure for tests:

```typescript
test('calculates similarity correctly', () => {
  // Arrange
  const vector1 = [1, 0, 0];
  const vector2 = [0, 1, 0];

  // Act
  const similarity = calculateCosineSimilarity(vector1, vector2);

  // Assert
  expect(similarity).toBe(0);
});
```

### Test Naming

Use descriptive names that explain the behavior under test:

```typescript
test('returns empty array when no rows match the filter', () => {});
test('throws error when API key is missing', () => {});
test('falls back to substring search when Redis is unavailable', () => {});
```
