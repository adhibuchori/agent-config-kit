---
description: Plan a fullstack feature before any code is written. Checks the backend API, the OpenAPI contract, the generated client and existing components first, then lists scope, ordered tasks, risks and open questions. Writes nothing
argument-hint: "[feature]"
---

# /agent-fe-nextjs:plan-fullstack — Fullstack Feature Planning

Run it before starting any new fullstack feature. This repo is the frontend. Find the backend repo,
and the content service's repo if the backend has one, in `SSOT.md` §2 or the workspace; if neither
names them, ask the user for their paths before step 1.

## Input

Feature: $ARGUMENTS

> **Note:** FE never calls a service that sits behind the backend — a content service,
> a database, a third-party API holding server credentials. All data flows through the backend; FE
> only knows about its API endpoints.

---

## 1. Research first

Do these research steps before drafting the plan; a plan that skips them guesses at the contract:

### 1.1 Backend (BE) Analysis

- **API**: Check the backend repo for existing endpoints and controllers.
- **Logic**: Review the backend's service files for business rules.
- **OpenAPI**: Check `openapi.json` (FE root) for the current API contract.

### 1.2 Frontend (FE) Analysis

- **Generated SDK**: Verify if `src/lib/api/generated/` already includes the needed endpoints.
- **Components**: Identify existing UI components in `src/components/` that can be reused.
- **Hooks**: Check `src/hooks/` for existing logic hooks.
- **Translations**: Check every catalogue in `src/messages/` (the pairs `localePairs` lists in
  `.claude/agent-config.json`, for example `en.json` and `id.json`) for missing keys.

### 1.3 Upstream Content Service Analysis — only if the backend has one

- **Content types**: Check the existing content-type definitions in the content service's repo for relevant models.
- **Fields**: Identify if new fields need to be added to existing content types.
- **Access control**: Review access rules if the feature involves restricted content.
- **Site-wide content**: Check shared, site-wide entries that may be affected.

---

## 2. SCOPE

Define what needs to be changed across every affected repository:

### Backend (BE)

- [ ] **Endpoints**: List new or updated API endpoints.
- [ ] **Logic**: List services or controllers to implement.
- [ ] **Migration strategy**: Note any data migration requirements.
- [ ] **OpenAPI**: Confirm `openapi.json` will be updated to reflect new endpoints.

### Content Service (optional)

- [ ] **Content types**: List new content types or fields to add.
- [ ] **Access control**: Note any access rule changes needed.
- [ ] **Site-wide content**: List any shared entries to add or modify.
- [ ] **Content re-entry**: Flag if existing content needs to be updated after a schema change.

### Frontend (FE) — this repo

- [ ] **SDK Sync**: Check if `bun generate:api` is required after BE changes.
- [ ] **Service Hooks**: List new hooks in `src/hooks/api/` (naming: `use{Domain}{Action}`).
- [ ] **Logic Hooks**: List new hooks in `src/hooks/` for extracted business logic.
- [ ] **UI**: List components to create (kebab-case file, PascalCase export) or modify.
- [ ] **Translations**: List new keys for every locale catalogue.
- [ ] **Store**: Check if any global UI state change is needed in `src/store/`.

---

## 3. TASKS

Format: `[ ] [TAG] [verb] [target] — est. Xmin`

- Each task: **5–30 min**. If larger, split it.
- Tags: `[CONTENT]` `[BE]` `[FE-API]` `[FE-UI]` `[FE-HOOK]` `[FE-i18n]` `[FE-STORE]`

Order by dependency — always content service → BE → FE:

1. _(if a content change is needed)_ **[CONTENT]** Add/modify content types or fields in the content service.
2. **[BE]** Implement controllers and services in the backend.
3. **[BE]** Update `openapi.json` to reflect new endpoints.
4. **[FE-API]** Run `bun generate:api` and create service hooks in `src/hooks/api/`.
5. **[FE-UI]** / **[FE-HOOK]** Build/Modify components and logic hooks in this repo.
6. _(if strings changed)_ **[FE-i18n]** Add translations to every locale catalogue.

---

## 4. RISKS

Format: `[HIGH/MED/LOW] [risk] → [mitigation]`

- Flag potential breaking changes in the API contract (`openapi.json`).
- Flag hydration issues or locale mismatches.
- Flag if a content-schema change requires content re-entry.

---

## 5. CONFIRMATION

Generate 1–3 questions **specific to this feature** that need user answers before execution starts. Examples of the kind of questions to ask (do not copy verbatim — derive from the actual feature):

- Is the proposed API contract (endpoint shape, request/response) aligned with what the BE team expects?
- Are there content implications that require coordination with content editors?
- Are there any UI constraints, brand guidelines, or copy decisions that must be confirmed first?

If no open questions → state: "No blockers — ready to execute."

---

## Hard Rules (Fullstack)

- **Do not skip BE research**: Always verify if the backend supports the feature before planning the FE.
- **SDK Rule**: Always use the generated SDK from `src/lib/api/generated/`. If it's missing an endpoint, the task is to update the BE and regenerate first.
- **Upstream services are invisible to FE**: Never plan a direct fetch to anything behind the backend.
- **Sync i18n**: Never add a translation to one catalogue without the others.
