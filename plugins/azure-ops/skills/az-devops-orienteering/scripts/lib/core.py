"""Shared machinery: authentication, read-only HTTP, captures, paging, redaction.

Every request is a GET, or a POST to an endpoint that only reads (WIQL,
workitemsbatch). Each response is written as <name>.json with a <name>.meta.json
recording URL, method, status, size and time.
"""
import base64
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Azure DevOps' fixed Entra application id, the token audience for every host.
ADO_RESOURCE = "499b84ac-1321-427f-aa17-267ca6975798"
ZERO_ID = "0" * 40
ODATA_SAFE = "()=,$/'@?&"


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def org_name_from_url(url):
    u = urllib.parse.urlparse(url.rstrip("/"))
    host = u.netloc.lower()
    if host.endswith(".visualstudio.com"):
        return host.split(".")[0]
    if host == "dev.azure.com":
        return u.path.strip("/").split("/")[0]
    raise SystemExit(f"cannot read an organisation name from {url!r}")


class Hosts:
    """Every Azure DevOps service host for one organisation, dev.azure.com form."""

    def __init__(self, org):
        self.org = org
        self.core = f"https://dev.azure.com/{org}"
        self.vsrm = f"https://vsrm.dev.azure.com/{org}"
        self.vssps = f"https://vssps.dev.azure.com/{org}"
        self.vsaex = f"https://vsaex.dev.azure.com/{org}"
        self.extmgmt = f"https://extmgmt.dev.azure.com/{org}"
        self.feeds = f"https://feeds.dev.azure.com/{org}"
        self.audit = f"https://auditservice.dev.azure.com/{org}"

    def analytics(self, project):
        return f"https://analytics.dev.azure.com/{self.org}/{urllib.parse.quote(project)}/_odata/v4.0-preview"


class Auth:
    """A PAT from AZURE_DEVOPS_EXT_PAT when set, else an az CLI bearer token."""

    def __init__(self, tenant=None):
        self.tenant = tenant
        self.pat = os.environ.get("AZURE_DEVOPS_EXT_PAT")
        self.kind = "pat" if self.pat else "az"
        self._header = None

    def header(self, refresh=False):
        if self._header and not refresh:
            return self._header
        if self.pat:
            self._header = "Basic " + base64.b64encode(f":{self.pat}".encode()).decode()
            return self._header
        cmd = ["az", "account", "get-access-token", "--resource", ADO_RESOURCE,
               "--query", "accessToken", "--output", "tsv"]
        if self.tenant:
            cmd += ["--tenant", self.tenant]
        out = subprocess.run(cmd, capture_output=True, text=True)
        if out.returncode != 0:
            raise SystemExit(f"az could not issue an Azure DevOps token: {out.stderr.strip()}")
        self._header = "Bearer " + out.stdout.strip()
        return self._header


class Session:
    """HTTP plus capture storage for one module in one scope."""

    def __init__(self, auth, timeout=60):
        self.auth = auth
        self.timeout = timeout

    def request(self, url, body=None, text=False):
        """Return (status, payload, headers). Payload is parsed JSON unless text."""
        data = json.dumps(body).encode() if body is not None else None
        refreshed = False
        for attempt in range(3):
            req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
            req.add_header("Authorization", self.auth.header())
            req.add_header("Accept", "text/plain" if text else "application/json")
            if data:
                req.add_header("Content-Type", "application/json")
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    raw = resp.read()
                    headers = {k.lower(): v for k, v in resp.headers.items()}
                    if text:
                        return resp.status, raw.decode(errors="replace"), headers
                    return resp.status, json.loads(raw or b"null"), headers
            except urllib.error.HTTPError as e:
                headers = {k.lower(): v for k, v in e.headers.items()}
                if e.code == 401 and not refreshed and self.auth.kind == "az":
                    self.auth.header(refresh=True)
                    refreshed = True
                    continue
                if e.code in (429, 503) and attempt < 2:
                    time.sleep(int(headers.get("retry-after", "5")))
                    continue
                return e.code, {"error": e.read().decode(errors="replace")[:2000]}, headers
            except (TimeoutError, urllib.error.URLError) as e:
                if attempt < 1:
                    continue
                return 0, {"error": f"{type(e).__name__}: {e}"}, {}
        return 0, {"error": "retries exhausted"}, {}


class Store:
    """Captures for one module in one scope, under raw/<scope>/<module>/."""

    def __init__(self, session, root, resume):
        self.s = session
        self.root = root
        self.resume = resume

    def reset(self):
        if not self.resume and self.root.exists():
            shutil.rmtree(self.root)
        self.root.mkdir(parents=True, exist_ok=True)

    def path(self, name):
        return self.root / f"{name}.json"

    def meta(self, name):
        p = self.root / f"{name}.meta.json"
        return json.loads(p.read_text()) if p.exists() else None

    def load(self, name, default=None):
        m = self.meta(name)
        if not m or m.get("status") != 200:
            return default
        p = self.path(name)
        return json.loads(p.read_text()) if p.suffix == ".json" and p.exists() else default

    def status(self, name):
        m = self.meta(name)
        return m.get("status") if m else None

    def _cached(self, name):
        m = self.meta(name)
        if self.resume and m and m.get("status") == 200:
            log(f"skip  {self.root.name}/{name}")
            return True
        return False

    def save(self, name, url, status, payload, method="GET", body=None, text=False):
        p = self.path(name) if not text else self.root / f"{name}.log"
        p.parent.mkdir(parents=True, exist_ok=True)
        if text and status == 200:
            p.write_text(payload)
        else:
            p = self.path(name)
            p.write_text(json.dumps(payload, indent=1, ensure_ascii=False))
        meta = {"name": name, "method": method, "url": url, "body": body, "status": status,
                "bytes": p.stat().st_size, "collected": dt.datetime.now(dt.timezone.utc).isoformat()}
        (self.root / f"{name}.meta.json").write_text(json.dumps(meta, indent=1))
        log(f"{status}  {self.root.name}/{name}  {p.stat().st_size}B")
        return payload

    def get(self, name, url):
        if self._cached(name):
            return self.load(name)
        status, payload, _ = self.s.request(url)
        self.save(name, url, status, payload)
        return payload if status == 200 else None

    def post(self, name, url, body):
        if self._cached(name):
            return self.load(name)
        status, payload, _ = self.s.request(url, body)
        self.save(name, url, status, payload, "POST", body)
        return payload if status == 200 else None

    def text(self, name, url):
        m = self.meta(name)
        if self.resume and m and m.get("status") == 200:
            return (self.root / f"{name}.log").read_text()
        status, payload, _ = self.s.request(url, text=True)
        self.save(name, url, status, payload if status == 200 else payload, text=True)
        return payload if status == 200 else None

    def get_paged(self, name, url, key="value"):
        """Follow the x-ms-continuationtoken response header (build, release, graph)."""
        if self._cached(name):
            return (self.load(name) or {}).get(key, [])
        rows, token, pages = [], None, 0
        while True:
            page_url = url + (f"&continuationToken={urllib.parse.quote(token)}" if token else "")
            status, payload, headers = self.s.request(page_url)
            if status != 200:
                self.save(name, url, status, payload)
                return None
            rows.extend(payload.get(key, []) if isinstance(payload, dict) else [])
            pages += 1
            token = headers.get("x-ms-continuationtoken")
            if not token:
                break
        self.save(name, url, 200, {key: rows, "pages": pages})
        return rows

    def get_skip(self, name, url, page=500, key="value"):
        """Follow $top/$skip paging (pull requests, pushes)."""
        if self._cached(name):
            return (self.load(name) or {}).get(key, [])
        rows, skip = [], 0
        while True:
            status, payload, _ = self.s.request(f"{url}&$top={page}&$skip={skip}")
            if status != 200:
                self.save(name, url, status, payload)
                return None
            batch = payload.get(key, [])
            rows.extend(batch)
            if len(batch) < page:
                break
            skip += page
        self.save(name, url, 200, {key: rows})
        return rows

    def get_body_token(self, name, url, key):
        """Follow a continuationToken carried in the response body (user entitlements)."""
        if self._cached(name):
            return (self.load(name) or {}).get(key, [])
        rows, token = [], None
        while True:
            page_url = url + (f"&continuationToken={urllib.parse.quote(token)}" if token else "")
            status, payload, _ = self.s.request(page_url)
            if status != 200:
                self.save(name, url, status, payload)
                return None
            rows.extend(payload.get(key, []))
            token = payload.get("continuationToken")
            if not token:
                break
        self.save(name, url, 200, {key: rows})
        return rows

    def odata(self, name, base, query):
        """Follow @odata.nextLink so server-side paging never truncates a result."""
        if self._cached(name):
            return (self.load(name) or {}).get("value", [])
        url = f"{base}/{urllib.parse.quote(query, safe=ODATA_SAFE)}"
        rows, first = [], url
        while url:
            status, payload, _ = self.s.request(url)
            if status != 200:
                self.save(name, first, status, payload)
                return None
            rows.extend(payload.get("value", []))
            url = payload.get("@odata.nextLink")
        self.save(name, first, 200, {"value": rows})
        return rows

    def failures(self):
        """Every capture in this store that did not return 200, as (name, status, message)."""
        out = []
        for m in sorted(self.root.rglob("*.meta.json")):
            meta = json.loads(m.read_text())
            if meta.get("status") != 200:
                err = ""
                p = m.with_name(m.name.replace(".meta.json", ".json"))
                if p.exists():
                    try:
                        err = str(json.loads(p.read_text()).get("error", ""))
                    except (ValueError, AttributeError):
                        err = ""
                out.append((meta["name"], meta.get("status"), first_message(err)))
        return out


def first_message(err):
    m = re.search(r'"message"\s*:\s*"([^"]{0,200})', err)
    return (m.group(1) if m else err[:200]).replace("\\u0027", "'")


# Redaction for anything a report quotes from user-written text.
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
PHONE = re.compile(r"(?<![\w/])\+?\d[\d ().-]{7,}\d(?![\w/])")


def redact(text):
    if not text:
        return ""
    text = EMAIL.sub("[email]", str(text))
    return PHONE.sub("[phone]", text)


def days_between(a, b):
    return (parse_dt(b) - parse_dt(a)).total_seconds() / 86400


def parse_dt(s):
    s = s.replace("Z", "+00:00")
    if "." in s:
        head, rest = s.split(".", 1)
        frac = re.match(r"\d+", rest).group(0)
        tz = rest[len(frac):]
        s = f"{head}.{frac[:6].ljust(6, '0')}{tz}"
    d = dt.datetime.fromisoformat(s)
    return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)


def percentile(values, q):
    if not values:
        return None
    v = sorted(values)
    return v[min(len(v) - 1, int(len(v) * q))]


def md_table(headers, rows):
    if not rows:
        return "_(none)_\n"
    def esc(c):
        return str("" if c is None else c).replace("|", "\\|").replace("\n", " ")
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    out += ["| " + " | ".join(esc(c) for c in r) + " |" for r in rows]
    return "\n".join(out) + "\n"
