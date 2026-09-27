# shellcheck shell=bash
# Shared setup for the agent-fe-nextjs-static tests: each test gets its own copy of the toy site
# (tests/fixtures/fe-nextjs-static/site) with its images generated, then runs a check from the
# plugin's templates against it and asserts the exit code and the finding.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
TEMPLATES="$REPO_ROOT/plugins/agent-fe-nextjs-static/templates/fe-nextjs-static"
CHECKS="$TEMPLATES/scripts/check"
FIXTURE="$REPO_ROOT/tests/fixtures/fe-nextjs-static"

# Copies the toy site into this test's temp dir, generates its binary assets, and cd's into it.
make_site() {
  command -v node >/dev/null 2>&1 || skip "node is not installed"
  SITE="$BATS_TEST_TMPDIR/site"
  rm -rf "$SITE"
  cp -R "$FIXTURE/site" "$SITE"
  node "$FIXTURE/make-assets.mjs" "$SITE"
  cd "$SITE" || return 1
  unset NEXT_PUBLIC_SITE_URL
}

# Runs one check against the current site: check <name> [args...]
check() {
  local name="$1"
  shift
  run --separate-stderr node "$CHECKS/$name.mjs" "$@"
}

# Replaces text in a file (literal, first occurrence of each line match is fine for fixtures).
replace() {
  local file="$1" from="$2" to="$3"
  FROM="$from" TO="$to" node -e '
    const fs = require("fs");
    const f = process.argv[1];
    const s = fs.readFileSync(f, "utf8");
    if (!s.includes(process.env.FROM)) { console.error("replace: text not found in " + f); process.exit(1); }
    fs.writeFileSync(f, s.split(process.env.FROM).join(process.env.TO));
  ' "$file"
}

# Sets a key in scripts/check/site.config.json (value is JSON): set_config images.maxKB 1
set_config() {
  KEY="$1" VALUE="$2" node -e '
    const fs = require("fs");
    const f = "scripts/check/site.config.json";
    const c = JSON.parse(fs.readFileSync(f, "utf8"));
    const keys = process.env.KEY.split(".");
    let o = c;
    for (const k of keys.slice(0, -1)) o = o[k] = o[k] || {};
    o[keys[keys.length - 1]] = JSON.parse(process.env.VALUE);
    fs.writeFileSync(f, JSON.stringify(c, null, 2) + "\n");
  '
}

# Rearranges the built site the way `next build` lays it out without output: 'export'
# (ssg-with-endpoints): pages in .next/server/app, metadata routes as .body files, static
# chunks in .next/static, public files served from public/.
to_ssg_layout() {
  replace next.config.mjs "  output: 'export',
" ""
  mkdir -p .next/server/app .next/static
  cp -R out/_next/static/. .next/static/
  (cd out && find . -name '*.html' | while IFS= read -r f; do
    mkdir -p "../.next/server/app/$(dirname "$f")"
    cp "$f" "../.next/server/app/$f"
  done)
  cp out/robots.txt .next/server/app/robots.txt.body
  cp out/sitemap.xml .next/server/app/sitemap.xml.body
  cp out/opengraph-image .next/server/app/opengraph-image.body
  cp out/icon.svg .next/server/app/icon.svg.body
  rm -rf out
}

PLUGIN="$REPO_ROOT/plugins/agent-fe-nextjs-static"
PLUGIN_TEMPLATES="$PLUGIN/templates"
CORE="$REPO_ROOT/plugins/agent-core"
export PLUGIN PLUGIN_TEMPLATES CORE

# Stand-ins for the project's own accessibility checkers, written into node_modules/.bin of the
# current site. Each fetches every URL it is given (so the local server is proven too) and prints
# what it saw. STUB_EXIT sets its exit code; the axe stand-in adds one violation with STUB_VIOLATION=1.
stub_pa11y() {
  mkdir -p node_modules/.bin
  cat >node_modules/.bin/pa11y-ci <<'JS'
#!/usr/bin/env node
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync(process.argv[process.argv.indexOf('--config') + 1], 'utf8'));
(async () => {
  for (const u of cfg.urls) {
    const r = await fetch(u);
    console.log(`STUB ${r.status} ${u.replace(/^http:\/\/127\.0\.0\.1:\d+/, '')}`);
    if (r.status !== 200) process.exit(1);
  }
  console.log(`STUB defaults ${JSON.stringify(cfg.defaults)}`);
  process.exit(Number(process.env.STUB_EXIT || 0));
})();
JS
  chmod +x node_modules/.bin/pa11y-ci
}

stub_axe() {
  mkdir -p node_modules/.bin
  cat >node_modules/.bin/axe <<'JS'
#!/usr/bin/env node
const urls = process.argv.slice(2).filter((a) => a.startsWith('http'));
const tags = process.argv[process.argv.indexOf('--tags') + 1];
if (!process.argv.includes('--stdout')) process.exit(3);
(async () => {
  const out = [];
  for (const u of urls) {
    const r = await fetch(u);
    const violations = process.env.STUB_VIOLATION === '1' && out.length === 0
      ? [{ id: 'image-alt', impact: 'critical', help: 'Images must have alternate text', nodes: [{}, {}] }]
      : [];
    out.push({ url: u, status: r.status, tags, violations });
  }
  process.stdout.write(JSON.stringify(out));
  process.exit(Number(process.env.STUB_EXIT || 0));
})();
JS
  chmod +x node_modules/.bin/axe
}
