#!/usr/bin/env node
// Security headers for static hosting. next.config headers() does not apply to a static export,
// so the headers live in a file the host reads: a `_headers` file (path lines, then indented
// "Name: value" lines) or an nginx config (add_header). headersFile in scripts/check/site.config.json
// names it (default public/_headers). Checks CSP, HSTS, nosniff, Referrer-Policy, framing and
// Permissions-Policy for every built page path (or / without a build).
//   --verify-hashes  every inline <script> in the build is allowed by the page's CSP (hash-based
//                    CSP: a hash that is missing means the page will not hydrate)
//   --print-hashes   print the 'sha256-...' sources each page needs, to write a hash-based CSP
// Rule: .claude/rules/web/security.md. The live response is what counts: re-check it on the
// deployed URL (curl -I).
//
//   node scripts/check/security-headers.mjs [--verify-hashes | --print-hashes] [--file F] [--dir out]
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { UsageError, openSite, parseHtml, run } from './lib/site.mjs';

const EXECUTABLE = new Set(['', 'text/javascript', 'application/javascript', 'module']);
const YEAR = 31536000;

/** [{ pattern, headers: [[name, value]] }] from a _headers file or an nginx config. */
function parseHeadersFile(text) {
  if (/^\s*add_header\s/m.test(text)) {
    const headers = [
      ...text.matchAll(
        /^\s*add_header\s+([A-Za-z0-9-]+)\s+("([^"]*)"|'([^']*)'|(\S+?))(\s+always)?\s*;/gm,
      ),
    ].map((m) => [m[1], m[3] ?? m[4] ?? m[5]]);
    return { format: 'nginx', rules: [{ pattern: '/*', headers }] };
  }
  const rules = [];
  let current = null;
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    if (!/^\s/.test(raw)) {
      current = { pattern: raw.trim(), headers: [] };
      rules.push(current);
      continue;
    }
    const m = raw.trim().match(/^([A-Za-z0-9-]+)\s*:\s*(.*)$/);
    if (!m) continue;
    if (!current) {
      current = { pattern: '/*', headers: [] };
      rules.push(current);
    }
    current.headers.push([m[1], m[2].trim()]);
  }
  return { format: '_headers', rules };
}

function patternRe(pattern) {
  const body = pattern
    .replace(/^https?:\/\/[^/]+/, '')
    .replace(/[.+?^${}()|[\]\\]/g, '\\$&')
    .replace(/:[A-Za-z]\w*/g, '[^/]+')
    .replace(/\*/g, '.*');
  return new RegExp(`^${body}$`);
}

/** Every header that applies to a path, as lower-case name -> [values]. */
function headersFor(rules, path) {
  const out = new Map();
  for (const r of rules) {
    const re = patternRe(r.pattern);
    if (
      !re.test(path) &&
      !(path.endsWith('/') && re.test(path.slice(0, -1))) &&
      !re.test(`${path}/`)
    )
      continue;
    for (const [name, value] of r.headers) {
      const k = name.toLowerCase();
      out.set(k, [...(out.get(k) || []), value]);
    }
  }
  return out;
}

function parseCsp(value) {
  const d = new Map();
  for (const part of value.split(';')) {
    const [name, ...sources] = part.trim().split(/\s+/);
    if (name && !d.has(name.toLowerCase())) d.set(name.toLowerCase(), sources);
  }
  return d;
}

const scriptSources = (csp) =>
  csp.get('script-src-elem') || csp.get('script-src') || csp.get('default-src') || null;

function checkPolicy(csp, where, report) {
  const scripts = scriptSources(csp);
  if (!scripts)
    report.error(where, 'CSP has neither script-src nor default-src: scripts are unrestricted');
  else {
    if (scripts.includes("'unsafe-eval'")) report.error(where, "CSP allows 'unsafe-eval'");
    const loose = scripts.filter((s) => s === '*' || /^(https?|data|blob):$/.test(s));
    if (loose.length)
      report.error(where, `CSP script sources ${loose.join(' ')} allow scripts from anywhere`);
    const pinned = scripts.some((s) => /^'(sha(256|384|512)-|nonce-)/.test(s));
    if (scripts.includes("'unsafe-inline'") && !pinned) {
      report.warn(
        where,
        "CSP allows 'unsafe-inline' scripts: list their sha256 hashes instead (--print-hashes), or record why you accept it",
      );
    }
  }
  const objects = csp.get('object-src') || csp.get('default-src');
  if (!objects || !(objects.length === 1 && objects[0] === "'none'"))
    report.error(where, "CSP needs object-src 'none'");
  if (!csp.get('base-uri')) report.error(where, "CSP needs base-uri 'self' (or 'none')");
  const connect = csp.get('connect-src') || csp.get('default-src') || [];
  if (connect.includes('*')) report.error(where, 'CSP connect-src allows any host');
}

function inlineScripts(doc) {
  return doc
    .all('script')
    .filter(
      (s) =>
        s.attrs.src === undefined &&
        EXECUTABLE.has((s.attrs.type || '').toLowerCase()) &&
        s.text !== undefined,
    );
}

const sha256 = (text) => `'sha256-${createHash('sha256').update(text, 'utf8').digest('base64')}'`;

run(
  'security-headers',
  ({ args, root, cfg, report }) => {
    const file = args.file ?? cfg.headersFile;
    let site = null;
    try {
      site = openSite(root, cfg, args.dir);
    } catch (e) {
      if (!(e instanceof UsageError) || args.dir || args['verify-hashes'] || args['print-hashes'])
        throw e;
    }

    if (args['print-hashes']) {
      for (const page of site.pages) {
        const hashes = [
          ...new Set(
            inlineScripts(parseHtml(readFileSync(page.file, 'utf8'))).map((s) => sha256(s.text)),
          ),
        ];
        console.log(`${page.path}\t${hashes.join(' ')}`);
      }
      return 0;
    }

    if (!file) {
      report.info(
        'SKIPPED: headersFile is empty in scripts/check/site.config.json, so nothing here proves the headers; check them on the live URL (curl -I)',
      );
      return report.finish('no headers file configured');
    }
    const path = join(root, file);
    if (!existsSync(path)) {
      report.error(
        file,
        'missing: a static host needs the headers in its own config (next.config headers() does not apply to an export); create it or point headersFile at the file your host reads',
      );
      return report.finish('');
    }
    const { format, rules } = parseHeadersFile(readFileSync(path, 'utf8'));
    const paths = site ? site.pages.map((p) => p.path) : ['/'];

    // Pages that get the same headers are checked once.
    const groups = new Map();
    for (const p of paths) {
      const h = headersFor(rules, p);
      const key = JSON.stringify([...h.entries()].toSorted());
      if (!groups.has(key)) groups.set(key, { h, paths: [] });
      groups.get(key).paths.push(p);
    }
    for (const { h, paths: group } of groups.values()) {
      const where = `${file} for ${group[0]}${group.length > 1 ? ` (+${group.length - 1} more)` : ''}`;
      const first = (n) => (h.get(n) || [])[0];
      const csps = h.get('content-security-policy') || [];
      if (!csps.length) report.error(where, 'no Content-Security-Policy');
      const policies = csps.map(parseCsp);
      policies.forEach((c) => checkPolicy(c, where, report));
      if (!policies.some((c) => c.get('frame-ancestors'))) {
        if (/^(deny|sameorigin)$/i.test(first('x-frame-options') || ''))
          report.warn(where, "X-Frame-Options only: add CSP frame-ancestors 'none' (or 'self')");
        else
          report.error(
            where,
            "no framing protection: CSP frame-ancestors 'none' (or X-Frame-Options: DENY)",
          );
      }
      const hsts = first('strict-transport-security');
      if (!hsts) report.error(where, 'no Strict-Transport-Security');
      else {
        const age = Number((hsts.match(/max-age=(\d+)/i) || [])[1] || 0);
        if (age < YEAR) report.error(where, `HSTS max-age=${age}; use at least ${YEAR} (one year)`);
        if (!/includesubdomains/i.test(hsts)) report.warn(where, 'HSTS without includeSubDomains');
      }
      if ((first('x-content-type-options') || '').toLowerCase() !== 'nosniff')
        report.error(where, 'X-Content-Type-Options must be nosniff');
      const referrer = (first('referrer-policy') || '').toLowerCase();
      if (!referrer)
        report.error(
          where,
          'no Referrer-Policy (strict-origin-when-cross-origin is a safe default)',
        );
      else if (/unsafe-url/.test(referrer))
        report.error(where, 'Referrer-Policy unsafe-url leaks full URLs to every site');
      if (!first('permissions-policy'))
        report.warn(
          where,
          'no Permissions-Policy: deny the features the site does not use (camera, microphone, geolocation, payment)',
        );
      if (!first('cross-origin-opener-policy'))
        report.warn(where, 'no Cross-Origin-Opener-Policy (same-origin)');
    }

    let hashesChecked = 0;
    if (args['verify-hashes'] && site) {
      for (const page of site.pages) {
        const policies = (headersFor(rules, page.path).get('content-security-policy') || []).map(
          parseCsp,
        );
        const html = readFileSync(page.file, 'utf8');
        const doc = parseHtml(html);
        const scripts = inlineScripts(doc);
        const external = doc
          .all('script')
          .filter((x) => x.attrs.src !== undefined && !x.attrs.integrity);
        for (const csp of policies) {
          const sources = scriptSources(csp);
          if (!sources) continue;
          const pinned = sources.some((x) => /^'(sha(256|384|512)-|nonce-)/.test(x));
          const inlineOk = sources.includes("'unsafe-inline'") && !pinned;
          for (const sc of scripts) {
            hashesChecked++;
            if (inlineOk) continue;
            const digest = sha256(sc.text);
            if (!sources.includes(digest))
              report.error(
                page.rel,
                `inline script ${digest} is blocked by the CSP for ${page.path}: the page will not hydrate (--print-hashes lists what it needs)`,
              );
          }
          if (sources.includes("'strict-dynamic'") && external.length) {
            report.error(
              page.rel,
              `'strict-dynamic' ignores 'self' and host sources, so ${external.length} <script src> without integrity are blocked`,
            );
          }
        }
      }
    }
    return report.finish(
      `${format} format, ${paths.length} path(s)${args['verify-hashes'] ? `, ${hashesChecked} inline script check(s)` : ''}`,
    );
  },
  { switches: ['verify-hashes', 'print-hashes'] },
);
