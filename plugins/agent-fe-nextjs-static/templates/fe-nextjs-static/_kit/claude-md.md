### Static site (agent-fe-nextjs-static)

- Every page is prerendered at build time; `scripts/check/site.config.json` sets the mode (export
  or ssg-with-endpoints) and the production origin. Rules in `.claude/rules/web/` load with a
  matching file; traps: `.claude/anti-patterns/INDEX.md`.
- Security headers live in the host's config (`public/_headers` by default), not in `next.config`.
- Done means `bash scripts/check/gates.sh` passes, and after `next build`,
  `node scripts/check/site-audit.mjs` too.
- `/agent-fe-nextjs-static:review`, `:seo-audit`, `:a11y-audit` and `:launch-checklist`; the
  `seo-validator`, `security-guard` and `i18n-guard` agents review a diff and only report.
