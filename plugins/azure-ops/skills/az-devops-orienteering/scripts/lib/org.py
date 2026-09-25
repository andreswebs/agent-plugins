"""Organisation: identities, licences, administrators, projects hidden from the caller, extensions, feeds."""
import collections
import datetime as dt
import re

from .core import md_table, parse_dt

SCOPE = "org"
TITLE = "Organisation, people and administration"

ADMIN_GROUPS = ("Project Collection Administrators", "Project Collection Build Administrators",
                "Project Collection Service Accounts", "Project Administrators", "Build Administrators",
                "Release Administrators", "Endpoint Administrators", "Endpoint Creators", "Contributors")
PROJECT_DOMAIN = "vstfs:///Classification/TeamProject/"
MICROSOFT_PUBLISHER = re.compile(r"^(ms|ms-.*|microsoft.*)$", re.I)


def _slug(s):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", s)


def collect(ctx):
    h, st = ctx.hosts, ctx.store
    st.get_paged("graph-users", f"{h.vssps}/_apis/graph/users?api-version=7.1-preview.1")
    groups = st.get_paged("graph-groups", f"{h.vssps}/_apis/graph/groups?api-version=7.1-preview.1") or []
    st.get_body_token("user-entitlements", f"{h.vsaex}/_apis/userentitlements?$top=100&api-version=7.1-preview.3", "members")
    for g in groups:
        if g.get("displayName") in ADMIN_GROUPS:
            scope = (g.get("principalName") or "").split("]")[0].strip("[") or "org"
            st.get(f"memberships/{_slug(scope)}--{_slug(g['displayName'])}",
                   f"{h.vssps}/_apis/graph/Memberships/{g['descriptor']}?direction=down&api-version=7.1-preview.1")
    st.get("installed-extensions", f"{h.extmgmt}/_apis/extensionmanagement/installedextensions?api-version=7.1-preview.1")
    feeds = st.get("feeds", f"{h.feeds}/_apis/packaging/feeds?api-version=7.1-preview.1") or {}
    for f in feeds.get("value", []):
        st.get(f"feed-packages/{_slug(f['name'])}", f"{h.feeds}/_apis/packaging/feeds/{f['id']}/packages?api-version=7.1-preview.1")
    st.get("banners", f"{h.core}/_apis/settings/entries/host/GlobalMessageBanners?api-version=3.2-preview")
    st.get("processes", f"{h.core}/_apis/work/processes?api-version=7.1-preview.2")
    st.get("projects", f"{h.core}/_apis/projects?stateFilter=all&$top=500&api-version=7.1")


def _age_bucket(date, now):
    try:
        d = parse_dt(date)
    except (ValueError, AttributeError, TypeError):
        return "never"
    if d.year < 2000:
        return "never"
    days = (now - d).days
    return "within 30 days" if days <= 30 else "within 90 days" if days <= 90 else \
        "within a year" if days <= 365 else "over a year"


def analyse(ctx):
    st = ctx.store
    now = dt.datetime.now(dt.timezone.utc)
    users = (st.load("graph-users") or {}).get("value", [])
    groups = (st.load("graph-groups") or {}).get("value", [])
    ents = (st.load("user-entitlements") or {}).get("members", [])
    by_desc = {u["descriptor"]: u for u in users}
    aad_domains = collections.Counter(u.get("domain") for u in users if u.get("origin") == "aad")
    home_tenant = aad_domains.most_common(1)[0][0] if aad_domains else None

    def kind(u):
        o = u.get("origin")
        if o == "aad":
            return "directory, home tenant" if u.get("domain") == home_tenant else "directory, other tenant"
        if o == "msa":
            return "personal Microsoft account"
        return "service identity" if o == "vsts" else (o or "unknown")

    visible = {p["id"]: p["name"] for p in (st.load("projects") or {}).get("value", [])}
    scopes = {}
    for g in groups:
        d = g.get("domain") or ""
        if d.startswith(PROJECT_DOMAIN):
            pid = d[len(PROJECT_DOMAIN):]
            name = (g.get("principalName") or "").split("]")[0].strip("[")
            scopes.setdefault(pid, name)
    projects = sorted(({"name": n, "visible": pid in visible} for pid, n in scopes.items()),
                      key=lambda r: (not r["visible"], r["name"].lower()))

    admin_rows = []
    for m in sorted(st.root.glob("memberships/*.json")):
        if m.name.endswith(".meta.json"):
            continue
        scope, group = m.stem.split("--", 1)
        members = (st.load(f"memberships/{m.stem}") or {}).get("value", [])
        kinds = collections.Counter(kind(by_desc[x["memberDescriptor"]]) for x in members
                                    if x["memberDescriptor"] in by_desc)
        nested = sum(1 for x in members if x["memberDescriptor"] not in by_desc)
        if kinds or nested:
            admin_rows.append({"scope": scope, "group": group.replace("_", " "), "users": sum(kinds.values()),
                               "nested_groups": nested, "by_kind": dict(kinds)})

    msa_domains = collections.Counter((u.get("mailAddress") or "@unknown").split("@")[-1].lower()
                                      for u in users if u.get("origin") == "msa")
    lic = collections.Counter((e["accessLevel"].get("licenseDisplayName"), kind(e["user"])) for e in ents)
    ages = collections.Counter(_age_bucket(e.get("lastAccessedDate"), now) for e in ents)
    basic_idle = sum(1 for e in ents if e["accessLevel"].get("licenseDisplayName") == "Basic"
                     and _age_bucket(e.get("lastAccessedDate"), now) in ("within a year", "over a year", "never"))

    ext = (st.load("installed-extensions") or {}).get("value", [])
    third = [{"id": f"{e['publisherId']}.{e['extensionId']}", "version": e.get("version"),
              "published": (e.get("lastPublished") or "")[:10]}
             for e in ext if not MICROSOFT_PUBLISHER.match(e.get("publisherId", ""))]
    feeds = []
    for f in (st.load("feeds") or {}).get("value", []):
        code = st.status("feed-packages/" + _slug(f["name"]))
        feeds.append({"name": f["name"], "upstreams": len(f.get("upstreamSources") or []),
                      "contents": "readable" if code == 200 else "refused (%s)" % code})
    banners = st.load("banners") or {}
    banner_text = [v.get("message", "") for v in (banners.get("value") or {}).values()] \
        if isinstance(banners.get("value"), dict) else []
    procs = [{"name": p["name"], "customization": p.get("customizationType")}
             for p in (st.load("processes") or {}).get("value", [])]
    return {
        "identities_by_kind": dict(collections.Counter(kind(u) for u in users)),
        "personal_account_mail_domains": dict(msa_domains),
        "tenants_seen": len(aad_domains),
        "projects": projects,
        "projects_total": len(projects),
        "projects_hidden": sum(1 for p in projects if not p["visible"]),
        "admin_groups": admin_rows,
        "licences": [{"licence": k[0], "kind": k[1], "count": v} for k, v in sorted(lic.items())],
        "licensed_users": len(ents),
        "last_access": dict(ages),
        "basic_idle_over_90_days": basic_idle,
        "third_party_extensions": sorted(third, key=lambda r: r["id"].lower()),
        "extensions_total": len(ext),
        "feeds": feeds,
        "banners": banner_text,
        "processes": procs,
    }


def render(m):
    out = ["## Projects", "",
           f"{m['projects_total']} projects hold security groups; {m['projects_hidden']} are hidden from the caller. "
           "Counted from group domains, because the project list shows only what the caller can read.", "",
           md_table(["Project", "Visible"], [[p["name"], "yes" if p["visible"] else "no"] for p in m["projects"]]),
           "## Identities", "",
           md_table(["Kind", "Count"], sorted(m["identities_by_kind"].items())),
           f"Directory tenants seen: {m['tenants_seen']}. Personal Microsoft account mail domains:", "",
           md_table(["Domain", "Accounts"], sorted(m["personal_account_mail_domains"].items(), key=lambda x: -x[1])),
           "A personal Microsoft account alongside directory accounts suggests the organisation is not backed by "
           "Entra ID; confirm before stating it. Report people as counts and kinds only.", "",
           "## Administrative and contributor groups", "",
           md_table(["Scope", "Group", "Users", "Nested groups", "By kind"],
                    [[r["scope"], r["group"], r["users"], r["nested_groups"],
                      "; ".join(f"{k}: {v}" for k, v in sorted(r["by_kind"].items()))] for r in m["admin_groups"]]),
           "## Licences", "",
           f"Licensed users: {m['licensed_users']}. Basic licences not used in 90 days: {m['basic_idle_over_90_days']}.", "",
           md_table(["Licence", "Kind", "Count"], [[r["licence"], r["kind"], r["count"]] for r in m["licences"]]),
           md_table(["Last sign-in", "Users"], sorted(m["last_access"].items())),
           "## Extensions", "",
           f"{m['extensions_total']} installed, {len(m['third_party_extensions'])} from third parties.", "",
           md_table(["Extension", "Version", "Last published"],
                    [[e["id"], e["version"], e["published"]] for e in m["third_party_extensions"]]),
           "## Feeds, processes, banners", "",
           md_table(["Feed", "Upstream sources", "Contents"], [[f["name"], f["upstreams"], f["contents"]] for f in m["feeds"]]),
           md_table(["Process", "Customisation"], [[p["name"], p["customization"]] for p in m["processes"]]),
           "\n".join(f"- Banner: {b}" for b in m["banners"]) or "_(no banners)_", ""]
    return "\n".join(out)
