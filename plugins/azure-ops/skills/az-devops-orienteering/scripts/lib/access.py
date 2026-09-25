"""Access check: one probe per surface, recorded before anything is collected."""
import urllib.parse

from .core import first_message, md_table

SCOPE = "org"
TITLE = "Access check"


def org_probes(h):
    return {
        "connection-data": f"{h.core}/_apis/connectionData",
        "projects": f"{h.core}/_apis/projects?stateFilter=all&$top=500&api-version=7.1",
        "user-entitlements": f"{h.vsaex}/_apis/userentitlements?$top=1&api-version=7.1-preview.3",
        "graph-groups": f"{h.vssps}/_apis/graph/groups?api-version=7.1-preview.1",
        "security-namespaces": f"{h.core}/_apis/securitynamespaces?api-version=7.1",
        "service-hooks": f"{h.core}/_apis/hooks/subscriptions?api-version=7.1",
        "audit-log": f"{h.audit}/_apis/audit/auditlog?batchSize=5&api-version=7.1-preview.1",
        "audit-actions": f"{h.audit}/_apis/audit/actions?api-version=7.1-preview.1",
        "installed-extensions": f"{h.extmgmt}/_apis/extensionmanagement/installedextensions?api-version=7.1-preview.1",
        "feeds": f"{h.feeds}/_apis/packaging/feeds?api-version=7.1-preview.1",
        "agent-pools": f"{h.core}/_apis/distributedtask/pools?api-version=7.1",
    }


def project_probes(h, project):
    p = urllib.parse.quote(project)
    return {
        "repositories": f"{h.core}/{p}/_apis/git/repositories?api-version=7.1",
        "git-recycle-bin": f"{h.core}/{p}/_apis/git/recycleBin/repositories?api-version=7.1-preview.1",
        "build-definitions": f"{h.core}/{p}/_apis/build/definitions?$top=1&api-version=7.1",
        "release-definitions": f"{h.vsrm}/{p}/_apis/release/definitions?$top=1&api-version=7.1",
        "service-endpoints": f"{h.core}/{p}/_apis/serviceendpoint/endpoints?includeFailed=true&api-version=7.1",
        "work-item-types": f"{h.core}/{p}/_apis/wit/workitemtypes?api-version=7.1",
        "analytics": h.analytics(project) + "/WorkItems?$apply=aggregate($count%20as%20Count)",
        "wikis": f"{h.core}/{p}/_apis/wiki/wikis?api-version=7.1",
        "test-plans": f"{h.core}/{p}/_apis/testplan/plans?api-version=7.1",
    }


def collect(ctx):
    for name, url in org_probes(ctx.hosts).items():
        ctx.store.get(f"org/{name}", url)
    for project in ctx.projects:
        for name, url in project_probes(ctx.hosts, project).items():
            ctx.store.get(f"project/{project}/{name}", url)


def _count(payload):
    if payload is None:
        return None
    if isinstance(payload, dict):
        for k in ("value", "members", "items"):
            if isinstance(payload.get(k), list):
                return len(payload[k])
        if "count" in payload and isinstance(payload["count"], int):
            return payload["count"]
    return None


def _meaning(status, count):
    if status == 200:
        return "empty: none visible to this identity" if count == 0 else "readable"
    return {401: "refused: not signed in", 403: "refused: permission", 404: "not found",
            400: "rejected request", 0: "no response"}.get(status, f"status {status}")


def analyse(ctx):
    rows = []
    names = [("org", n) for n in org_probes(ctx.hosts)]
    names += [(f"project/{p}", n) for p in ctx.projects for n in project_probes(ctx.hosts, p)]
    for scope, n in names:
        key = f"{scope}/{n}"
        status = ctx.store.status(key)
        count = _count(ctx.store.load(key))
        msg = ""
        if status != 200:
            p = ctx.store.path(key)
            if p.exists():
                msg = first_message(p.read_text())
        rows.append({"scope": scope, "surface": n, "status": status, "count": count,
                     "meaning": _meaning(status, count), "message": msg})
    who = (ctx.store.load("org/connection-data") or {}).get("authenticatedUser", {})
    visible = [p["name"] for p in (ctx.store.load("org/projects") or {}).get("value", [])]
    return {"caller": who.get("providerDisplayName"), "caller_id": who.get("id"),
            "auth": ctx.auth.kind, "visible_projects": visible, "probes": rows}


def render(m):
    out = [f"Caller: `{m['caller']}` (credential: {m['auth']}).",
           f"Projects visible to the caller: {len(m['visible_projects'])} ({', '.join(m['visible_projects'])}).",
           "",
           "An empty result means none visible to this identity, never that none exist.",
           "A 404 beside a 403 on a sibling endpoint of the same service is a permission gap.",
           ""]
    out.append(md_table(["Scope", "Surface", "Status", "Items", "Meaning", "Message"],
                        [[r["scope"], r["surface"], r["status"], r["count"], r["meaning"], r["message"]]
                         for r in m["probes"]]))
    return "\n".join(out)
