### iOS app (agent-ios-swiftui)

- Rules: `AGENTS.md`; traps: `.claude/anti-patterns/INDEX.md`. Review with the
  `agent-ios-swiftui:reviewer` and `agent-ios-swiftui:i18n-guard` subagents.
- The API client is generated from the backend's spec copy: refresh it with
  `bash scripts/ios/api-client.sh`; the `generated-guard` hook refuses hand edits to either.
