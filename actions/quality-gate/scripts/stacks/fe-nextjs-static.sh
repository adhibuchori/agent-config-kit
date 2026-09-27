# shellcheck shell=bash
# fe-nextjs-static (agent-fe-nextjs-static): a static Next.js site (output 'export', or static pages
# plus a few route handlers). Sourced by gate.sh after lib.sh.
#
# The source gates from gates.list, the pull-request checks, then `next build` and the checks that
# read the built site: scripts/check/site-audit.mjs (sitemap and robots, metadata, share images,
# JSON-LD, links, images, fonts, bundle size, security headers). The browser checks (check:a11y,
# check:lighthouse) need a browser and stay out of this gate.
stack_gate() {
  qg_js_install || return 0
  qg_gates
  qg_coverage_floor
  qg_env_committed
  qg_js_scans
  qg_gitleaks
  qg_js_audit
  qg_skill_scan
  qg_build
  qg_step "Built Site Audit (scripts/check/site-audit.mjs)"
  if [ -f scripts/check/site-audit.mjs ]; then
    # A production build: a noindex robots.txt or a missing canonical fails here, not after launch.
    node scripts/check/site-audit.mjs --env production || qg_fail "the built site failed a check in site-audit.mjs (table above)"
  else
    qg_skip "Built Site Audit" "scripts/check/site-audit.mjs is missing: run /agent-fe-nextjs-static:setup"
  fi
  qg_source_maps out/_next/static .next/static
}
