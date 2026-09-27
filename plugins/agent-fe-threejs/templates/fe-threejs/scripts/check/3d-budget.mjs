#!/usr/bin/env node
/**
 * 3D-BUDGET — asset budgets for a site that ships three.js or React Three Fiber scenes.
 * Why the budgets exist: .claude/rules/web/3d.md § 5. The numbers live in
 * scripts/check/3d-budget.json, which is this repo's to edit.
 *
 * For every file under the configured roots:
 * - models (.glb, .gltf): bytes, counting the buffers and images a model points at; triangles as
 *   rendered (a mesh placed by three nodes counts three times, GPU instancing multiplies); and each
 *   image the model carries: bytes and pixel size
 * - textures (.ktx2 and .basis anywhere; .png .jpg .jpeg .webp .avif inside textureDirs): bytes, and
 *   the longer side in pixels where the header says
 * - environment maps (.hdr, .exr): bytes
 *
 * Raise a budget for one file with an `exceptions` entry (path, budget, max, reason). The path is the
 * file that holds the bytes: the model for an image inside it, the image file for one beside it.
 *
 * Plain Node ESM with no dependencies, so it runs under node or bun. It reads local files only.
 * Exit 0 within budget, 1 over budget or unreadable, 2 a configuration or usage error. `--warn`
 * reports and exits 0, for a repo that is adopting budgets it does not meet yet.
 */

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
process.chdir(ROOT);

const CONFIG = 'scripts/check/3d-budget.json';
const RULES = '.claude/rules/web/3d.md';
const USAGE = `usage: node scripts/check/3d-budget.mjs [--warn]

Checks models, textures and environment maps against ${CONFIG}.
  --warn   report, but exit 0
Exit 0 within budget, 1 over budget or unreadable, 2 a configuration or usage error.`;

const BUDGET_KEYS = ['modelKB', 'triangles', 'textureKB', 'texturePx', 'environmentKB'];
const CONFIG_KEYS = new Set(['roots', 'textureDirs', 'budgets', 'exceptions']);
const EXCEPTION_KEYS = new Set(['path', 'budget', 'max', 'reason']);
const MODEL_EXT = new Set(['.glb', '.gltf']);
const GPU_TEXTURE_EXT = new Set(['.ktx2', '.basis']);
const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.webp', '.avif']);
const ENVIRONMENT_EXT = new Set(['.hdr', '.exr']);
const SKIPPED_DIRS = new Set(['node_modules', '.git']);
const KTX2_ID = Buffer.from([0xab, 0x4b, 0x54, 0x58, 0x20, 0x32, 0x30, 0xbb, 0x0d, 0x0a, 0x1a, 0x0a]);

class Unreadable extends Error {}

const usageError = (message) => {
  console.error(`3d-budget: ${message}`);
  console.error(USAGE);
  process.exit(2);
};
const configError = (message) => {
  console.error(`3d-budget: ${CONFIG}: ${message}`);
  process.exit(2);
};
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
/* Text from a file, made safe to print: no control characters, bounded length. */
const clean = (text) => {
  const flat = String(text).replace(/[\u0000-\u001f\u007f]+/g, ' ');
  return flat.length > 80 ? `${flat.slice(0, 79)}…` : flat;
};
const plural = (n, word) => `${n.toLocaleString('en-US')} ${word}${n === 1 ? '' : 's'}`;

// ── arguments and configuration ─────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
if (args.includes('-h') || args.includes('--help')) {
  console.log(USAGE);
  process.exit(0);
}
for (const arg of args) if (arg !== '--warn') usageError(`unknown argument ${JSON.stringify(clean(arg))}`);
const WARN_ONLY = args.includes('--warn');

/* A repo-relative path in the config: forward slashes, no leading slash, no `..`. */
const repoPath = (value, where) => {
  if (typeof value !== 'string' || value.trim() === '') configError(`${where} must be a non-empty path`);
  const path = value.replace(/\\/g, '/').replace(/\/+$/, '').replace(/^\.\//, '');
  if (path === '' || isAbsolute(path) || path.split('/').includes('..')) {
    configError(`${where} must be a path inside the repository, such as "public"`);
  }
  return path;
};

const loadConfig = () => {
  if (!existsSync(CONFIG)) configError('not found; /agent-fe-threejs:setup creates it');
  let raw;
  try {
    raw = JSON.parse(readFileSync(CONFIG, 'utf8'));
  } catch (error) {
    configError(`not JSON (${clean(error.message)})`);
  }
  if (!isObject(raw)) configError('must hold a JSON object');
  for (const key of Object.keys(raw)) {
    if (!key.startsWith('//') && !CONFIG_KEYS.has(key)) configError(`unknown key "${clean(key)}"`);
  }
  if (!Array.isArray(raw.roots) || raw.roots.length === 0) configError('"roots" must list at least one folder');
  const roots = [...new Set(raw.roots.map((root, i) => repoPath(root, `roots[${i}]`)))];
  for (const root of roots) {
    if (!existsSync(root) || !statSync(root).isDirectory()) {
      configError(`root "${root}" is not a folder in this repository; point "roots" at the folders your assets are served from`);
    }
  }
  const textureDirs = raw.textureDirs === undefined ? [] : raw.textureDirs;
  if (!Array.isArray(textureDirs)) configError('"textureDirs" must be a list of folders');
  const dirs = textureDirs.map((dir, i) => repoPath(dir, `textureDirs[${i}]`));

  if (!isObject(raw.budgets)) configError('"budgets" must be an object');
  for (const key of Object.keys(raw.budgets)) {
    if (!key.startsWith('//') && !BUDGET_KEYS.includes(key)) configError(`unknown budget "${clean(key)}"`);
  }
  const budgets = {};
  for (const key of BUDGET_KEYS) {
    const value = raw.budgets[key];
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
      configError(`budgets.${key} must be a positive number`);
    }
    budgets[key] = value;
  }

  const exceptions = new Map();
  const list = raw.exceptions === undefined ? [] : raw.exceptions;
  if (!Array.isArray(list)) configError('"exceptions" must be a list');
  list.forEach((entry, i) => {
    const where = `exceptions[${i}]`;
    if (!isObject(entry)) configError(`${where} must be an object`);
    for (const key of Object.keys(entry)) {
      if (!key.startsWith('//') && !EXCEPTION_KEYS.has(key)) configError(`${where} has an unknown key "${clean(key)}"`);
    }
    const path = repoPath(entry.path, `${where}.path`);
    if (!BUDGET_KEYS.includes(entry.budget)) configError(`${where}.budget must be one of ${BUDGET_KEYS.join(', ')}`);
    if (typeof entry.max !== 'number' || !Number.isFinite(entry.max) || entry.max <= budgets[entry.budget]) {
      configError(`${where}.max must be a number above budgets.${entry.budget} (${budgets[entry.budget]}): an exception raises a budget`);
    }
    if (typeof entry.reason !== 'string' || entry.reason.trim().length < 10) {
      configError(`${where}.reason must say why this file needs more (at least 10 characters)`);
    }
    const id = `${path}\u0000${entry.budget}`;
    if (exceptions.has(id)) configError(`${where} repeats the exception for ${path} ${entry.budget}`);
    exceptions.set(id, { path, budget: entry.budget, max: entry.max, used: false, peak: 0 });
  });
  return { roots, textureDirs: dirs, budgets, exceptions };
};

const config = loadConfig();

// ── findings ────────────────────────────────────────────────────────────────────────────────────

const findings = [];
const warnings = [];
const KB = 1024;
const shown = {
  modelKB: (bytes) => `${(bytes / KB).toFixed(1)} KB`,
  textureKB: (bytes) => `${(bytes / KB).toFixed(1)} KB`,
  environmentKB: (bytes) => `${(bytes / KB).toFixed(1)} KB`,
  triangles: (n) => plural(n, 'triangle'),
  texturePx: (px) => `${px.toLocaleString('en-US')} px`,
};
const limitShown = (key, limit) => (key.endsWith('KB') ? `${limit.toLocaleString('en-US')} KB` : shown[key](limit));

/* measure(file, subject, budget, value): one measured value against its budget. `file` is the file
   that holds the bytes, the key an exception names. KB budgets take bytes. */
const measure = (file, subject, key, value, detail = '') => {
  const exception = config.exceptions.get(`${file}\u0000${key}`);
  const limit = exception ? exception.max : config.budgets[key];
  const scaled = key.endsWith('KB') ? value / KB : value;
  if (exception) {
    exception.used = true;
    exception.peak = Math.max(exception.peak, scaled);
  }
  if (scaled > limit) {
    const raised = exception ? ', raised by an exception' : '';
    findings.push(`${subject}: ${shown[key](value)}${detail} > ${limitShown(key, limit)} (${key}${raised})`);
  }
};
const unreadable = (subject, reason) => findings.push(`${subject}: unreadable, ${reason}`);

// ── image headers ───────────────────────────────────────────────────────────────────────────────

const jpegSize = (b) => {
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return null;
    let marker = b[i + 1];
    while (marker === 0xff && i + 2 < b.length) {
      i += 1;
      marker = b[i + 1];
    }
    if (marker === 0x01 || marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7)) {
      i += 2;
      continue;
    }
    if (marker === 0xd9 || marker === 0xda || i + 4 > b.length) return null;
    const isFrame = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrame) {
      if (i + 9 > b.length) return null;
      return { width: b.readUInt16BE(i + 7), height: b.readUInt16BE(i + 5) };
    }
    i += 2 + b.readUInt16BE(i + 2);
  }
  return null;
};

const webpSize = (b) => {
  const chunk = b.toString('latin1', 12, 16);
  if (chunk === 'VP8X' && b.length >= 30) return { width: 1 + b.readUIntLE(24, 3), height: 1 + b.readUIntLE(27, 3) };
  if (chunk === 'VP8L' && b.length >= 25 && b[20] === 0x2f) {
    const bits = b.readUInt32LE(21);
    return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >>> 14) & 0x3fff) };
  }
  if (chunk === 'VP8 ' && b.length >= 30 && b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a) {
    return { width: b.readUInt16LE(26) & 0x3fff, height: b.readUInt16LE(28) & 0x3fff };
  }
  return null;
};

/* AVIF (and any HEIF image): the largest `ispe` (image spatial extent) property in the header. */
const avifSize = (b) => {
  let best = null;
  const end = Math.min(b.length, 1 << 20);
  for (let i = b.indexOf('ispe', 4, 'latin1'); i !== -1 && i + 16 <= end; i = b.indexOf('ispe', i + 4, 'latin1')) {
    const width = b.readUInt32BE(i + 8);
    const height = b.readUInt32BE(i + 12);
    if (!best || width * height > best.width * best.height) best = { width, height };
  }
  return best;
};

/* Width and height from an image's header, or null when the format is one this check does not read. */
const imageSize = (b) => {
  if (b.length >= 24 && b.readUInt32BE(0) === 0x89504e47 && b.toString('latin1', 12, 16) === 'IHDR') {
    return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
  }
  if (b.length >= 4 && b[0] === 0xff && b[1] === 0xd8) return jpegSize(b);
  if (b.length >= 30 && b.toString('latin1', 0, 4) === 'RIFF' && b.toString('latin1', 8, 12) === 'WEBP') return webpSize(b);
  if (b.length >= 16 && b.toString('latin1', 4, 8) === 'ftyp') return avifSize(b);
  if (b.length >= 28 && b.subarray(0, 12).equals(KTX2_ID)) return { width: b.readUInt32LE(20), height: b.readUInt32LE(24) };
  return null;
};

/* The texture checks for one image: bytes, then the longer side when the header gives one. */
const checkImage = (file, subject, bytes) => {
  measure(file, subject, 'textureKB', bytes.length);
  const size = imageSize(bytes);
  if (size) measure(file, subject, 'texturePx', Math.max(size.width, size.height), ` (${size.width}x${size.height})`);
};

// ── glTF ────────────────────────────────────────────────────────────────────────────────────────

const parseGlb = (data) => {
  if (data.length < 20 || data.readUInt32LE(0) !== 0x46546c67) throw new Unreadable('not a glTF binary (no glTF header)');
  const version = data.readUInt32LE(4);
  if (version !== 2) throw new Unreadable(`glTF binary version ${version}, not 2`);
  const length = data.readUInt32LE(8);
  if (length > data.length) throw new Unreadable(`its header says ${length} bytes, the file has ${data.length}`);
  let json = null;
  let bin = null;
  for (let offset = 12; offset + 8 <= length; ) {
    const size = data.readUInt32LE(offset);
    const type = data.readUInt32LE(offset + 4);
    const start = offset + 8;
    if (start + size > length) throw new Unreadable('a chunk runs past the end of the file');
    if (type === 0x4e4f534a && json === null) {
      try {
        json = JSON.parse(data.toString('utf8', start, start + size));
      } catch (error) {
        throw new Unreadable(`its JSON chunk is not JSON (${clean(error.message)})`);
      }
    } else if (type === 0x004e4942 && bin === null) {
      bin = data.subarray(start, start + size);
    }
    offset = start + size;
  }
  if (json === null) throw new Unreadable('no JSON chunk');
  return { json, bin };
};

const decodeDataUri = (uri) => {
  const comma = uri.indexOf(',');
  if (comma === -1) throw new Unreadable('a data: URI without a comma');
  const head = uri.slice(5, comma);
  const payload = uri.slice(comma + 1);
  return /;base64$/i.test(head) ? Buffer.from(payload, 'base64') : Buffer.from(decodeURIComponent(payload), 'latin1');
};

/* Where a URI inside a model points: its bytes (data:), a file in the repo, or somewhere unchecked. */
const locate = (model, uri) => {
  if (/^data:/i.test(uri)) return { kind: 'data', bytes: decodeDataUri(uri) };
  if (/^[a-z][a-z0-9+.-]*:/i.test(uri)) return { kind: 'remote' };
  let path;
  try {
    path = decodeURIComponent(uri);
  } catch {
    throw new Unreadable(`malformed URI ${JSON.stringify(clean(uri))}`);
  }
  const inside = relative(ROOT, resolve(dirname(model), path));
  if (inside === '' || inside.startsWith('..') || isAbsolute(inside)) return { kind: 'outside' };
  return { kind: 'file', path: inside.split(sep).join('/') };
};

const primitiveTriangles = (primitive, accessors) => {
  const mode = primitive.mode ?? 4;
  const accessor = primitive.indices !== undefined ? accessors[primitive.indices] : accessors[primitive.attributes?.POSITION];
  const count = Number.isInteger(accessor?.count) ? accessor.count : 0;
  if (mode === 4) return Math.floor(count / 3);
  if (mode === 5 || mode === 6) return Math.max(0, count - 2);
  return 0;
};

/* Triangles as rendered: every node that places a mesh, through the default scene. */
const renderedTriangles = (gltf) => {
  const accessors = Array.isArray(gltf.accessors) ? gltf.accessors : [];
  const meshes = Array.isArray(gltf.meshes) ? gltf.meshes : [];
  const nodes = Array.isArray(gltf.nodes) ? gltf.nodes : [];
  const perMesh = meshes.map((mesh) =>
    (Array.isArray(mesh?.primitives) ? mesh.primitives : []).reduce((sum, p) => sum + primitiveTriangles(p ?? {}, accessors), 0),
  );
  let roots;
  const scenes = Array.isArray(gltf.scenes) ? gltf.scenes : [];
  if (scenes.length > 0) {
    const scene = scenes[Number.isInteger(gltf.scene) ? gltf.scene : 0] ?? scenes[0];
    roots = Array.isArray(scene?.nodes) ? scene.nodes : [];
  } else if (nodes.length > 0) {
    const children = new Set(nodes.flatMap((node) => (Array.isArray(node?.children) ? node.children : [])));
    roots = nodes.map((_, i) => i).filter((i) => !children.has(i));
  } else {
    return perMesh.reduce((a, b) => a + b, 0);
  }
  let total = 0;
  const seen = new Set();
  const stack = [...roots];
  while (stack.length > 0) {
    const index = stack.pop();
    const node = nodes[index];
    if (!Number.isInteger(index) || seen.has(index) || !node) continue;
    seen.add(index);
    if (Number.isInteger(node.mesh) && perMesh[node.mesh] !== undefined) {
      const instancing = node.extensions?.EXT_mesh_gpu_instancing?.attributes ?? {};
      const counts = Object.values(instancing).map((a) => accessors[a]?.count).filter(Number.isInteger);
      total += perMesh[node.mesh] * (counts.length > 0 ? Math.max(...counts) : 1);
    }
    if (Array.isArray(node.children)) stack.push(...node.children);
  }
  return total;
};

const modelImages = new Set();

const checkModel = (model) => {
  let gltf;
  let bin = null;
  try {
    const data = readFileSync(model);
    if (model.toLowerCase().endsWith('.glb')) {
      ({ json: gltf, bin } = parseGlb(data));
    } else {
      try {
        gltf = JSON.parse(data.toString('utf8'));
      } catch (error) {
        throw new Unreadable(`not JSON (${clean(error.message)})`);
      }
    }
    if (!isObject(gltf) || !/^2\./.test(String(gltf.asset?.version ?? ''))) throw new Unreadable('not glTF 2.0 (asset.version)');

    // Bytes: the file, plus every buffer and image file it points at.
    let bytes = data.length;
    const counted = new Set();
    const buffers = [];
    for (const [i, buffer] of (Array.isArray(gltf.buffers) ? gltf.buffers : []).entries()) {
      if (buffer?.uri === undefined) {
        buffers[i] = i === 0 ? bin : null;
        continue;
      }
      const where = locate(model, String(buffer.uri));
      if (where.kind === 'data') buffers[i] = where.bytes;
      else if (where.kind === 'remote') warnings.push(`${model}: buffer ${i} is a remote file, not checked`);
      else if (where.kind === 'outside') throw new Unreadable(`buffer ${i} points outside the repository`);
      else if (!existsSync(where.path)) throw new Unreadable(`buffer ${i} points at ${where.path}, which does not exist`);
      else {
        buffers[i] = readFileSync(where.path);
        if (!counted.has(where.path)) bytes += buffers[i].length;
        counted.add(where.path);
      }
    }

    const images = Array.isArray(gltf.images) ? gltf.images : [];
    const views = Array.isArray(gltf.bufferViews) ? gltf.bufferViews : [];
    const external = [];
    for (const [i, image] of images.entries()) {
      const name = typeof image?.name === 'string' && image.name ? ` "${clean(image.name)}"` : '';
      const subject = `${model} image ${i}${name}`;
      if (Number.isInteger(image?.bufferView)) {
        const view = views[image.bufferView];
        const buffer = buffers[view?.buffer];
        const start = view?.byteOffset ?? 0;
        if (!view || !buffer || !Number.isInteger(view.byteLength) || start + view.byteLength > buffer.length) {
          if (view && buffers[view.buffer] === undefined && gltf.buffers?.[view.buffer]?.uri) continue; // remote, warned
          throw new Unreadable(`image ${i} points at bytes the model does not hold`);
        }
        checkImage(model, subject, buffer.subarray(start, start + view.byteLength));
      } else if (typeof image?.uri === 'string') {
        const where = locate(model, image.uri);
        if (where.kind === 'data') checkImage(model, subject, where.bytes);
        else if (where.kind === 'remote') warnings.push(`${subject} is a remote file, not checked`);
        else if (where.kind === 'outside') throw new Unreadable(`image ${i} points outside the repository`);
        else if (!existsSync(where.path)) throw new Unreadable(`image ${i} points at ${where.path}, which does not exist`);
        else external.push({ i, path: where.path, name });
      }
    }
    // An image file counts toward every model that uses it, and is checked once however many do.
    for (const { i, path, name } of external) {
      const content = readFileSync(path);
      if (!counted.has(path)) bytes += content.length;
      counted.add(path);
      if (!modelImages.has(path)) checkImage(path, `${path} (image ${i}${name} of ${model})`, content);
      modelImages.add(path);
    }

    measure(model, model, 'modelKB', bytes);
    measure(model, model, 'triangles', renderedTriangles(gltf));
    return images.length;
  } catch (error) {
    // A malformed file (a field of the wrong type included) is a finding about that file, not a crash.
    unreadable(model, clean(error instanceof Unreadable ? error.message : error.code ?? error.message));
    return 0;
  }
};

/* readFileSync, with a file that cannot be read reported as a finding. */
const readOrReport = (path) => {
  try {
    return readFileSync(path);
  } catch (error) {
    unreadable(path, clean(error.code ?? error.message));
    return null;
  }
};

// ── the scan ────────────────────────────────────────────────────────────────────────────────────

const walk = (dir, out) => {
  const entries = readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const entry of entries) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory()) {
      if (!SKIPPED_DIRS.has(entry.name)) walk(path, out);
    } else if (entry.isFile()) {
      out.add(path);
    }
  }
};

const files = new Set();
for (const root of config.roots) walk(root, files);
const inTextureDir = (path) => config.textureDirs.some((dir) => path === dir || path.startsWith(`${dir}/`));

const models = [];
const textures = [];
const environments = [];
for (const path of [...files].sort()) {
  const ext = extname(path).toLowerCase();
  if (MODEL_EXT.has(ext)) models.push(path);
  else if (GPU_TEXTURE_EXT.has(ext) || (IMAGE_EXT.has(ext) && inTextureDir(path))) textures.push(path);
  else if (ENVIRONMENT_EXT.has(ext)) environments.push(path);
}

let imagesInside = 0;
for (const model of models) imagesInside += checkModel(model);
let textureCount = 0;
for (const texture of textures) {
  if (modelImages.has(texture)) continue; // checked as part of the model that uses it
  textureCount += 1;
  const content = readOrReport(texture);
  if (content) checkImage(texture, texture, content);
}
for (const map of environments) {
  const content = readOrReport(map);
  if (content) measure(map, map, 'environmentKB', content.length);
}

for (const exception of config.exceptions.values()) {
  const what = `exception for ${exception.path} (${exception.budget})`;
  if (!existsSync(exception.path)) warnings.push(`${what} names a file that does not exist; remove it`);
  else if (!exception.used) warnings.push(`${what} does not apply to that file; remove it`);
  else if (exception.peak <= config.budgets[exception.budget]) warnings.push(`${what} is no longer needed: the file fits the budget`);
}

for (const finding of findings) console.log(`3D-BUDGET ${finding}`);
for (const warning of warnings) console.log(`3d-budget: warning: ${warning}`);
const inside = imagesInside > 0 ? ` (${plural(imagesInside, 'image')} inside)` : '';
console.log(
  `3d-budget: ${plural(models.length, 'model')}${inside}, ${plural(textureCount, 'texture')}, ` +
    `${plural(environments.length, 'environment map')} under ${config.roots.join(', ')}; ` +
    `${findings.length} over budget or unreadable`,
);
if (findings.length > 0) {
  console.log(`Budgets and exceptions: ${CONFIG}. Why they exist: ${RULES} § 5.`);
  if (!WARN_ONLY) process.exit(1);
}
