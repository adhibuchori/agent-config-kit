#!/usr/bin/env node
// Serves the built site on 127.0.0.1 the way a static host would, for the checks that need a
// browser: a11y.mjs, and Lighthouse CI through lighthouserc.json. It reads both layouts: out/
// (export) and .next/server/app + .next/static + public/ (ssg-with-endpoints). A path that is not
// built gets the site's own 404 page with status 404. Text responses are gzipped when the client
// accepts it, as hosts do, so a lab run measures realistic transfer sizes. It binds 127.0.0.1 only,
// and it serves pages, not endpoints: route handlers need `next start`.
//
//   node scripts/check/serve.mjs [--port 4173] [--dir out] [--root .] [--config FILE]
//
// It prints "ready on http://127.0.0.1:<port>/" once it listens, and stops on Ctrl-C or SIGTERM.
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { basename, extname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';
import { UsageError, openSite, run } from './lib/site.mjs';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.pdf': 'application/pdf',
};

// By extension, as most static hosts decide it. An extension-less file (a generated
// opengraph-image under export) is served as bytes, which is what such a host sends too.
const typeFor = (name) => TYPES[extname(name).toLowerCase()] || 'application/octet-stream';
const COMPRESSIBLE = /^(text\/|application\/(json|xml|manifest\+json)|image\/svg\+xml)/;

/** Starts serving `site` (from openSite); resolves to { url, close }. Port 0 picks a free one. */
export function startServer(site, port = 0) {
  const notFound = site.pages.find((p) =>
    ['404.html', '_not-found.html'].includes(basename(p.file)),
  );
  const server = createServer((req, res) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { Allow: 'GET, HEAD' });
      res.end();
      return;
    }
    let path = null;
    try {
      path = new URL(req.url || '/', 'http://127.0.0.1').pathname;
    } catch {
      path = null;
    }
    const file = path ? site.resolvePath(path) : null;
    const send = (status, f, typeName) => {
      const type = typeFor(typeName);
      let body = readFileSync(f);
      const headers = {
        'Content-Type': type,
        'Cache-Control': 'no-store',
        Vary: 'Accept-Encoding',
      };
      if (COMPRESSIBLE.test(type) && /\bgzip\b/.test(req.headers['accept-encoding'] || '')) {
        body = gzipSync(body, { level: 6 });
        headers['Content-Encoding'] = 'gzip';
      }
      headers['Content-Length'] = body.length;
      res.writeHead(status, headers);
      res.end(req.method === 'HEAD' ? undefined : body);
    };
    // A prerendered metadata route in the ssg layout is <name>.body: its type comes from the URL.
    if (file) send(200, file, file.endsWith('.body') ? path : file);
    else if (notFound) send(404, notFound.file, notFound.file);
    else {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('not found\n');
    }
  });
  return new Promise((resolve, reject) => {
    server.once('error', (e) =>
      reject(e.code === 'EADDRINUSE' ? new UsageError(`port ${port} is already in use`) : e),
    );
    server.listen(port, '127.0.0.1', () => {
      const { port: bound } = server.address();
      resolve({
        url: `http://127.0.0.1:${bound}`,
        close: () =>
          new Promise((done) => {
            server.closeAllConnections?.();
            server.close(() => done());
          }),
      });
    });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run('serve', async ({ args, root, cfg }) => {
    const site = openSite(root, cfg, args.dir);
    const port = args.port === undefined ? 4173 : Number(args.port);
    if (!Number.isInteger(port) || port < 0 || port > 65535)
      throw new UsageError('--port must be a whole number from 0 to 65535');
    const { url, close } = await startServer(site, port);
    console.log(`serve: ${site.mode} build, ${site.pages.length} page(s), ready on ${url}/`);
    await new Promise((resolve) => {
      process.once('SIGINT', resolve);
      process.once('SIGTERM', resolve);
    });
    await close();
    return 0;
  });
}
