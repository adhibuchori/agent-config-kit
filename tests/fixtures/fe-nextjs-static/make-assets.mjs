#!/usr/bin/env node
// Writes the toy site's binary assets at test time, so the repo holds no binary files:
//   node make-assets.mjs <site dir>              every image and font stub the fixture needs
//   node make-assets.mjs --png <file> <w> <h>    one solid PNG of that size
//   node make-assets.mjs --bytes <file> <kb>     one file of that many KB (a budget breaker)
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { deflateSync } from 'node:zlib';

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
};

/** A valid solid-colour RGB PNG. */
export function png(width, height) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // RGB
  const row = Buffer.alloc(1 + width * 3, 0x4f);
  row[0] = 0; // filter: none
  const raw = Buffer.concat(Array.from({ length: height }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const write = (file, data) => {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, data);
};

const [cmd, ...rest] = process.argv.slice(2);
if (cmd === '--png') {
  const [file, w, h] = rest;
  write(file, png(Number(w), Number(h)));
} else if (cmd === '--bytes') {
  const [file, kb] = rest;
  write(file, Buffer.concat([png(1, 1), Buffer.alloc(Number(kb) * 1024)]));
} else if (cmd && !cmd.startsWith('--')) {
  const site = cmd;
  const hero = png(1200, 630);
  const logo = png(64, 64);
  for (const base of [join(site, 'public/images'), join(site, 'out/images')]) {
    write(join(base, 'hero.png'), hero);
    write(join(base, 'logo.png'), logo);
  }
  write(join(site, 'out/opengraph-image'), hero);
  // A font stub: the WOFF2 signature and padding. The checks read names and sizes, not glyphs.
  write(join(site, 'out/_next/static/media/brand.woff2'), Buffer.concat([Buffer.from('wOF2', 'ascii'), Buffer.alloc(2044)]));
} else {
  console.error('usage: make-assets.mjs <site dir> | --png <file> <w> <h> | --bytes <file> <kb>');
  process.exit(2);
}
