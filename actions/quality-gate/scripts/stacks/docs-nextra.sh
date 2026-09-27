# shellcheck shell=bash
# docs-nextra (agent-docs-nextra): a Nextra documentation site. Sourced by gate.sh after lib.sh.
#
# A docs site has no test suite, so there is no coverage floor. The scans skip content/: its pages
# may quote the very patterns they refuse.
stack_gate() {
  qg_js_install || return 0
  qg_gates
  qg_env_committed
  qg_js_scans
  qg_gitleaks
  qg_js_audit
  qg_skill_scan
  # docs:generate writes these placeholders when a source JSDoc is incomplete. A warning, not a
  # failure: the page is still correct, only unfinished.
  qg_step "Generated Page TODOs"
  local todos
  todos=$(git diff --name-only --diff-filter=ACMR "${QG_BASE}...HEAD" -- 'content/technical/*.mdx' |
    while IFS= read -r f; do [ -f "$f" ] && grep -lE '_TODO_|TODO: Add usage example' -- "$f"; done)
  if [ -n "$todos" ]; then
    printf '%s\n' "$todos" | qg_quote
    echo "::warning::these generated pages still hold TODO placeholders; fill them in before merging"
  else
    echo "Clean"
  fi
  qg_build
  # out/ is what ships; .next/ is what it is copied from.
  qg_source_maps .next/static out/_next/static
}
