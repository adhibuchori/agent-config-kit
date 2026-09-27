#!/usr/bin/env python3
"""The engine behind agent-setup and agent-sync (agent-config-kit, the agent-core plugin).

    agent-setup questions --templates DIR --stack ID [--project DIR] [--json]
    agent-setup plan      --templates DIR --stack ID [--project DIR] [--answer ID=VALUE]... [--json]
    agent-setup apply     --templates DIR --stack ID [--project DIR] [--answer ID=VALUE]... --digest sha256:HEX
    agent-sync  check     --templates DIR --stack ID [--project DIR] [--json]
    agent-sync  plan      --templates DIR --stack ID [--project DIR] [--json]
    agent-sync  apply     --templates DIR --stack ID [--project DIR] --digest sha256:HEX
    agent-sync  own       --templates DIR --stack ID [--project DIR] [--undo] PATH...

--templates is a plugin's templates/ folder and --stack picks templates/<stack>/, which holds
_kit/setup.json. agent-core's own templates/common is found from this file's location and planned
first while the project's lock has no agent-core entry.

What it writes: template files, created only where nothing exists (O_CREAT|O_EXCL), unchanged;
four managed merges into files that may exist (.claude/settings.json additively, one block in
.gitignore, one block in CLAUDE.md, missing package.json scripts); and, last, the lock
.claude/agent-config-kit.lock, whose presence turns the kit's hooks on. It never deletes a file,
never rewrites one it did not write (a template file is replaced only while its bytes still equal
what the lock recorded), never writes under .git/, and opens no network connection. `apply` writes
only when the plan it recomputes has the digest the user approved. A template that still calls
this repository's reusable workflows at the release placeholder (@ and forty zeros) is held back,
not installed: it would fail in every pull request until a release pins a real commit.

Exit codes: 0 ok or in sync; 1 drift; 4 double wiring; 5 both; 2 usage or I/O error;
3 refused (digest mismatch, a path that appeared or escapes the project, a conflicting plugin).
Standard library only; python3 3.8 or newer; run as `python3 -I`.
"""
import argparse
import copy
import hashlib
import json
import os
import re
import stat
import subprocess
import sys

KIT = "agent-config-kit"
CORE = "agent-core"
LOCK = ".claude/agent-config-kit.lock"
SETTINGS = ".claude/settings.json"
LOCAL_SETTINGS = ".claude/settings.local.json"
CONFIG = ".claude/agent-config.json"
LOCK_NOTE = ("Written by agent-setup (agent-config-kit). Do not edit: agent-sync check compares the project with it, "
             "and while it exists the kit's hooks run in this project.")
SETTINGS_KEYS = {"$schema", "permissions", "sandbox", "env", "extraKnownMarketplaces", "enabledPlugins"}
SETUP_KEYS = {"stack", "conflictsWith", "questions", "seed", "snippets", "gitignore", "packageScripts"}
QUESTION_KEYS = {"id", "ask", "why", "choices", "recommended", "detect", "install", "settings"}
GI_START = "# >>> agent-config-kit (managed by /agent-core:setup and sync; edit outside this block)"
GI_END = "# <<< agent-config-kit"
MD_START = "<!-- >>> agent-config-kit: managed by /agent-core:setup and sync; edit outside this block -->"
MD_END = "<!-- <<< agent-config-kit -->"
MD_HEADING = "## Agent config kit"
MD_SECTION = re.compile(r"<!-- agent-config-kit/([a-z0-9][a-z0-9-]*) -->")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
# Kinds a draft prints, in this order; within a kind, by path.
ORDER = ["create", "replace", "mode", "same", "seed", "keep", "modified", "drop", "merge", "conflict", "block",
         "alias", "by-hand", "note", "warn", "lock"]
DRIFT = {"missing", "modified", "mode", "stale", "new", "removed-upstream", "settings-missing", "block-modified",
         "block-stale", "block-missing", "alias-missing", "version", "no-lock"}
CODE_EXEC = 0o755
CODE_PLAIN = 0o644
# A `uses:` pinned to the all-zero placeholder a caller template carries until the release that
# replaces it (RELEASING.md, "Update the callers").
PLACEHOLDER_PIN = re.compile(rb"^\s*(?:-\s+)?uses:\s*\S+@0{40}(?![0-9A-Fa-f])", re.M)


class Usage(Exception):
    """Bad flags, unreadable templates or a malformed setup.json: exit 2."""


class Refused(Exception):
    """The project changed since the draft, a path escapes it, or a plugin conflicts: exit 3."""


# ── small helpers ────────────────────────────────────────────────────────────────────────────────

def sha(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return "sha256:" + hashlib.sha256(data).hexdigest()


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def inside(path, root):
    return path == root or path.startswith(root.rstrip(os.sep) + os.sep)


def esc(key):
    return key.replace("~", "~0").replace("/", "~1")


def unesc(key):
    return key.replace("~1", "/").replace("~0", "~")


def dotted(pointer):
    return ".".join(unesc(k) for k in pointer.split("/")[1:]) or "(root)"


def glob_re(pattern):
    """A destination glob: `*` within one folder, `**` across folders, `?` one character."""
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        else:
            c = pattern[i]
            out.append("[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c))
            i += 1
    return re.compile("".join(out) + r"\Z")


def matches(globs, path):
    return any(glob_re(g).match(path) for g in globs)


def read_json(path, what):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise Usage(f"{what} not found: {path}")
    except (OSError, ValueError) as err:
        raise Usage(f"{what} is not readable JSON: {path} ({err})")


def leaves(obj, pointer=""):
    """Every leaf of a JSON value: (pointer, "item", x) for each array item, (pointer, "value", v) otherwise."""
    if isinstance(obj, dict) and obj:
        for key, value in obj.items():
            yield from leaves(value, pointer + "/" + esc(key))
    elif isinstance(obj, list) and obj:
        for item in obj:
            yield (pointer, "item", item)
    elif pointer:
        yield (pointer, "value", obj)


def build(entries):
    """The JSON object holding exactly these leaves, in their order."""
    root = {}
    for pointer, kind, value in entries:
        keys = [unesc(k) for k in pointer.split("/")[1:]]
        node = root
        for key in keys[:-1]:
            node = node.setdefault(key, {})
        if kind == "item":
            node.setdefault(keys[-1], []).append(copy.deepcopy(value))
        else:
            node[keys[-1]] = copy.deepcopy(value)
    return root


def lookup(obj, pointer):
    node = obj
    for key in pointer.split("/")[1:]:
        if not isinstance(node, dict) or unesc(key) not in node:
            return None, False
        node = node[unesc(key)]
    return node, True


def has_leaf(obj, pointer, kind, value):
    node, found = lookup(obj, pointer)
    if not found:
        return False
    if kind == "item":
        return isinstance(node, list) and canon(value) in {canon(x) for x in node}
    return canon(node) == canon(value)


def lock_entries(recorded):
    """The lock's `settings` map back into leaves."""
    out = []
    for pointer in sorted(recorded or {}):
        value = recorded[pointer]
        if isinstance(value, list):
            out += [(pointer, "item", v) for v in value]
        else:
            out.append((pointer, "value", value))
    return out


def record_entries(entries):
    out = {}
    for pointer, kind, value in entries:
        if kind == "item":
            out.setdefault(pointer, [])
            if canon(value) not in {canon(x) for x in out[pointer]}:
                out[pointer].append(value)
        else:
            out[pointer] = value
    return out


def lock_problems(lock):
    """Why a parsed lock is not one this engine wrote: [] when every field has the shape it writes."""
    def strings(v):
        return isinstance(v, list) and all(isinstance(x, str) for x in v)

    def string_map(v):
        return isinstance(v, dict) and all(isinstance(k, str) and isinstance(x, str) for k, x in v.items())

    out = []
    if not isinstance(lock.get("blocks", {}), dict) or not string_map(lock.get("blocks", {})):
        out.append("blocks is not a map of file to digest")
    for name, entry in lock["plugins"].items():
        if not NAME.match(name):
            out.append(f"plugins has a malformed name {name!r}")
            continue
        if not isinstance(entry, dict):
            out.append(f"plugins.{name} is not an object")
            continue
        for key in ("files", "packageScripts", "answers"):
            if key in entry and not string_map(entry[key]):
                out.append(f"plugins.{name}.{key} is not a map of strings")
        for key in ("kept", "seeded", "owned", "gitignore"):
            if key in entry and not strings(entry[key]):
                out.append(f"plugins.{name}.{key} is not a list of strings")
        if "settings" in entry and (not isinstance(entry["settings"], dict)
                                    or not all(isinstance(k, str) and k.startswith("/") for k in entry["settings"])):
            out.append(f"plugins.{name}.settings is not a map of JSON Pointers")
        for key in ("version", "stack", "claudeMd"):
            if key in entry and not isinstance(entry[key], str):
                out.append(f"plugins.{name}.{key} is not a string")
    return out


# ── a plugin's templates ─────────────────────────────────────────────────────────────────────────

class Template:
    def __init__(self, src, rel):
        self.src = src
        self.rel = rel  # path under templates/<stack>/
        with open(src, "rb") as fh:
            self.data = fh.read()
        self.sha = sha(self.data)
        self.exec = bool(os.stat(src).st_mode & 0o111)
        self.mode = CODE_EXEC if self.exec else CODE_PLAIN
        self.placeholder = bool(PLACEHOLDER_PIN.search(self.data))


class Layer:
    """One plugin's templates/<stack>/: its manifest, its setup.json and its files."""

    def __init__(self, templates, stack):
        self.templates = os.path.realpath(templates)
        if not NAME.match(stack or ""):
            raise Usage(f"--stack {stack!r} is not a stack id")
        self.stack = stack
        self.dir = os.path.join(self.templates, stack)
        if not os.path.isdir(self.dir):
            raise Usage(f"no templates for stack {stack!r}: {self.dir} is not a folder")
        self.root = os.path.dirname(self.templates)
        manifest = read_json(os.path.join(self.root, ".claude-plugin", "plugin.json"), "plugin.json")
        self.name, self.version = manifest.get("name"), manifest.get("version")
        if not isinstance(self.name, str) or not NAME.match(self.name) or not isinstance(self.version, str):
            raise Usage(f"{self.root}/.claude-plugin/plugin.json has no usable name and version")
        hooks = os.path.join(self.root, "hooks", "hooks.json")
        self.hooks = hooks if os.path.isfile(hooks) else None
        self.cfg = self._setup_json()
        self.fragment = self._read_kit("claude-md.md")
        self.files, self.starters = self._walk()
        self.settings = self._settings_template()

    def _read_kit(self, name):
        path = os.path.join(self.dir, "_kit", name)
        if not os.path.isfile(path):
            return ""
        with open(path, encoding="utf-8") as fh:
            return fh.read()

    def _setup_json(self):
        cfg = read_json(os.path.join(self.dir, "_kit", "setup.json"), f"{self.name} _kit/setup.json")
        where = f"{self.name} templates/{self.stack}/_kit/setup.json"
        if not isinstance(cfg, dict):
            raise Usage(f"{where}: not a JSON object")
        unknown = sorted(k for k in cfg if k not in SETUP_KEYS and not k.startswith("//"))
        if unknown:
            raise Usage(f"{where}: unknown keys {', '.join(unknown)}")
        if cfg.get("stack") != self.stack:
            raise Usage(f"{where}: \"stack\" is {cfg.get('stack')!r}, not {self.stack!r}")
        cfg.setdefault("conflictsWith", [])
        cfg.setdefault("questions", [])
        cfg.setdefault("seed", [])
        cfg.setdefault("snippets", {})
        cfg.setdefault("gitignore", [])
        cfg.setdefault("packageScripts", {})
        for key in ("conflictsWith", "seed", "gitignore"):
            if not isinstance(cfg[key], list) or not all(isinstance(x, str) and x for x in cfg[key]):
                raise Usage(f"{where}: {key} must be a list of strings")
        for key in ("snippets", "packageScripts"):
            if not isinstance(cfg[key], dict) or not all(isinstance(v, str) for v in cfg[key].values()):
                raise Usage(f"{where}: {key} must map names to strings")
        if self.name != CORE and "unlock" in cfg["packageScripts"]:
            raise Usage(f"{where}: only agent-core declares the unlock script")
        ids = set()
        if not isinstance(cfg["questions"], list):
            raise Usage(f"{where}: questions must be a list")
        for q in cfg["questions"]:
            if not isinstance(q, dict):
                raise Usage(f"{where}: a question is not an object")
            bad = sorted(k for k in q if k not in QUESTION_KEYS and not k.startswith("//"))
            if bad:
                raise Usage(f"{where}: question {q.get('id')!r} has unknown keys {', '.join(bad)}")
            qid, choices = q.get("id"), q.get("choices")
            if not isinstance(qid, str) or not NAME.match(qid) or qid in ids:
                raise Usage(f"{where}: question id {qid!r} is missing, malformed or repeated")
            ids.add(qid)
            if (not isinstance(choices, list) or len(choices) < 2
                    or not all(isinstance(c, str) and c for c in choices) or len(set(choices)) != len(choices)):
                raise Usage(f"{where}: question {qid} needs two or more distinct choices")
            if q.get("recommended") not in choices:
                raise Usage(f"{where}: question {qid} recommends a value outside its choices")
            for key in ("ask", "why", "detect"):
                if not isinstance(q.get(key, ""), str) or (key != "detect" and not q.get(key)):
                    raise Usage(f"{where}: question {qid} needs a text {key}")
            for key in ("install", "settings"):
                gate = q.get(key, {})
                if not isinstance(gate, dict) or not set(gate) <= set(choices):
                    raise Usage(f"{where}: question {qid} {key} is keyed by something other than its choices")
            for globs in q.get("install", {}).values():
                if not isinstance(globs, list) or not all(isinstance(g, str) and g for g in globs):
                    raise Usage(f"{where}: question {qid} install lists must hold globs")
            for gates in q.get("settings", {}).values():
                if not isinstance(gates, dict) or not all(p.startswith("/") and (v is True or isinstance(v, list))
                                                          for p, v in gates.items()):
                    raise Usage(f"{where}: question {qid} settings gates map a JSON Pointer to true or a list")
        for target, snippet in cfg["snippets"].items():
            if not os.path.isfile(os.path.join(self.dir, "_kit", snippet)):
                raise Usage(f"{where}: snippet {snippet} for {target} is missing")
        return cfg

    def _walk(self):
        files, starters, problems = {}, {}, []
        for folder, dirs, names in os.walk(self.dir):
            rel_folder = os.path.relpath(folder, self.dir)
            if rel_folder == ".":
                dirs[:] = [d for d in dirs if d != "_kit"]
            for d in list(dirs):
                if os.path.islink(os.path.join(folder, d)):
                    problems.append(f"{os.path.normpath(os.path.join(rel_folder, d))} is a symlink")
                    dirs.remove(d)
            dirs.sort()
            for n in sorted(names):
                src = os.path.join(folder, n)
                rel = os.path.normpath(os.path.join(rel_folder, n)).replace(os.sep, "/")
                if os.path.islink(src):
                    problems.append(f"{rel} is a symlink")
                    continue
                dest = rel[: -len(".starter")] if rel.endswith(".starter") else rel
                why = forbidden(dest, rel)
                if why:
                    problems.append(f"{rel}: {why}")
                    continue
                if dest in files or dest in starters:
                    problems.append(f"{rel}: two templates land on {dest}")
                    continue
                (starters if rel.endswith(".starter") else files)[dest] = Template(src, rel)
        if problems:
            raise Usage(f"{self.name} templates/{self.stack} cannot be installed: " + "; ".join(problems))
        return files, starters

    def _settings_template(self):
        t = self.files.pop(SETTINGS, None)
        if t is None:
            return None
        try:
            data = json.loads(t.data.decode("utf-8"))
        except ValueError as err:
            raise Usage(f"{self.name} templates/{self.stack}/{SETTINGS} is not JSON ({err})")
        if not isinstance(data, dict):
            raise Usage(f"{self.name} templates/{self.stack}/{SETTINGS} is not a JSON object")
        bad = sorted(set(data) - SETTINGS_KEYS)
        if bad:
            raise Usage(f"{self.name} templates/{self.stack}/{SETTINGS} may not hold {', '.join(bad)}"
                        " (hooks belong to the plugin's hooks/hooks.json)")
        all_leaves = list(leaves(data))
        for q in self.cfg["questions"]:
            for gates in q.get("settings", {}).values():
                for pointer, value in gates.items():
                    if value is True:
                        found = any(p == pointer or p.startswith(pointer + "/") for p, _, _ in all_leaves)
                    else:
                        found = all(any(p == pointer and k == "item" and canon(x) == canon(v) for p, k, x in all_leaves)
                                    for v in value)
                    if not found:
                        raise Usage(f"{self.name} setup.json question {q['id']} gates {pointer}, which the settings "
                                    "template does not hold")
        return data

    # What one set of answers installs.
    def answers(self, given, strict=True):
        out = {}
        for q in self.cfg["questions"]:
            value = given.get(q["id"])
            if value is None or value not in q["choices"]:
                if value is not None and strict:
                    raise Usage(f"--answer {q['id']}={value}: choose one of {', '.join(q['choices'])}")
                value = q["recommended"]
            out[q["id"]] = value
        return out

    def installs(self, dest, answers):
        for q in self.cfg["questions"]:
            gate = q.get("install", {})
            gated = [g for globs in gate.values() for g in globs]
            if gated and matches(gated, dest) and not matches(gate.get(answers[q["id"]], []), dest):
                return False
        return True

    def expected(self, answers):
        return {d: t for d, t in self.files.items() if self.installs(d, answers)}

    def is_seed(self, dest):
        return matches(self.cfg["seed"], dest)

    def settings_entries(self, answers):
        """The settings template's leaves these answers install: a leaf a question's settings gate
        names is installed only for the choices that list it; every other leaf always is."""
        if self.settings is None:
            return []
        out = []
        for pointer, kind, value in leaves(self.settings):
            keep = True
            for q in self.cfg["questions"]:
                naming = [choice for choice, gates in q.get("settings", {}).items()
                          if any(gate_hit(pointer, kind, value, gp, gv) for gp, gv in gates.items())]
                if naming and answers[q["id"]] not in naming:
                    keep = False
            if keep:
                out.append((pointer, kind, value))
        return out


def gate_hit(pointer, kind, value, gate, gated):
    """Whether a settings gate covers one leaf: true covers the subtree at the gate's pointer, a
    list covers those items of the array there."""
    if gated is True:
        return pointer == gate or pointer.startswith(gate + "/")
    return pointer == gate and kind == "item" and canon(value) in {canon(x) for x in gated}


def forbidden(dest, rel):
    parts = dest.split("/")
    base = parts[-1]
    if parts[0] == ".git":
        return "nothing is ever written under .git/"
    if base == ".gitignore":
        return "a .gitignore template would ignore files in the kit itself; lines go in _kit/setup.json"
    if dest == "package.json":
        return "package.json is never installed; scripts go in packageScripts"
    if dest.startswith((".claude/hooks/", ".claude/commands/", ".claude/agents/", ".claude/skills/")):
        return "hooks, commands, agents and skills are plugin components, never project files"
    if dest in ("CLAUDE.md", "AGENTS.md") and not rel.endswith(".starter"):
        return "ship it as a .starter so it never loads as instructions inside the kit"
    if re.match(r"\.env(rc)?([._-]|$)", base) and not base.endswith(".example"):
        return "a real .env file"
    return ""


# ── the project ──────────────────────────────────────────────────────────────────────────────────

def git_toplevel(cwd):
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                           timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


class State:
    """One destination in the project: absent, a symlink, a folder, or a file with its hash and mode."""

    def __init__(self, root, rel):
        self.path = os.path.join(root, rel)
        self.exists = os.path.lexists(self.path)
        self.link = os.path.islink(self.path)
        self.file = self.exists and not self.link and os.path.isfile(self.path)
        self.data = b""
        self.sha = ""
        self.exec = False
        if self.file:
            with open(self.path, "rb") as fh:
                self.data = fh.read()
            self.sha = sha(self.data)
            self.exec = bool(os.stat(self.path).st_mode & 0o100)

    def text(self):
        return self.data.decode("utf-8", "surrogateescape")


class Draft:
    def __init__(self):
        self.actions = []  # (kind, path, detail, digest part)
        self.findings = []  # (kind, path, detail)
        self.writes = []  # ordered write operations, the lock last

    def act(self, kind, path, detail="", part=""):
        self.actions.append((kind, path, detail, part))

    def find(self, kind, path, detail=""):
        self.findings.append((kind, path, detail))


class Engine:
    def __init__(self, tool, args):
        self.tool = tool
        self.args = args
        self.here = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
        self.target = Layer(args.templates, args.stack)
        if self.target.name == CORE:
            self.core = self.target
        else:
            self.core = Layer(os.path.join(self.here, "templates"), "common")
            if self.core.name != CORE:
                raise Usage(f"{self.here} is not agent-core, so the core layer cannot be found")
        self.project = self._project(args.project)
        self.lock = self._read_lock()
        self.cwd = os.getcwd()

    def _project(self, given):
        path = given or git_toplevel(os.getcwd()) or os.getcwd()
        if not os.path.isdir(path):
            raise Usage(f"--project {path}: not a folder")
        real = os.path.realpath(path)
        for layer in sorted({self.target.root, self.core.root}):
            plugins = os.path.dirname(layer)
            kit_repo = (os.path.basename(plugins) == "plugins"
                        and os.path.isfile(os.path.join(os.path.dirname(plugins), ".claude-plugin", "marketplace.json")))
            if inside(real, layer) or (kit_repo and (inside(real, plugins) or real == os.path.dirname(plugins))):
                raise Refused(f"{real} is a plugin or the kit repository ({layer}); run setup in your own project")
        return real

    def _read_lock(self):
        path = os.path.join(self.project, LOCK)
        if not os.path.lexists(path):
            return None
        if os.path.islink(path):
            raise Usage(f"{LOCK} is a symlink; the engine reads and writes only a plain lock file")
        data = read_json(path, LOCK)
        if not isinstance(data, dict) or not isinstance(data.get("plugins"), dict):
            raise Usage(f"{LOCK} is not a lock this engine wrote (no plugins map); move it aside and run setup again")
        problems = lock_problems(data)
        if problems:
            raise Usage(f"{LOCK} is malformed ({'; '.join(problems[:3])}); it was edited by hand or by another "
                        "tool: restore it from git, or move it aside and run setup again")
        return data

    def display(self):
        rel = os.path.relpath(self.project, self.cwd)
        return rel if not rel.startswith("..") else self.project

    def locked(self, name):
        return (self.lock or {}).get("plugins", {}).get(name)

    def layers(self):
        return [self.core] if self.target is self.core else [self.core, self.target]

    # ── safety ──

    def dest(self, rel):
        """The absolute path of a project-relative destination, refused when it could land outside."""
        parts = rel.split("/")
        if rel.startswith("/") or ".." in parts or "" in parts or parts[0] == ".git":
            raise Refused(f"{rel}: not a plain path inside the project")
        full = os.path.join(self.project, *parts)
        probe = os.path.dirname(full)
        while not os.path.lexists(probe):
            probe = os.path.dirname(probe)
        if not inside(os.path.realpath(probe), self.project):
            raise Refused(f"{rel}: its folder resolves outside the project")
        real_parts = os.path.relpath(os.path.realpath(probe), self.project).split(os.sep)
        if real_parts[0] == ".git":
            raise Refused(f"{rel}: its folder resolves under .git/")
        return full

    # ── planning ──

    def plan(self, layers, given, fresh):
        """The draft for these layers: what exists, what would be written, and what drifted."""
        draft = Draft()
        lock = copy.deepcopy(self.lock) if self.lock else {"plugins": {}}
        lock["//"] = LOCK_NOTE
        lock["kit"] = KIT
        lock["lockVersion"] = 1
        lock.setdefault("blocks", {})
        answers = {}
        for layer in layers:
            prior = self.locked(layer.name) or {}
            if fresh:
                answers[layer.name] = layer.answers(given)
            else:
                answers[layer.name] = layer.answers(prior.get("answers") or {}, strict=False)
        entries = {}
        for layer in layers:
            prior = copy.deepcopy(self.locked(layer.name) or {})
            if not fresh and self.locked(layer.name) and prior.get("version") != layer.version:
                draft.find("version", LOCK, f"{layer.name}: set up with {prior.get('version')}, {layer.version} installed")
            entries[layer.name] = self._files(draft, layer, prior, answers[layer.name], fresh)
        self._settings(draft, layers, answers, entries, fresh)
        self._gitignore(draft, layers, lock, entries, fresh)
        self._claude_md(draft, layers, lock, entries, fresh)
        self._aliases(draft, layers, entries, fresh)
        for layer in layers:
            for target in sorted(layer.cfg["snippets"]):
                snippet = os.path.join(layer.dir, "_kit", layer.cfg["snippets"][target])
                with open(snippet, "rb") as fh:
                    part = sha(fh.read())
                draft.act("by-hand", target, f"add what {snippet} holds; the engine does not merge this format", part)
        for kind, path, detail in self.double_wiring(layers):
            draft.act("warn", path, detail)
            draft.find(kind, path, detail)
        for layer in layers:
            entry = entries[layer.name]
            entry["answers"] = answers[layer.name]
            entry["stack"] = layer.stack
            entry["version"] = layer.version
            for key in ("kept", "owned", "seeded"):
                entry[key] = sorted(set(entry.get(key, [])))
            # In the plugin's own order: a later setup rebuilds the block from these lines, and
            # must write them exactly as this plugin's setup.json does.
            entry["gitignore"] = list(dict.fromkeys(layer.cfg["gitignore"]))
            if layer.fragment.strip():
                entry["claudeMd"] = sha(layer.fragment)
            else:
                entry.pop("claudeMd", None)
            lock["plugins"][layer.name] = entry
        text = json.dumps(lock, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        old = None
        if self.lock is not None:
            old = json.dumps(self.lock, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        if text != old:
            draft.act("lock", LOCK, "written last; turns the hooks on" if fresh else "updated last", sha(text))
            draft.writes.append(("lock", LOCK, text.encode("utf-8"), None))
        return draft

    def _files(self, draft, layer, prior, answers, fresh):
        files = dict(prior.get("files") or {})
        kept, seeded, owned = set(prior.get("kept") or []), set(prior.get("seeded") or []), set(prior.get("owned") or [])
        expected = layer.expected(answers)
        # A starter (CLAUDE.md.starter aside, which the CLAUDE.md block uses) installs once, then is the project's.
        for dest, t in layer.starters.items():
            if dest != "CLAUDE.md":
                expected[dest] = t
        # A caller still pinned to the release placeholder is held back: installed, it would fail every
        # pull request. It is neither written nor recorded, so a later release that pins a real commit
        # installs it through sync as a new file. One the lock already records is left as it is.
        for dest in sorted(d for d, t in expected.items() if t.placeholder and d not in files and d not in seeded):
            del expected[dest]
            draft.act("warn", dest, f"not installed: {layer.name} {layer.version} still pins the kit's reusable "
                                    "workflow to the release placeholder @000…0; a later release pins a real "
                                    "commit, and sync installs it then")
            draft.find("held", dest, "the release placeholder pin; installed by a later release")
        for dest in sorted(set(expected) | set(files)):
            t = expected.get(dest)
            cur = State(self.project, dest)
            if dest in owned:
                draft.find("owned", dest, "yours (agent-sync own); not compared")
                continue
            if t is None:
                draft.find("removed-upstream", dest, f"{layer.name} {layer.version} no longer ships it")
                draft.act("drop", dest, "no longer shipped: left in place, dropped from the lock", cur.sha)
                files.pop(dest, None)
                continue
            seed = layer.is_seed(dest) or dest in layer.starters
            if dest in seeded:
                draft.find("seeded", dest, "created once; the project's own")
                continue
            if seed and dest not in files:
                if cur.exists and dest in kept:
                    draft.find("kept", dest, "existed before setup; left alone")
                    continue
                if not fresh:
                    draft.find("new", dest, "kept at setup and now gone; sync seeds the template's" if dest in kept
                               else f"{layer.name} {layer.version} ships it (seeded: created once)")
                if not cur.exists:
                    self.dest(dest)
                    draft.act("seed", dest, "(created once; yours from then on)", t.sha)
                    draft.writes.append(("create", dest, t.data, t.mode))
                    seeded.add(dest)
                    kept.discard(dest)
                else:
                    draft.act("keep", dest, f"(exists; left alone; compare with {layer.name} templates/{layer.stack}/{t.rel})",
                              cur.sha)
                    kept.add(dest)
                continue
            if dest in files:
                recorded = files[dest]
                if not cur.exists:
                    draft.find("missing", dest, "setup wrote it; it is gone")
                    self.dest(dest)
                    draft.act("create", dest, "(missing; restored from the template)", t.sha)
                    draft.writes.append(("create", dest, t.data, t.mode))
                    files[dest] = t.sha
                elif not cur.file:
                    draft.find("modified", dest, "is no longer a plain file")
                    draft.act("modified", dest, "(no longer a plain file; left alone)", "link" if cur.link else "dir")
                elif cur.sha == recorded and t.sha != recorded:
                    draft.find("stale", dest, f"{layer.name} {layer.version} changed it; your copy still matches the lock")
                    self.dest(dest)
                    draft.act("replace", dest, "(template changed; your copy is what setup wrote)", cur.sha + t.sha)
                    draft.writes.append(("replace", dest, t.data, t.mode, cur.sha))
                    files[dest] = t.sha
                elif cur.sha == recorded:
                    if t.exec and not cur.exec:
                        draft.find("mode", dest, "lost its exec bit")
                        draft.act("mode", dest, "(restore the exec bit)", cur.sha)
                        draft.writes.append(("chmod", dest, None, t.mode))
                elif cur.sha == t.sha:
                    draft.find("stale", dest, "already holds the template's new bytes; the lock is behind")
                    draft.act("same", dest, "(already the template's bytes; the lock follows)", cur.sha)
                    files[dest] = t.sha
                else:
                    draft.find("modified", dest, "differs from what setup wrote")
                    draft.act("modified", dest, f"(yours differs; keep it: agent-sync own {dest}; take the kit's: "
                                                "delete it, then sync again)", cur.sha)
                continue
            # A template file the lock does not manage: a first setup, a new file, or one kept before.
            if not fresh and dest not in kept:
                draft.find("new", dest, f"{layer.name} {layer.version} ships it")
            elif not fresh and not cur.exists:
                draft.find("new", dest, "kept at setup and now gone; sync installs the template's")
            if not cur.exists:
                self.dest(dest)
                draft.act("create", dest, "", t.sha)
                draft.writes.append(("create", dest, t.data, t.mode))
                files[dest] = t.sha
                kept.discard(dest)
            elif cur.file and cur.sha == t.sha:
                draft.act("same", dest, "(already identical; managed)", cur.sha)
                files[dest] = t.sha
                kept.discard(dest)
            elif dest in kept:
                draft.find("kept", dest, "existed before setup; left alone")
            else:
                draft.act("keep", dest, f"(exists; left alone; compare with {layer.name} templates/{layer.stack}/{t.rel})",
                          cur.sha)
                kept.add(dest)
        return {"files": files, "kept": sorted(kept), "seeded": sorted(seeded), "owned": sorted(owned),
                "packageScripts": dict(prior.get("packageScripts") or {}), "settings": {}}

    def _settings(self, draft, layers, answers, entries, fresh):
        parts = [(layer, layer.settings_entries(answers[layer.name])) for layer in layers if layer.settings is not None]
        if not parts:
            return
        cur = State(self.project, SETTINGS)
        user, broken = {}, ""
        if cur.link or (cur.exists and not cur.file):
            broken = "is not a plain file"
        elif cur.file:
            try:
                user = json.loads(cur.text())
            except ValueError:
                broken = "is not valid JSON"
            if not broken and not isinstance(user, dict):
                broken = "is not a JSON object"
        if broken:
            wanted = [(p, k, v) for _, es in parts for p, k, v in es]
            if not fresh:
                draft.find("settings-missing", SETTINGS, f"{broken}, so no entry can be checked")
            draft.act("conflict", SETTINGS, f"{broken}: nothing written; add by hand: {canon(build(wanted))}", cur.sha)
            return
        before = copy.deepcopy(user)
        added_all = []
        for layer, es in parts:
            prior = self.locked(layer.name) or {}
            if not fresh:
                # What the lock recorded, plus what this version adds; a scalar the user set
                # differently is information (kept), never drift.
                want = lock_entries(prior.get("settings")) + es
                seen = set()
                for pointer, kind, value in want:
                    key = (pointer, kind, canon(value))
                    if key in seen:
                        continue
                    seen.add(key)
                    node, found = lookup(before, pointer)
                    if kind == "value" and found and canon(node) != canon(value):
                        draft.find("kept", SETTINGS, f"{pointer} yours: {canon(node)}, kit: {canon(value)}")
                    elif not has_leaf(before, pointer, kind, value):
                        draft.find("settings-missing", SETTINGS, f"{pointer} {canon(value)}")
            recorded, conflicts = [], []
            for pointer, kind, value in es:
                node, found = lookup(user, pointer)
                if kind == "item":
                    if found and not isinstance(node, list):
                        conflicts.append((pointer, node, [value]))
                        continue
                    if not has_leaf(user, pointer, kind, value):
                        if not self._place(user, pointer, kind, value, conflicts):
                            continue
                        added_all.append((pointer, kind))
                    recorded.append((pointer, kind, value))
                else:
                    if found and canon(node) != canon(value):
                        conflicts.append((pointer, node, value))
                        continue
                    if not found:
                        if not self._place(user, pointer, kind, value, conflicts):
                            continue
                        added_all.append((pointer, kind))
                    recorded.append((pointer, kind, value))
            shown = set()
            for pointer, yours, kit in conflicts:
                if pointer in shown:
                    continue
                shown.add(pointer)
                draft.act("conflict", f"{SETTINGS} {pointer}", f"yours: {canon(yours)}, kit: {canon(kit)} (kept yours)")
            entries[layer.name]["settings"] = record_entries(recorded)
        if not added_all:
            return
        counts = {}
        for pointer, kind in added_all:
            key = "/".join(pointer.split("/")[:3])
            n, _ = counts.get(key, (0, kind))
            counts[key] = (n + 1, kind if n == 0 else "item")
        summary = ", ".join(f"+{n} {dotted(p)}" if n > 1 or k == "item" else f"+{dotted(p)}"
                            for p, (n, k) in counts.items())
        text = json.dumps(user, indent=2, ensure_ascii=False) + "\n"
        self.dest(SETTINGS)
        if cur.exists:
            draft.act("merge", SETTINGS, summary, cur.sha + sha(text))
            draft.writes.append(("rewrite", SETTINGS, text.encode("utf-8"), None, cur.sha))
        else:
            draft.act("create", SETTINGS, summary, sha(text))
            draft.writes.append(("create", SETTINGS, text.encode("utf-8"), CODE_PLAIN))

    @staticmethod
    def _place(user, pointer, kind, value, conflicts):
        """Add one leaf; a scalar standing where an object must go is a conflict, left as it is."""
        keys = [unesc(k) for k in pointer.split("/")[1:]]
        node, walked = user, ""
        for key in keys[:-1]:
            walked += "/" + esc(key)
            if key not in node:
                node[key] = {}
            elif not isinstance(node[key], dict):
                conflicts.append((walked, node[key], "an object"))
                return False
            node = node[key]
        if kind == "item":
            node.setdefault(keys[-1], []).append(copy.deepcopy(value))
        else:
            node[keys[-1]] = copy.deepcopy(value)
        return True

    # ── managed blocks ──

    @staticmethod
    def _span(lines, start, end):
        """("absent" | "ok" | "bad", (i, j)): the one block, its start and end line indexes."""
        # A trailing \r (an editor that rewrote the file with CRLF endings) still marks the block,
        # so the block is never appended a second time; its bytes then differ, which is a conflict.
        s = [i for i, line in enumerate(lines) if line.rstrip("\r") == start]
        e = [i for i, line in enumerate(lines) if line.rstrip("\r") == end]
        if not s and not e:
            return "absent", None
        if len(s) == 1 and len(e) == 1 and s[0] < e[0]:
            return "ok", (s[0], e[0])
        return "bad", None

    def _block(self, draft, rel, start, end, render, record, label, create_text=None, fresh=False):
        """Create, replace or append one managed block. render(current_block_or_None) -> new block text."""
        cur = State(self.project, rel)
        recorded = (self.lock or {}).get("blocks", {}).get(rel)
        if cur.link or (cur.exists and not cur.file):
            draft.act("conflict", rel, "is not a plain file; the block was not written", cur.sha)
            return
        if not cur.exists:
            new = render(None)
            if new is None:
                return
            if recorded and not fresh:
                draft.find("block-missing", rel, "the file is gone")
            text = (create_text + "\n" + new) if create_text else new
            self.dest(rel)
            draft.act("block", rel, f"{label} (new file)" + (" from the starter" if create_text else ""), sha(text))
            draft.writes.append(("create", rel, text.encode("utf-8"), CODE_PLAIN))
            record(sha(new), bool(create_text))
            return
        text = cur.text()
        lines = text.split("\n")
        state, span = self._span(lines, start, end)
        if state == "bad":
            draft.find("block-modified", rel, "its markers are repeated or out of order")
            draft.act("conflict", rel, "block markers repeated or out of order: left alone; fix them by hand", cur.sha)
            return
        if state == "absent":
            new = render(None)
            if new is None:
                return
            if recorded:
                draft.find("block-missing", rel, "the agent-config-kit block is gone")
            joined = text if text.endswith("\n") or not text else text + "\n"
            joined = (joined + "\n" if joined else "") + new
            self.dest(rel)
            draft.act("block", rel, f"{label} (appended)", cur.sha + sha(joined))
            draft.writes.append(("rewrite", rel, joined.encode("utf-8"), None, cur.sha))
            record(sha(new), False)
            return
        i, j = span
        block = "\n".join(lines[i:j + 1]) + "\n"
        if recorded and sha(block) != recorded:
            draft.find("block-modified", rel, "the agent-config-kit block was edited by hand")
            draft.act("conflict", rel, "the agent-config-kit block was edited by hand: left alone; move your lines "
                                       "outside it and delete the block, then sync again", cur.sha)
            record(recorded, False)
            return
        new = render(block)
        if new is None or new == block:
            record(sha(block), False)
            return
        if recorded and not fresh and not any(k == "block-stale" and p == rel for k, p, _ in draft.findings):
            draft.find("block-stale", rel, "a plugin changed what the block holds")
        joined = "\n".join(lines[:i]) + ("\n" if i else "") + new + "\n".join(lines[j + 1:])
        self.dest(rel)
        draft.act("block", rel, f"{label} (updated)", cur.sha + sha(joined))
        draft.writes.append(("rewrite", rel, joined.encode("utf-8"), None, cur.sha))
        record(sha(new), False)

    def _installed(self, layers, lock):
        """Every plugin the project will have: the lock's and these layers', agent-core first, then by name."""
        names = set(lock.get("plugins", {})) | {layer.name for layer in layers}
        return sorted(names, key=lambda n: (n != CORE, n))

    def _gitignore(self, draft, layers, lock, entries, fresh):
        by_name = {layer.name: layer for layer in layers}
        order = self._installed(layers, lock)
        lines = []
        for name in order:
            source = by_name[name].cfg["gitignore"] if name in by_name else lock["plugins"][name].get("gitignore", [])
            for line in source:
                if line not in lines:
                    lines.append(line)
        if not fresh:
            for layer in layers:
                prior = self.locked(layer.name) or {}
                if sorted(set(layer.cfg["gitignore"])) != sorted(prior.get("gitignore") or []):
                    draft.find("block-stale", ".gitignore", f"{layer.name} {layer.version} changed its lines")

        def render(_current):
            if not lines:
                return None
            return "\n".join([GI_START] + lines + [GI_END]) + "\n"

        def record(digest, _starter):
            lock["blocks"][".gitignore"] = digest

        self._block(draft, ".gitignore", GI_START, GI_END, render, record,
                    f"agent-config-kit block ({len(lines)} lines)", fresh=fresh)

    @staticmethod
    def _sections(block):
        """The per-plugin sections of an existing CLAUDE.md block: {plugin: text}."""
        out, name, buf = {}, None, []
        for line in block.split("\n")[1:-2]:
            m = MD_SECTION.fullmatch(line)
            if m:
                if name:
                    out[name] = "\n".join(buf).strip("\n")
                name, buf = m.group(1), []
            elif name:
                buf.append(line)
        if name:
            out[name] = "\n".join(buf).strip("\n")
        return out

    def _claude_md(self, draft, layers, lock, entries, fresh):
        by_name = {layer.name: layer for layer in layers}
        order = self._installed(layers, lock)
        if not fresh:
            for layer in layers:
                prior = self.locked(layer.name) or {}
                now = sha(layer.fragment) if layer.fragment.strip() else None
                if now != prior.get("claudeMd"):
                    draft.find("block-stale", "CLAUDE.md", f"{layer.name} {layer.version} changed its CLAUDE.md lines")

        def render(current):
            old = self._sections(current) if current else {}
            parts = []
            for name in order:
                text = by_name[name].fragment.strip("\n") if name in by_name else old.get(name, "")
                if text.strip():
                    parts.append(f"<!-- agent-config-kit/{name} -->\n{text}\n")
            if not parts:
                return None
            return MD_START + "\n" + MD_HEADING + "\n\n" + "\n".join(parts) + MD_END + "\n"

        starter_layer = next((layer for layer in reversed(layers) if "CLAUDE.md" in layer.starters), None)
        starter = None
        if starter_layer and not os.path.lexists(os.path.join(self.project, "CLAUDE.md")):
            starter = starter_layer.starters["CLAUDE.md"].data.decode("utf-8")
            if not starter.endswith("\n"):
                starter += "\n"

        def record(digest, from_starter):
            lock["blocks"]["CLAUDE.md"] = digest
            if from_starter and starter_layer:
                entries[starter_layer.name]["seeded"] = sorted(set(entries[starter_layer.name]["seeded"]) | {"CLAUDE.md"})

        self._block(draft, "CLAUDE.md", MD_START, MD_END, render, record, "## Agent config kit",
                    create_text=starter, fresh=fresh)

    # ── package.json scripts ──

    def _aliases(self, draft, layers, entries, fresh):
        wanted = []
        for layer in layers:
            for name, value in layer.cfg["packageScripts"].items():
                wanted.append((layer, name, value))
        if not wanted:
            return
        cur = State(self.project, "package.json")
        if not cur.exists:
            for layer, name, value in wanted:
                if name in (self.locked(layer.name) or {}).get("packageScripts", {}):
                    draft.find("alias-missing", "package.json", f"scripts.{name}: package.json is gone")
                    entries[layer.name]["packageScripts"].pop(name, None)
            names = ", ".join(n for _, n, _ in wanted)
            hint = "; unlock runs as ./scripts/ops/unlock.sh" if any(n == "unlock" for _, n, _ in wanted) else ""
            draft.act("note", "package.json", f"none here, so no {names} script is added{hint}")
            return
        by_hand = ", ".join(f"scripts.{n} = {json.dumps(v)}" for _, n, v in wanted)
        if cur.link or not cur.file:
            draft.act("conflict", "package.json", f"is not a plain file: nothing written; add by hand: {by_hand}",
                      "link" if cur.link else "dir")
            return
        try:
            data = json.loads(cur.text())
        except ValueError:
            data = None
        scripts = data.get("scripts", {}) if isinstance(data, dict) else None
        if not isinstance(scripts, dict):
            draft.act("conflict", "package.json", f"not a JSON object with a scripts object: add by hand: {by_hand}",
                      cur.sha)
            return
        additions = {}
        for layer, name, value in wanted:
            recorded = (self.locked(layer.name) or {}).get("packageScripts", {})
            if name not in scripts:
                if not fresh:
                    draft.find("alias-missing", "package.json", f"scripts.{name} is missing")
                additions[name] = value
                entries[layer.name]["packageScripts"][name] = value
                draft.act("alias", "package.json", f"scripts.{name} = {json.dumps(value)}", sha(value))
            elif scripts[name] != value:
                if name in recorded and not fresh:
                    draft.find("alias-missing", "package.json", f"scripts.{name} changed to {json.dumps(scripts[name])}")
                draft.act("conflict", f"package.json scripts.{name}",
                          f"yours: {json.dumps(scripts[name])}, kit: {json.dumps(value)} (kept yours)", cur.sha)
                entries[layer.name]["packageScripts"].pop(name, None)
        if additions:
            text = add_scripts(cur.text(), data, additions)
            self.dest("package.json")
            draft.writes.append(("rewrite", "package.json", text.encode("utf-8"), None, cur.sha))
            draft.actions = [(k, p, d, part + sha(text) if k == "alias" else part) for k, p, d, part in draft.actions]

    # ── double wiring ──

    def double_wiring(self, layers):
        mine = {}
        for layer in [self.core] + [layer for layer in layers if layer is not self.core]:
            if not layer.hooks:
                continue
            try:
                with open(layer.hooks, encoding="utf-8") as fh:
                    wiring = json.load(fh)
            except (OSError, ValueError) as err:
                raise Usage(f"{layer.hooks} is not readable JSON ({err})")
            for command in hook_commands(wiring):
                for name in re.findall(r"\$\{CLAUDE_PLUGIN_ROOT\}/scripts/([A-Za-z0-9_.-]+\.sh)", command):
                    mine.setdefault(name, layer.name)
        found = []
        for rel in (SETTINGS, LOCAL_SETTINGS):
            cur = State(self.project, rel)
            if not cur.file:
                continue
            try:
                data = json.loads(cur.text())
            except ValueError:
                continue
            hooks = data.get("hooks") if isinstance(data, dict) else None
            if not isinstance(hooks, dict):
                continue
            for event in sorted(hooks):
                groups = hooks[event] if isinstance(hooks[event], list) else []
                for i, group in enumerate(groups):
                    for command in hook_commands({"hooks": {event: [group]}}):
                        for name in sorted(set(re.findall(r"([A-Za-z0-9_.-]+\.sh)", command))):
                            if name in mine:
                                found.append(("double-wired", rel,
                                              f"hooks.{event}[{i}] runs {name}, which {mine[name]} also runs"))
        return found

    # ── writing ──

    def write(self, draft):
        written = []
        try:
            for op in draft.writes:
                kind, rel = op[0], op[1]
                full = self.dest(rel)
                if kind == "create":
                    os.makedirs(os.path.dirname(full), exist_ok=True)
                    self.dest(rel)
                    try:
                        fd = os.open(full, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), op[3])
                    except FileExistsError:
                        raise Refused(f"{rel} appeared since the draft; nothing more was written and no lock was "
                                      "written. Run the plan again")
                    with os.fdopen(fd, "wb") as fh:
                        fh.write(op[2])
                    os.chmod(full, op[3])
                elif kind in ("replace", "rewrite"):
                    cur = State(self.project, rel)
                    if not cur.file or cur.sha != op[4]:
                        raise Refused(f"{rel} changed since the draft; nothing more was written and no lock was "
                                      "written. Run the plan again")
                    mode = op[3] if op[3] is not None else stat.S_IMODE(os.stat(full).st_mode)
                    atomic_write(full, op[2], mode)
                elif kind == "chmod":
                    os.chmod(full, op[3])
                elif kind == "lock":
                    os.makedirs(os.path.dirname(full), exist_ok=True)
                    if os.path.islink(full):
                        raise Refused(f"{LOCK} is a symlink")
                    atomic_write(full, op[2], CODE_PLAIN)
                written.append((kind, rel))
        except Refused:
            for kind, rel in written:
                print(f"  wrote    {rel}", file=sys.stderr)
            raise
        return written


def hook_commands(wiring):
    """Every `type: command` string of a hooks wiring ({"hooks": {event: [group, ...]}})."""
    hooks = wiring.get("hooks") if isinstance(wiring, dict) else None
    if not isinstance(hooks, dict):
        return
    for groups in hooks.values():
        if not isinstance(groups, list):
            continue
        for group in groups:
            inner = group.get("hooks") if isinstance(group, dict) else None
            if not isinstance(inner, list):
                continue
            for hook in inner:
                if isinstance(hook, dict) and isinstance(hook.get("command"), str):
                    yield hook["command"]


def atomic_write(full, data, mode):
    folder = os.path.dirname(full)
    tmp = os.path.join(folder, f".{os.path.basename(full)}.agentkit-{os.getpid()}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, full)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def add_scripts(text, data, additions):
    """package.json with `additions` added to scripts, keeping the file's own formatting where it can."""
    indent = "  "
    for line in text.split("\n")[1:]:
        m = re.match(r"^([ \t]+)\S", line)
        if m:
            indent = m.group(1)
            break
    expected = copy.deepcopy(data)
    expected.setdefault("scripts", {})
    expected["scripts"].update(additions)
    entries = [f"{json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)}" for k, v in additions.items()]
    # A file written on one line stays on one line; so does a scripts object written on one line.
    one_line = "\n" not in text.strip()
    out = None
    try:
        span = top_level_value(text, "scripts")
        if span:
            start, end = span  # the { and the } of scripts
            inner = text[start + 1:end]
            if inner.strip():
                k = end - 1
                while text[k] in " \t\r\n":
                    k -= 1
                sep = ", " if "\n" not in text[start:end + 1] else f",\n{indent * 2}"
                out = text[:k + 1] + "".join(sep + e for e in entries) + text[k + 1:]
            elif one_line:
                out = text[:start + 1] + ", ".join(entries) + text[end:]
            else:
                out = (text[:start + 1] + "\n" + ",\n".join(indent * 2 + e for e in entries) + "\n" + indent
                       + text[end:])
        else:
            close = text.rstrip().rfind("}")
            k = close - 1
            while k >= 0 and text[k] in " \t\r\n":
                k -= 1
            if one_line:
                member = "\"scripts\": {" + ", ".join(entries) + "}"
                out = text[:k + 1] + ("" if text[k] == "{" else ", ") + member + text[k + 1:]
            else:
                member = (f"{indent}\"scripts\": {{\n" + ",\n".join(indent * 2 + e for e in entries) + f"\n{indent}}}")
                out = text[:k + 1] + ("\n" if text[k] == "{" else ",\n") + member + "\n" + text[close:]
        if json.loads(out) != expected:
            out = None
    except (ValueError, IndexError):
        out = None
    if out is None:
        out = json.dumps(expected, indent=indent, ensure_ascii=False) + ("\n" if text.endswith("\n") else "")
    return out


def top_level_value(text, wanted):
    """(start, end) of the object value of a top-level key, or None: a small JSON scanner."""
    depth, i, n, key, expect_value = 0, 0, len(text), None, False
    last_string = None
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            last_string = json.loads(text[i:j + 1])
            i = j + 1
            continue
        if c == ":" and depth == 1:
            key, expect_value = last_string, True
        elif c in "{[":
            if depth == 1 and expect_value and key == wanted and c == "{":
                start, d, k = i, 0, i
                while k < n:
                    ch = text[k]
                    if ch == '"':
                        k += 1
                        while k < n and text[k] != '"':
                            k += 2 if text[k] == "\\" else 1
                    elif ch in "{[":
                        d += 1
                    elif ch in "}]":
                        d -= 1
                        if d == 0:
                            return start, k
                    k += 1
                return None
            depth += 1
            expect_value = False
        elif c in "}]":
            depth -= 1
        elif c == "," and depth == 1:
            expect_value = False
        i += 1
    return None


# ── output ───────────────────────────────────────────────────────────────────────────────────────

def line(kind, path, detail):
    pad = " " * max(1, 40 - len(path))
    return f"  {kind:<8} {path}{pad}{detail}".rstrip() if detail else f"  {kind:<8} {path}"


def ordered(actions):
    return sorted(actions, key=lambda a: (ORDER.index(a[0]) if a[0] in ORDER else len(ORDER), a[1], a[2]))


def digest_of(actions):
    parts = [{"kind": k, "path": p, "detail": d, "sha": part} for k, p, d, part in ordered(actions)]
    return sha(canon(parts))


def exit_code(findings):
    code = 0
    if any(k in DRIFT for k, _, _ in findings):
        code |= 1
    if any(k == "double-wired" for k, _, _ in findings):
        code |= 4
    return code


def print_draft(engine, title, plugins, draft, as_json):
    actions = ordered(draft.actions)
    digest = digest_of(draft.actions)
    if as_json:
        print(json.dumps({"plugins": [{"name": n, "version": v} for n, v in plugins],
                          "actions": [{"kind": k, "path": p, "detail": d} for k, p, d, _ in actions],
                          "digest": digest}, indent=2, ensure_ascii=False))
        return
    names = " + ".join(f"{n} {v}" for n, v in plugins)
    print(f"{title} · {names} · project {engine.display()}")
    for kind, path, detail, _ in actions:
        print(line(kind, path, detail))
    if not draft.writes:
        print("  (nothing to write)")
    print(f"digest {digest}")


# ── commands ─────────────────────────────────────────────────────────────────────────────────────

def setup_layers(engine):
    """The layers a setup installs, or a message when the target is already set up."""
    if engine.locked(engine.target.name):
        prior = engine.locked(engine.target.name)
        return None, (f"already set up ({engine.target.name} {prior.get('version')}); "
                      f"run /{engine.target.name}:sync")
    layers = [layer for layer in engine.layers() if not engine.locked(layer.name)]
    for layer in layers:
        for other in layer.cfg["conflictsWith"]:
            if engine.locked(other):
                raise Refused(f"{layer.name} conflicts with {other}, which this project has set up; "
                              "a project uses one of them")
    return layers, ""


def parse_answers(values, layers):
    given = {}
    known = {q["id"]: q for layer in layers for q in layer.cfg["questions"]}
    for item in values or []:
        if "=" not in item:
            raise Usage(f"--answer {item}: write it as ID=VALUE")
        qid, value = item.split("=", 1)
        if qid not in known:
            raise Usage(f"--answer {item}: no question {qid!r} in this setup "
                        f"(questions: {', '.join(sorted(known)) or 'none'})")
        if value not in known[qid]["choices"]:
            raise Usage(f"--answer {item}: choose one of {', '.join(known[qid]['choices'])}")
        given[qid] = value
    return given


def cmd_questions(engine, args):
    layers, message = setup_layers(engine)
    if message:
        if args.json:
            print(json.dumps({"plugin": engine.target.name, "stack": engine.target.stack, "questions": [],
                              "message": message}, indent=2))
        else:
            print(message)
        return 0
    questions = [dict(q, plugin=layer.name) for layer in layers for q in layer.cfg["questions"]]
    if args.json:
        print(json.dumps({"plugin": engine.target.name, "stack": engine.target.stack,
                          "questions": [{k: q.get(k, "") for k in ("plugin", "id", "ask", "why", "choices",
                                                                    "recommended", "detect")} for q in questions]},
                         indent=2, ensure_ascii=False))
        return 0
    names = " + ".join(f"{layer.name} {layer.version}" for layer in layers)
    print(f"agent-setup questions · {names} · project {engine.display()}")
    if not questions:
        print("  (no questions: the plan needs no answers)")
    for n, q in enumerate(questions, 1):
        print(f"{n}. [{q['plugin']}] {q['id']}: {q['ask']}")
        print(f"   why: {q['why']}")
        print(f"   choices: {' | '.join(q['choices'])}   recommended: {q['recommended']}")
        if q.get("detect"):
            print(f"   detect: {q['detect']}")
    return 0


def cmd_setup_plan(engine, args, apply=False):
    layers, message = setup_layers(engine)
    if message:
        print(message)
        return 0
    given = parse_answers(args.answer, layers)
    draft = engine.plan(layers, given, fresh=True)
    plugins = [(layer.name, layer.version) for layer in reversed(layers)]
    return finish(engine, draft, plugins, "agent-setup", args, apply)


def cmd_sync_plan(engine, args, apply=False):
    layers = [layer for layer in engine.layers() if engine.locked(layer.name)]
    missing = [layer.name for layer in engine.layers() if not engine.locked(layer.name)]
    if not layers:
        if apply:
            raise Refused(f"nothing is set up here to sync: run /{engine.target.name}:setup")
        print(f"agent-sync plan · nothing is set up here: run /{engine.target.name}:setup")
        return 0
    for name in missing:
        print(f"{name} is not set up here: run /{name}:setup", file=sys.stderr)
    draft = engine.plan(layers, {}, fresh=False)
    plugins = [(layer.name, layer.version) for layer in reversed(layers)]
    return finish(engine, draft, plugins, "agent-sync", args, apply)


def finish(engine, draft, plugins, tool, args, apply):
    if not apply:
        print_draft(engine, f"{tool} plan", plugins, draft, args.json)
        return 0
    digest = digest_of(draft.actions)
    if args.digest != digest:
        raise Refused(f"the project changed since the draft (approved {args.digest}, now {digest}); "
                      f"nothing was written. Show a new plan")
    written = engine.write(draft)
    names = " + ".join(f"{n} {v}" for n, v in plugins)
    print(f"{tool} apply · {names} · project {engine.display()}")
    for kind, rel in written:
        print(f"  wrote    {rel}" if kind != "chmod" else f"  chmod    {rel}")
    if not written:
        print("  (nothing to write)")
    return 0


def cmd_check(engine, args):
    findings = []
    lock = engine.lock
    if lock is None:
        why = ("setup has not run: .claude/agent-config.json opts the project in, but there is no lock"
               if os.path.isfile(os.path.join(engine.project, CONFIG)) else "not set up here")
        for layer in engine.layers():
            findings.append(("no-lock", LOCK, f"{layer.name}: {why}; run /{engine.target.name}:setup"))
        findings += engine.double_wiring(engine.layers())
    else:
        layers = [layer for layer in engine.layers() if engine.locked(layer.name)]
        for layer in engine.layers():
            if not engine.locked(layer.name):
                findings.append(("no-lock", LOCK, f"{layer.name} is not in the lock; run /{layer.name}:setup"))
        for name in sorted(lock["plugins"]):
            if name not in {layer.name for layer in engine.layers()}:
                findings.append(("unchecked", LOCK, f"{name}: its templates were not given"))
        if layers:
            draft = engine.plan(layers, {}, fresh=False)
            findings += draft.findings
        else:
            findings += engine.double_wiring(engine.layers())
    findings = sorted(set(findings))
    code = exit_code(findings)
    if args.json:
        print(json.dumps({"plugin": engine.target.name, "version": engine.target.version,
                          "findings": [{"kind": k, "path": p, "detail": d} for k, p, d in findings],
                          "exit": code}, indent=2, ensure_ascii=False))
        return code
    names = " + ".join(f"{layer.name} {layer.version}" for layer in reversed(engine.layers()))
    print(f"agent-sync check · {names} · project {engine.display()}")
    for kind, path, detail in findings:
        print(f"{kind}  {path}  {detail}")
    verdict = {0: "in sync", 1: "drift", 4: "double wiring", 5: "drift and double wiring"}[code]
    drift = sum(1 for k, _, _ in findings if k in DRIFT or k == "double-wired")
    print(f"result: {verdict} ({drift} finding{'s' if drift != 1 else ''}; exit {code})")
    return code


def cmd_own(engine, args):
    if engine.lock is None:
        raise Usage("no lock here: run setup first")
    changed = []
    for raw in args.paths:
        rel = os.path.normpath(raw).replace(os.sep, "/")
        if os.path.isabs(raw):
            rel = os.path.relpath(os.path.realpath(raw), engine.project).replace(os.sep, "/")
        owner = owner_layer = None
        for layer in engine.layers():
            entry = engine.locked(layer.name) or {}
            if (rel in entry.get("files", {})) if not args.undo else (rel in entry.get("owned", [])):
                owner, owner_layer = entry, layer
                break
        if owner is None:
            where = "owned" if args.undo else "managed"
            names = " or ".join(dict.fromkeys(layer.name for layer in reversed(engine.layers())))
            raise Usage(f"{rel} is not a {where} path of {names} in the lock")
        if args.undo:
            owner["owned"] = sorted(set(owner.get("owned", [])) - {rel})
            # The kit's bytes, not the user's: a copy that differs is then `modified` (never
            # overwritten), and one that matches is in sync.
            t = owner_layer.files.get(rel) or owner_layer.starters.get(rel)
            owner.setdefault("files", {})[rel] = t.sha if t else "sha256:" + "0" * 64
            changed.append(f"  kit      {rel}  (managed again; sync compares it with the template)")
        else:
            owner["files"].pop(rel)
            owner["owned"] = sorted(set(owner.get("owned", [])) | {rel})
            changed.append(f"  own      {rel}  (yours; sync no longer compares it)")
    text = json.dumps(engine.lock, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    atomic_write(engine.dest(LOCK), text.encode("utf-8"), CODE_PLAIN)
    print(f"agent-sync own · project {engine.display()}")
    print("\n".join(changed))
    return 0


def main(argv):
    if sys.version_info < (3, 8):
        print("agent-config-kit needs python3 3.8 or newer", file=sys.stderr)
        return 2
    subs = {"setup": ("questions", "plan", "apply"), "sync": ("check", "plan", "apply", "own")}
    if len(argv) < 2 or argv[0] not in subs or argv[1] not in subs[argv[0]]:
        tool = argv[0] if argv and argv[0] in subs else "setup|sync"
        choices = "|".join(subs.get(tool, ("questions", "plan", "apply", "check", "own")))
        print(f"usage: agent-{tool} {{{choices}}} --templates DIR --stack ID [--project DIR] ...", file=sys.stderr)
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    tool, sub = argv[0], argv[1]
    parser = argparse.ArgumentParser(prog=f"agent-{tool} {sub}")
    parser.add_argument("--templates", required=True, help="the plugin's templates/ folder")
    parser.add_argument("--stack", required=True, help="the stack id: templates/<stack>/")
    parser.add_argument("--project", help="the project root (default: the git top level, else this folder)")
    if tool == "setup" and sub in ("plan", "apply"):
        parser.add_argument("--answer", action="append", default=[], metavar="ID=VALUE")
    if sub in ("questions", "plan", "check"):
        parser.add_argument("--json", action="store_true")
    if sub == "apply":
        parser.add_argument("--digest", required=True, help="the digest the approved plan printed")
    if sub == "own":
        parser.add_argument("--undo", action="store_true", help="hand the paths back to the kit")
        parser.add_argument("paths", nargs="+")
    args = parser.parse_args(argv[2:])
    try:
        engine = Engine(tool, args)
        if tool == "setup":
            if sub == "questions":
                return cmd_questions(engine, args)
            return cmd_setup_plan(engine, args, apply=sub == "apply")
        if sub == "check":
            return cmd_check(engine, args)
        if sub == "own":
            return cmd_own(engine, args)
        return cmd_sync_plan(engine, args, apply=sub == "apply")
    except Usage as err:
        print(f"agent-{tool}: {err}", file=sys.stderr)
        return 2
    except Refused as err:
        print(f"agent-{tool}: refused: {err}", file=sys.stderr)
        return 3
    except OSError as err:
        print(f"agent-{tool}: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
