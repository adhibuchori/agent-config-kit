#!/usr/bin/env bash
# verify-deploy.sh: smoke-test a live deploy from the outside, on any host.
#
# It uses the network, and only when you run it: GET requests to the site you name (the page,
# then /robots.txt and the sitemap on the host the page lands on) and, for the deploy check,
# read-only calls to the GitHub API. It prints what it will contact before the first request, and
# never fetches a sitemap that robots.txt places on another host. Nothing runs it on its own.
#
# Usage: bash scripts/deploy/verify-deploy.sh --url https://www.example.com/ [options]
#        bash scripts/deploy/verify-deploy.sh --help
#
# Exit: 0 every check passed (warnings allowed), 1 at least one check failed, 2 usage error or a
# missing tool (python3, curl).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "verify-deploy: python3 is required" >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "verify-deploy: curl is required" >&2
  exit 2
fi

exec python3 -I - "$@" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from html.parser import HTMLParser
from urllib.parse import quote, urlsplit

USAGE = """usage: verify-deploy.sh --url URL [options]

Checks (each prints PASS, FAIL, WARN or SKIP):
  http       the URL answers 200 after at most 5 redirects, and never drops to plain http
  canonical  the page has one <link rel="canonical"> (or Link header): absolute, same host
  indexing   production: no noindex (meta robots or X-Robots-Tag);
             with --expect-noindex: the deploy is NOT indexable (a staging or preview site)
  robots     /robots.txt answers 200 as text and does not disallow / for every crawler
  sitemap    the sitemaps robots.txt names on the same host (else /sitemap.xml) answer 200 with
             <urlset> or <sitemapindex>; one on another host is named, not fetched
  hsts       Strict-Transport-Security with max-age > 0
  csp        Content-Security-Policy is enforced (report-only is a warning)
  nosniff    X-Content-Type-Options: nosniff
  framing    CSP frame-ancestors, or X-Frame-Options DENY or SAMEORIGIN
  referrer   Referrer-Policy is set and is not unsafe-url (missing is a warning)
  deploy     a GitHub deployment created after the merge, whose newest status is success and
             whose commit contains the merge commit

Options:
  --url URL            the live page to check (required; https:// expected)
  --canonical URL      the exact canonical URL the page must declare
  --expect-noindex     the target is a staging or preview deploy: it must not be indexable;
                       the sitemap is not checked and canonical problems are warnings
  --repo OWNER/REPO    GitHub repository for the deploy check (default: the github.com remote
                       named origin, when there is one)
  --pr N               the merged pull request whose merge time and commit the deploy must follow
  --since TIME         instead of --pr: a UTC time such as 2026-01-31T12:00:00Z
  --environment NAME   count only deployments to this GitHub environment
  --skip NAME[,NAME]   skip checks by name (repeatable)
  --timeout SECONDS    per request, 1-120 (default 15)
  --json               print one JSON object; the host list goes to stderr
  -h, --help           this text

Environment:
  GH_TOKEN, GITHUB_TOKEN   token for the GitHub API (a private repository needs one). Without
                           either, the GitHub CLI's token is used when gh is installed and signed
                           in. The token is sent only to the GitHub API, over https, and never
                           printed.
  GITHUB_API_URL           API base (default https://api.github.com; set it for GitHub Enterprise)
"""

CHECKS = ["http", "canonical", "indexing", "robots", "sitemap",
          "hsts", "csp", "nosniff", "framing", "referrer", "deploy"]
UA = "verify-deploy (agent-config-kit)"
CURL = shutil.which("curl")
SAFE_REFERRER = {"no-referrer", "no-referrer-when-downgrade", "same-origin", "origin",
                 "strict-origin", "origin-when-cross-origin", "strict-origin-when-cross-origin"}


def usage_error(msg):
    print(f"verify-deploy: {msg}", file=sys.stderr)
    print("run with --help for the options", file=sys.stderr)
    sys.exit(2)


def clean(text, limit=160):
    """Server-supplied text, made safe to print: no control characters, bounded length."""
    text = re.sub(r" {2,}", " ", re.sub(r"[\x00-\x1f\x7f]+", " ", str(text))).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def parse_time(value):
    value = value.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        stamp = datetime.fromisoformat(value)
    except ValueError:
        return None
    if stamp.tzinfo is None:
        return None
    return stamp.astimezone(timezone.utc)


def show_time(stamp):
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args(argv):
    opts = {"url": None, "canonical": None, "expect_noindex": False, "repo": None, "pr": None,
            "since": None, "environment": None, "skip": set(), "timeout": 15, "json": False}
    tokens = []
    for arg in argv:
        if arg.startswith("--") and "=" in arg:
            tokens.extend(arg.split("=", 1))
        else:
            tokens.append(arg)
    takes_value = {"--url", "--canonical", "--repo", "--pr", "--since", "--environment",
                   "--skip", "--timeout"}
    i = 0
    while i < len(tokens):
        arg = tokens[i]
        if arg in ("-h", "--help"):
            print(USAGE, end="")
            sys.exit(0)
        if arg in takes_value:
            if i + 1 >= len(tokens):
                usage_error(f"{arg} needs a value")
            value = tokens[i + 1]
            i += 2
            if arg == "--skip":
                for name in value.split(","):
                    if name not in CHECKS:
                        usage_error(f"unknown check {name!r} (checks: {', '.join(CHECKS)})")
                    opts["skip"].add(name)
            elif arg == "--timeout":
                if not re.fullmatch(r"[0-9]{1,3}", value) or not 1 <= int(value) <= 120:
                    usage_error("--timeout takes whole seconds from 1 to 120")
                opts["timeout"] = int(value)
            else:
                opts[arg[2:]] = value
            continue
        if arg == "--expect-noindex":
            opts["expect_noindex"] = True
        elif arg == "--json":
            opts["json"] = True
        else:
            usage_error(f"unknown argument {clean(arg, 60)!r}")
        i += 1

    def http_url(name, value):
        parts = urlsplit(value)
        if (parts.scheme not in ("http", "https") or not parts.hostname
                or re.search(r"[\s\"'<>\\]", value)):
            usage_error(f"{name} must be an absolute http(s) URL")

    if not opts["url"]:
        usage_error("--url is required")
    http_url("--url", opts["url"])
    if opts["canonical"]:
        http_url("--canonical", opts["canonical"])
    if opts["repo"] and not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", opts["repo"]):
        usage_error("--repo takes OWNER/REPO")
    if opts["pr"] and not re.fullmatch(r"[1-9][0-9]{0,9}", opts["pr"]):
        usage_error("--pr takes a pull request number")
    if opts["pr"] and opts["since"]:
        usage_error("--pr and --since are alternatives; pass one")
    if opts["since"]:
        stamp = parse_time(opts["since"])
        if stamp is None:
            usage_error("--since takes a time with a zone, such as 2026-01-31T12:00:00Z")
        opts["since"] = stamp
    if opts["environment"] is not None and not re.fullmatch(r"[A-Za-z0-9 _.\-/]{1,255}", opts["environment"]):
        usage_error("--environment takes a GitHub environment name")
    return opts


class Fetched:
    def __init__(self):
        self.status = 0
        self.redirects = 0
        self.final_url = ""
        self.headers = {}
        self.body = b""
        self.error = None
        self.curl_exit = 0

    def header(self, name):
        values = self.headers.get(name.lower(), [])
        return ", ".join(values) if values else None

    def ctype(self):
        return (self.header("content-type") or "").split(";")[0].strip().lower()


def last_header_block(raw):
    blocks, current = [], None
    for line in raw.decode("iso-8859-1").splitlines():
        if line.startswith("HTTP/"):
            current = {}
            blocks.append(current)
        elif current is not None and ":" in line:
            name, value = line.split(":", 1)
            current.setdefault(name.strip().lower(), []).append(value.strip())
    return blocks[-1] if blocks else {}


def fetch(url, timeout, api=False, token=None, max_bytes=5_000_000):
    got = Fetched()
    with tempfile.TemporaryDirectory(prefix="verify-deploy.") as tmp:
        body_path = os.path.join(tmp, "body")
        head_path = os.path.join(tmp, "head")
        # -q first: a personal ~/.curlrc must not change what the check sees (for example -k).
        cmd = [CURL, "-q", "-sS", "-L", "--max-redirs", "5",
               "--proto", "=https,http", "--proto-redir", "=https,http",
               "--max-time", str(timeout), "--max-filesize", str(max_bytes), "-A", UA,
               "-o", body_path, "-D", head_path,
               "-w", "%{http_code} %{num_redirects} %{url_effective}"]
        if api:
            cmd += ["-H", "Accept: application/vnd.github+json",
                    "-H", "X-GitHub-Api-Version: 2022-11-28"]
        if token:
            # From a 0600 file, so the token never shows in the process list.
            auth_path = os.path.join(tmp, "auth")
            fd = os.open(auth_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as handle:
                handle.write(f"Authorization: Bearer {token}\n")
            cmd += ["-H", "@" + auth_path]
        cmd += ["--url", url]
        run = subprocess.run(cmd, capture_output=True)
        got.curl_exit = run.returncode
        out = run.stdout.decode("utf-8", "replace").split(" ", 2)
        if len(out) == 3 and out[0].isdigit():
            got.status, got.redirects, got.final_url = int(out[0]), int(out[1] or 0), out[2]
        if os.path.exists(head_path):
            with open(head_path, "rb") as handle:
                got.headers = last_header_block(handle.read())
        if os.path.exists(body_path):
            with open(body_path, "rb") as handle:
                got.body = handle.read()
        if run.returncode != 0:
            lines = run.stderr.decode("utf-8", "replace").strip().splitlines()
            got.error = clean(lines[-1] if lines else f"curl exit {run.returncode}", 120)
    return got


class PageHead(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.canonicals = []
        self.robots = []

    def handle_starttag(self, tag, attrs):
        attr = {key.lower(): (value or "") for key, value in attrs}
        if tag == "link" and "canonical" in attr.get("rel", "").lower().split():
            self.canonicals.append(attr.get("href", "").strip())
        if tag == "meta" and attr.get("name", "").strip().lower() in ("robots", "googlebot"):
            self.robots.append(attr.get("content", ""))


def robots_rules(text):
    """Returns (blocks every crawler, sitemap URLs) for a robots.txt body."""
    blocks_all, sitemaps = False, []
    agents, seen_rule = [], False
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        key = key.lower()
        if key == "sitemap":
            sitemaps.append(value)
        elif key == "user-agent":
            if seen_rule:
                agents, seen_rule = [], False
            agents.append(value.lower())
        elif key in ("allow", "disallow"):
            seen_rule = True
            if key == "disallow" and value == "/" and "*" in agents:
                blocks_all = True
    return blocks_all, sitemaps


def github_repo_from_origin():
    try:
        run = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.fullmatch(r"(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)"
                         r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?", run.stdout.strip())
    return match.group(1) if run.returncode == 0 and match else None


def github_token(api_base):
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        value = os.environ.get(name, "").strip()
        if value:
            return value, name
    gh = shutil.which("gh")
    if not gh:
        return None, None
    host = urlsplit(api_base).hostname or ""
    host = "github.com" if host == "api.github.com" else host
    try:
        run = subprocess.run([gh, "auth", "token", "--hostname", host], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None, None
    value = run.stdout.strip()
    if run.returncode == 0 and value and not re.search(r"\s", value):
        return value, "the GitHub CLI"
    return None, None


class ApiError(Exception):
    pass


def api_get(base, path, timeout, token):
    got = fetch(base + path, timeout, api=True, token=token, max_bytes=20_000_000)
    if got.error and not got.status:
        raise ApiError(f"GitHub API unreachable: {got.error}")
    try:
        data = json.loads(got.body.decode("utf-8", "replace") or "null")
    except ValueError:
        data = None
    if got.status != 200:
        message = clean(data.get("message", ""), 100) if isinstance(data, dict) else ""
        hint = {401: "the token was rejected",
                403: "forbidden or rate-limited",
                404: "not found; a private repository needs GH_TOKEN"}.get(got.status, "")
        detail = "; ".join(part for part in (hint, message) if part)
        raise ApiError(f"GitHub API {path.split('?')[0]}: HTTP {got.status}" + (f" ({detail})" if detail else ""))
    return data


def newest_status(statuses):
    dated = [(parse_time(s.get("created_at", "")), s) for s in statuses if isinstance(s, dict)]
    dated = [(stamp, s) for stamp, s in dated if stamp is not None]
    if not dated:
        return None
    return max(dated, key=lambda pair: (pair[0], pair[1].get("id", 0)))[1].get("state")


def check_deploy(opts, repo, api_base, token):
    """Returns (status, detail) for the deploy check."""
    threshold, merge_sha, what = opts["since"], None, None
    if opts["pr"]:
        pull = api_get(api_base, f"/repos/{repo}/pulls/{opts['pr']}", opts["timeout"], token)
        if not isinstance(pull, dict) or not pull.get("merged_at"):
            return "fail", f"pull request #{opts['pr']} is not merged"
        threshold = parse_time(pull["merged_at"])
        if threshold is None:
            return "fail", f"pull request #{opts['pr']} has an unreadable merge time"
        merge_sha = pull.get("merge_commit_sha") or None
        what = f"the merge of #{opts['pr']} at {show_time(threshold)}"
    else:
        what = show_time(threshold)
    query = "?per_page=100"
    if opts["environment"]:
        query += "&environment=" + quote(opts["environment"], safe="")
    deployments = api_get(api_base, f"/repos/{repo}/deployments{query}", opts["timeout"], token)
    if not isinstance(deployments, list):
        return "fail", "GitHub API returned no deployment list"
    where = f" to {opts['environment']}" if opts["environment"] else ""
    dated = []
    for deployment in deployments:
        stamp = parse_time(deployment.get("created_at", "")) if isinstance(deployment, dict) else None
        if stamp is not None:
            dated.append((stamp, deployment))
    if not dated:
        return "fail", (f"{repo} has no GitHub deployments{where}. If your host does not report "
                        "deployments to GitHub, confirm the deploy in its own deployment list "
                        "and pass --skip deploy")
    # Newest by created_at, never by position: the list order is not a promise.
    dated.sort(key=lambda pair: (pair[0], pair[1].get("id", 0)), reverse=True)
    after = [pair for pair in dated if pair[0] >= threshold]
    if not after:
        stamp, newest = dated[0]
        return "fail", (f"no deployment{where} created after {what}; the newest is "
                        f"#{newest.get('id')} at {show_time(stamp)}. Not deployed yet is never success")
    first_state, chosen = None, None
    for index, (stamp, deployment) in enumerate(after[:10]):
        statuses = api_get(api_base, f"/repos/{repo}/deployments/{deployment.get('id')}/statuses?per_page=100",
                           opts["timeout"], token)
        state = newest_status(statuses if isinstance(statuses, list) else [])
        if index == 0:
            first_state = state
        if state == "success":
            chosen = (stamp, deployment)
            break
    if chosen is None:
        stamp, newest = after[0]
        return "fail", (f"deployment #{newest.get('id')}{where} created {show_time(stamp)} is "
                        f"{first_state or 'without a status'}: not finished, or it failed")
    stamp, deployment = chosen
    sha = str(deployment.get("sha") or "")
    if merge_sha and sha != merge_sha:
        compare = api_get(api_base, f"/repos/{repo}/compare/{merge_sha}...{sha}", opts["timeout"], token)
        relation = compare.get("status") if isinstance(compare, dict) else None
        if relation not in ("identical", "ahead"):
            return "fail", (f"deployment #{deployment.get('id')} is of {sha[:7]}, which does not "
                            f"contain the merge commit {merge_sha[:7]} ({relation or 'unknown'})")
    newer = ""
    if deployment is not after[0][1]:
        newer = f"; a newer deployment #{after[0][1].get('id')} is {first_state or 'without a status'}"
    return "pass", (f"deployment #{deployment.get('id')}{where} created {show_time(stamp)}, after "
                    f"{what}; status success; commit {sha[:7]}{newer}")


def main():
    opts = parse_args(sys.argv[1:])
    results = {}

    def record(name, status, detail):
        if name in opts["skip"]:
            status, detail = "skip", "skipped with --skip"
        results[name] = (status, clean(detail, 300))

    api_base = os.environ.get("GITHUB_API_URL", "").strip().rstrip("/") or "https://api.github.com"
    repo, deploy_reason = None, None
    if "deploy" not in opts["skip"]:
        repo = opts["repo"] or github_repo_from_origin()
        if not repo:
            deploy_reason = "no --repo, and origin is not a github.com remote"
        elif not (opts["pr"] or opts["since"]):
            deploy_reason = "pass --pr N or --since TIME to compare a deployment with a merge"
    use_api = "deploy" not in opts["skip"] and deploy_reason is None
    token, token_source = (None, None)
    if use_api:
        token, token_source = github_token(api_base)
        if token and urlsplit(api_base).scheme != "https":
            token, token_source = None, None

    target = urlsplit(opts["url"])
    hosts = (f"network: GET {opts['url']} (up to 5 redirects), then /robots.txt and the sitemap "
             "on the host it lands on")
    if use_api:
        hosts += f"; GitHub API {api_base} for {repo}"
        hosts += f" (token from {token_source})" if token else " (no token)"
    print(f"verify-deploy: {opts['url']}", file=sys.stderr if opts["json"] else sys.stdout)
    print(f"  {hosts}", file=sys.stderr if opts["json"] else sys.stdout)
    sys.stdout.flush()

    page = fetch(opts["url"], opts["timeout"])
    final = urlsplit(page.final_url or opts["url"])
    final_host = final.hostname or target.hostname
    page_ok = page.status == 200 and not page.error
    if page.error and not page.status:
        record("http", "fail", f"no response: {page.error}")
    elif page.status != 200:
        record("http", "fail", f"HTTP {page.status} at {page.final_url}" + (f" ({page.error})" if page.error else ""))
    elif page.error:
        record("http", "fail", f"200 at {page.final_url}, but the response did not complete: {page.error}")
    elif target.scheme == "https" and final.scheme != "https":
        record("http", "fail", f"redirected from https to plain http: {page.final_url}")
    else:
        hops = f" after {page.redirects} redirect{'s' if page.redirects != 1 else ''}" if page.redirects else ""
        record("http", "pass", f"200 at {page.final_url}{hops}")

    is_html = page_ok and ("html" in page.ctype())
    head = PageHead()
    if is_html:
        try:
            head.feed(page.body.decode("utf-8", "replace"))
        except Exception:  # a malformed page is reported by what was found, not by a crash
            pass

    # robots first: indexing in --expect-noindex mode reads it.
    robots = fetch(f"{final.scheme}://{final.netloc}/robots.txt", opts["timeout"])
    blocks_all, sitemaps = False, []
    robots_ok = robots.status == 200 and not robots.error
    if robots_ok:
        blocks_all, sitemaps = robots_rules(robots.body.decode("utf-8", "replace"))
    if not robots_ok:
        reason = robots.error if robots.error and not robots.status else f"HTTP {robots.status}"
        record("robots", "warn" if opts["expect_noindex"] else "fail", f"/robots.txt: {reason}")
    elif "html" in robots.ctype():
        record("robots", "fail", f"/robots.txt is served as {robots.ctype()}, not text (a soft 404?)")
    elif blocks_all and not opts["expect_noindex"]:
        record("robots", "fail", "robots.txt disallows / for every crawler: the site is hidden from search")
    else:
        note = "; disallows / for every crawler" if blocks_all else ""
        record("robots", "pass", f"200, {len(sitemaps)} sitemap line{'s' if len(sitemaps) != 1 else ''}{note}")

    # canonical
    if not page_ok:
        record("canonical", "skip", "no page to read")
    elif not is_html:
        record("canonical", "skip", f"not an HTML page ({page.ctype() or 'no content type'})")
    else:
        found = list(head.canonicals)
        for value in page.headers.get("link", []):
            for match in re.finditer(r'<([^>]+)>\s*;[^,]*\brel="?canonical"?', value, re.I):
                found.append(match.group(1).strip())
        unique = sorted(set(found))
        soft = "warn" if opts["expect_noindex"] else "fail"
        if not unique:
            record("canonical", soft, 'no <link rel="canonical"> and no canonical Link header')
        elif len(unique) > 1:
            record("canonical", soft, "several canonicals: " + ", ".join(unique[:3]))
        else:
            value = unique[0]
            parts = urlsplit(value)
            if parts.scheme not in ("http", "https") or not parts.hostname:
                record("canonical", soft, f"not an absolute URL: {value}")
            elif opts["canonical"] and value != opts["canonical"]:
                record("canonical", soft, f"{value}, expected {opts['canonical']}")
            elif final.scheme == "https" and parts.scheme != "https":
                record("canonical", soft, f"points at plain http: {value}")
            elif parts.hostname != final_host and not opts["expect_noindex"]:
                record("canonical", "fail", f"{value} points at {parts.hostname}, not {final_host}")
            else:
                record("canonical", "pass", value)

    # indexing
    noindex = []
    for value in page.headers.get("x-robots-tag", []):
        if re.search(r"\b(noindex|none)\b", value, re.I):
            noindex.append(f"X-Robots-Tag: {value}")
    for value in head.robots:
        if re.search(r"\b(noindex|none)\b", value, re.I):
            noindex.append(f'<meta name="robots" content="{value}">')
    if not page_ok:
        record("indexing", "skip", "no page to read")
    elif opts["expect_noindex"]:
        if noindex or blocks_all:
            record("indexing", "pass", "not indexable: " + ("; ".join(noindex) if noindex else "robots.txt disallows /"))
        else:
            record("indexing", "fail", "this staging or preview deploy is indexable: send X-Robots-Tag: noindex "
                                       "or serve a robots.txt that disallows /")
    elif noindex:
        record("indexing", "fail", "production page says noindex: " + "; ".join(noindex))
    else:
        record("indexing", "pass", "indexable")

    # sitemap
    if opts["expect_noindex"]:
        record("sitemap", "skip", "a staging or preview deploy needs no sitemap")
    else:
        named = [url for url in sitemaps if urlsplit(url).scheme in ("http", "https")]
        # Only the host the page landed on is fetched: robots.txt is server text, and it must not
        # send this script to hosts nobody named.
        candidates = [url for url in named if urlsplit(url).hostname == final_host][:3]
        elsewhere = [url for url in named if urlsplit(url).hostname != final_host]
        if not candidates and not elsewhere:
            candidates = [f"{final.scheme}://{final.netloc}/sitemap.xml"]
        problems, notes = [], []
        if elsewhere:
            notes.append(f"robots.txt names {len(elsewhere)} sitemap{'s' if len(elsewhere) != 1 else ''} "
                         f"on another host, not fetched (first: {elsewhere[0]})")
        for url in candidates:
            got = fetch(url, opts["timeout"], max_bytes=50_000_000)
            name = urlsplit(url).path or url
            if got.error and got.curl_exit == 63:
                notes.append(f"{name}: larger than 50 MB, not inspected")
                continue
            if got.error and not got.status:
                problems.append(f"{name}: {got.error}")
                continue
            if got.status != 200:
                problems.append(f"{name}: HTTP {got.status}")
                continue
            if got.body[:2] == b"\x1f\x8b":
                notes.append(f"{name}: 200, gzip (not inspected)")
                continue
            text = got.body.decode("utf-8", "replace")
            if not re.search(r"<(?:[A-Za-z_][\w.-]*:)?(urlset|sitemapindex)\b", text[:4096]):
                problems.append(f"{name}: 200 but not a sitemap ({got.ctype() or 'no content type'})")
                continue
            locs = re.findall(r"<(?:[A-Za-z_][\w.-]*:)?loc>\s*([^<\s]+)\s*<", text)
            foreign = [loc for loc in locs if urlsplit(loc).hostname not in (final_host, None)]
            detail = f"{name}: {len(locs)} URL{'s' if len(locs) != 1 else ''}"
            if foreign:
                detail += f", {len(foreign)} on another host (first: {foreign[0]})"
            notes.append(detail)
        if problems:
            record("sitemap", "fail", "; ".join(problems + notes))
        elif any("another host" in note or "not inspected" in note for note in notes):
            record("sitemap", "warn", "; ".join(notes))
        else:
            record("sitemap", "pass", "; ".join(notes))

    # security headers, on the final response
    if not page.status:
        for name in ("hsts", "csp", "nosniff", "framing", "referrer"):
            record(name, "skip", "no response to read")
    else:
        hsts = page.header("strict-transport-security")
        if final.scheme != "https":
            record("hsts", "fail", "served over plain http")
        elif not hsts:
            record("hsts", "fail", "no Strict-Transport-Security header")
        else:
            age = re.search(r"max-age\s*=\s*\"?(\d+)", hsts, re.I)
            if not age or int(age.group(1)) == 0:
                record("hsts", "fail", f"max-age is missing or 0: {hsts}")
            else:
                record("hsts", "pass", hsts)
        csp = page.header("content-security-policy")
        csp_ro = page.header("content-security-policy-report-only")
        if csp:
            record("csp", "pass", csp)
        elif csp_ro:
            record("csp", "warn", "report-only, nothing is enforced: " + csp_ro)
        else:
            record("csp", "fail", "no Content-Security-Policy header")
        nosniff = page.header("x-content-type-options")
        if nosniff and nosniff.strip().lower() == "nosniff":
            record("nosniff", "pass", "nosniff")
        else:
            record("nosniff", "fail", f"X-Content-Type-Options is {nosniff!r}, expected nosniff" if nosniff
                   else "no X-Content-Type-Options header")
        ancestors = re.search(r"(?:^|;)\s*frame-ancestors\s+([^;]*)", csp or "", re.I)
        xfo = (page.header("x-frame-options") or "").strip().upper()
        if ancestors:
            record("framing", "pass", "CSP frame-ancestors " + ancestors.group(1).strip())
        elif xfo in ("DENY", "SAMEORIGIN"):
            record("framing", "pass", "X-Frame-Options " + xfo)
        else:
            record("framing", "fail", "no CSP frame-ancestors and no X-Frame-Options DENY or SAMEORIGIN")
        referrer = page.header("referrer-policy")
        policies = [part.strip().lower() for part in (referrer or "").split(",") if part.strip()]
        known = [policy for policy in policies if policy in SAFE_REFERRER or policy == "unsafe-url"]
        if not referrer:
            record("referrer", "warn", "no Referrer-Policy header (browsers default to strict-origin-when-cross-origin)")
        elif known and known[-1] == "unsafe-url":
            record("referrer", "fail", "Referrer-Policy unsafe-url sends full URLs to every site")
        else:
            record("referrer", "pass", referrer)

    # deploy
    if "deploy" in opts["skip"]:
        record("deploy", "skip", "skipped with --skip")
    elif deploy_reason:
        record("deploy", "skip", deploy_reason)
    else:
        try:
            status, detail = check_deploy(opts, repo, api_base, token)
        except ApiError as error:
            status, detail = "fail", str(error)
        record("deploy", status, detail)

    counts = {state: sum(1 for s, _ in results.values() if s == state) for state in ("pass", "fail", "warn", "skip")}
    verdict = "fail" if counts["fail"] else "pass"
    if opts["json"]:
        print(json.dumps({
            "url": opts["url"],
            "finalUrl": page.final_url or None,
            "checks": [{"name": name, "status": results[name][0], "detail": results[name][1]} for name in CHECKS],
            "counts": counts,
            "result": verdict,
        }, indent=2))
    else:
        for name in CHECKS:
            status, detail = results[name]
            print(f"  {status.upper():<4}  {name:<9}  {detail}")
        print(f"result: {verdict} ({counts['pass']} passed, {counts['fail']} failed, "
              f"{counts['warn']} warnings, {counts['skip']} skipped)")
    return 1 if counts["fail"] else 0


sys.exit(main())
PY
