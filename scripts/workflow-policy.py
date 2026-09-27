"""Checks every workflow this repository holds or installs against the kit's CI policy.

Run from anywhere; PyYAML is the one dependency, pinned the way the kit's trigger check runs it:

    uv run --no-project --with pyyaml==6.0.3 python3 scripts/workflow-policy.py [--release] [ROOT]

Files: .github/workflows/*.y*ml and plugins/*/templates/*/.github/workflows/*.y*ml.

Per file:
  - Triggers: pull_request and workflow_call only. Never push, schedule, pull_request_target,
    workflow_run or workflow_dispatch. Two documented exceptions (ADR 0004):
      - agent-docs-nextra's changelog.yaml also accepts repository_dispatch, the event the
        documented application's own release sends; no other file may use it.
      - a template's deepseek-review.yml also accepts issue_comment (`/ask-deepseek`), and only in
        the safe shape: `types: [created]`; top-level permissions `contents: read`; every job a call
        to this repository's deepseek-review.yml with nothing but `contents: read` and
        `pull-requests: write`, and an `if:` that requires a comment on a pull request by an OWNER,
        MEMBER or COLLABORATOR; and the called workflow checks nothing out.
  - A `pull_request: types: [closed]` workflow runs no job without a merge guard (the job's `if:`
    tests `merged`, directly or through every job it needs).
  - A top-level `permissions:` block; no `secrets: inherit`.
  - Every actions/checkout step says `persist-credentials:` explicitly.
  - A call to this repository's reusable workflows
    (adhibuchori/agent-config-kit/.github/workflows/<name>@<sha> # vX.Y.Z) names a workflow that
    exists here, pins a 40-hex SHA and carries a `# vX.Y.Z` comment. The all-zero placeholder SHA a
    template holds until the release commit exists is a warning, and an error with --release; with
    --release a real SHA must also be a commit in this clone, and the tag vX.Y.Z (when present) must
    point at it.
And: no Dependabot config in the repository or in any template.

Prints how many files it read; reading none is a failure. Exit 0 clean, 1 a problem, 2 usage.
"""

import glob
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("workflow-policy: PyYAML is missing; run: uv run --no-project --with pyyaml==6.0.3 python3 scripts/workflow-policy.py")

ALLOWED = {"pull_request", "workflow_call"}
# The one exception to ALLOWED, per file (ADR 0004): the docs site's changelog regenerates its pages
# when the application it documents announces a release. The job's `if:` names both events.
EXCEPTIONS = {
    "plugins/agent-docs-nextra/templates/docs-nextra/.github/workflows/changelog.yaml": {"repository_dispatch"},
}
# The second exception (ADR 0004): the DeepSeek review callers answer an `/ask-deepseek` comment. A
# comment can come from anyone, and GitHub gives that run the repository's secrets and a write
# token, so the file must keep the shape comment_problems() checks.
COMMENT_CALLER = re.compile(r"^plugins/[^/]+/templates/[^/]+/\.github/workflows/deepseek-review\.yml$")
COMMENT_TARGET = "deepseek-review.yml"
TRUSTED = ("OWNER", "MEMBER", "COLLABORATOR")
KIT = "adhibuchori/agent-config-kit/"
PLACEHOLDER = "0" * 40
USES_LINE = re.compile(r"^\s*(?:-\s+)?uses:\s*(['\"]?)(?P<ref>[^\s'\"#]+)\1\s*(?:#\s*(?P<comment>.*))?$")
KIT_CALL = re.compile(r"^adhibuchori/agent-config-kit/\.github/workflows/(?P<file>[A-Za-z0-9._-]+)@(?P<sha>\S+)$")


def usage(message):
    print(f"workflow-policy: {message}", file=sys.stderr)
    print("usage: workflow-policy.py [--release] [ROOT]", file=sys.stderr)
    sys.exit(2)


def guarded(jobs, name, seen=()):
    """A job is merge-guarded if its `if` tests `merged`, or every job it needs is."""
    job = jobs.get(name) or {}
    if "merged" in str(job.get("if", "")):
        return True
    needs = job.get("needs") or []
    needs = [needs] if isinstance(needs, str) else needs
    return bool(needs) and all(n not in seen and guarded(jobs, n, seen + (name,)) for n in needs)


def comment_problems(rel, root, doc, events, jobs):
    """Why an issue_comment workflow is not in the one safe shape (empty when it is)."""
    out = []
    types = (events.get("issue_comment") or {}).get("types") if isinstance(events.get("issue_comment"), dict) else None
    if types != ["created"]:
        out.append(f"{rel}: issue_comment must be limited to `types: [created]`")
    if doc.get("permissions") != {"contents": "read"}:
        out.append(f"{rel}: an issue_comment workflow needs top-level `permissions: contents: read` and nothing more")
    if not jobs:
        out.append(f"{rel}: an issue_comment workflow needs a job")
    for name, job in jobs.items():
        if not isinstance(job, dict):
            continue
        call = KIT_CALL.match(str(job.get("uses", "")))
        if not call or call.group("file") != COMMENT_TARGET or job.get("steps"):
            out.append(f"{rel}: job `{name}` must be a call to this repository's {COMMENT_TARGET} and nothing else")
        perms = job.get("permissions")
        if not isinstance(perms, dict) or not set(perms.items()) <= {("contents", "read"), ("pull-requests", "write")}:
            out.append(f"{rel}: job `{name}` may hold `contents: read` and `pull-requests: write` only")
        cond = str(job.get("if", ""))
        needed = ["github.event.issue.pull_request", "github.event.comment.author_association"] + [f'"{t}"' for t in TRUSTED]
        missing = [n for n in needed if n not in cond]
        extra = [a for a in ("CONTRIBUTOR", "FIRST_TIMER", "FIRST_TIME_CONTRIBUTOR", "MANNEQUIN", "NONE") if a in cond]
        if missing or extra:
            out.append(f"{rel}: job `{name}` must run on a comment only for a pull request and an OWNER, MEMBER or COLLABORATOR"
                       + (f" (missing {', '.join(missing)})" if missing else "") + (f" (also allows {', '.join(extra)})" if extra else ""))
    target = os.path.join(root, ".github", "workflows", COMMENT_TARGET)
    if os.path.isfile(target):
        with open(target, encoding="utf-8") as fh:
            called = yaml.safe_load(fh) or {}
        for jname, job in (called.get("jobs") or {}).items():
            for step in (job or {}).get("steps") or []:
                if isinstance(step, dict) and str(step.get("uses", "")).startswith("actions/checkout@"):
                    out.append(f".github/workflows/{COMMENT_TARGET}: job `{jname}` checks out code, which a comment-triggered run must never do")
    return out


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def main():
    args = sys.argv[1:]
    release = False
    root = None
    for a in args:
        if a == "--release":
            release = True
        elif a.startswith("-"):
            usage(f"unknown option {a}")
        elif root is None:
            root = a
        else:
            usage("at most one ROOT")
    root = root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    patterns = [".github/workflows/*.yml", ".github/workflows/*.yaml",
                "plugins/*/templates/*/.github/workflows/*.yml",
                "plugins/*/templates/*/.github/workflows/*.yaml"]
    files = sorted({p for pat in patterns for p in glob.glob(os.path.join(root, pat))})
    problems, warnings = [], []

    for path in files:
        rel = os.path.relpath(path, root)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        try:
            doc = yaml.safe_load(text)
        except yaml.YAMLError as err:
            problems.append(f"{rel}: not valid YAML ({err.__class__.__name__})")
            continue
        if not isinstance(doc, dict):
            problems.append(f"{rel}: not a YAML mapping")
            continue

        on = doc.get("on", doc.get(True))  # YAML 1.1 reads a bare `on:` key as True
        if isinstance(on, str):
            events = {on: None}
        elif isinstance(on, list):
            events = dict.fromkeys(on)
        elif isinstance(on, dict):
            events = on
        else:
            problems.append(f"{rel}: no `on:` block")
            events = {}
        posix = rel.replace(os.sep, "/")
        allowed = ALLOWED | EXCEPTIONS.get(posix, set())
        if COMMENT_CALLER.match(posix):
            allowed = allowed | {"issue_comment"}
        for event in events:
            if event not in allowed:
                problems.append(f"{rel}: trigger `{event}` is not allowed (pull-request events and workflow_call only)")

        jobs = doc.get("jobs") or {}
        if "issue_comment" in events and COMMENT_CALLER.match(posix):
            problems.extend(comment_problems(rel, root, doc, events, jobs))
        pr = events.get("pull_request")
        if isinstance(pr, dict) and "closed" in (pr.get("types") or []):
            for name in jobs:
                if not guarded(jobs, name):
                    problems.append(f"{rel}: job `{name}` can run on a closed pull request that was not merged")
        if "permissions" not in doc:
            problems.append(f"{rel}: no top-level `permissions:`")

        for name, job in jobs.items():
            if not isinstance(job, dict):
                continue
            if job.get("secrets") == "inherit":
                problems.append(f"{rel}: job `{name}` uses `secrets: inherit`; pass named secrets")
            for i, step in enumerate(job.get("steps") or []):
                if not isinstance(step, dict):
                    continue
                uses = str(step.get("uses", ""))
                if uses.startswith("actions/checkout@"):
                    with_ = step.get("with") or {}
                    if "persist-credentials" not in with_:
                        problems.append(f"{rel}: job `{name}` step {i + 1} checks out without an explicit `persist-credentials:`")

        # Comments are not in the parsed YAML, so the pins of kit calls are read from the lines.
        for n, line in enumerate(text.splitlines(), 1):
            m = USES_LINE.match(line)
            if not m or not m.group("ref").startswith(KIT):
                continue
            ref, comment = m.group("ref"), (m.group("comment") or "").strip()
            call = KIT_CALL.match(ref)
            where = f"{rel}:{n}"
            if not call:
                problems.append(f"{where}: `{ref}` is not a call to one of this repository's reusable workflows")
                continue
            target = os.path.join(root, ".github", "workflows", call.group("file"))
            if not os.path.isfile(target):
                problems.append(f"{where}: calls .github/workflows/{call.group('file')}, which this repository does not have")
            sha = call.group("sha")
            version = re.fullmatch(r"v(\d+\.\d+\.\d+)", comment.split()[0]) if comment else None
            if not re.fullmatch(r"[0-9a-f]{40}", sha):
                problems.append(f"{where}: pin `{sha}` is not a full 40-hex commit SHA")
            if not version:
                problems.append(f"{where}: the pin needs an exact `# vX.Y.Z` release comment")
            if sha == PLACEHOLDER:
                msg = f"{where}: placeholder SHA; the release commit replaces it (RELEASING.md)"
                (problems if release else warnings).append(msg)
            elif release and re.fullmatch(r"[0-9a-f]{40}", sha):
                if git(root, "cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
                    problems.append(f"{where}: {sha} is not a commit in this clone")
                elif version:
                    tag = git(root, "rev-parse", "--verify", "--quiet", f"refs/tags/v{version.group(1)}^{{commit}}")
                    if tag.returncode == 0 and tag.stdout.strip() != sha:
                        problems.append(f"{where}: tag v{version.group(1)} is {tag.stdout.strip()}, not {sha}")

    for pat in (".github/dependabot.yml", ".github/dependabot.yaml",
                "plugins/*/templates/*/.github/dependabot.yml", "plugins/*/templates/*/.github/dependabot.yaml"):
        for found in glob.glob(os.path.join(root, pat)):
            problems.append(f"{os.path.relpath(found, root)}: Dependabot config is not used in this kit")

    print(f"workflow-policy: scanned {len(files)} workflow file(s)")
    if not files:
        print("FAIL: no workflow files scanned")
        return 1
    for w in warnings:
        print("WARN:", w)
    for p in problems:
        print("FAIL:", p)
    print(f"{len(problems)} problem(s), {len(warnings)} warning(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
