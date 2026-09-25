"""Boards: whether the board is live, how it is used, what is in flight, what touches the migration."""
import collections
import datetime as dt
import re
import urllib.parse
from pathlib import Path

from .core import md_table, redact

SCOPE = "project"
TITLE = "Boards: usage, in-flight work and migration-relevant items"
DEFAULT_KEYWORDS = Path(__file__).resolve().parents[2] / "assets" / "keywords.txt"
SYNC_TAG = re.compile(r"^\[?[A-Z][A-Z0-9]{1,9}-\d+\]?$")
SYNC_COMMENT = re.compile(r"paired with|getint\.io|synced from|jira", re.I)
HOTFIX = re.compile(r"hot ?fix", re.I)
FIELDS = ("WorkItemId,Title,WorkItemType,State,StateCategory,Priority,TagNames,CreatedDate,ChangedDate,ClosedDate")
EXPAND = "Area($select=AreaPath),Iteration($select=IterationPath),AssignedTo($select=UserName),CreatedBy($select=UserName)"
CLOSED = ("Completed", "Removed")


def keywords(ctx):
    terms = [t.strip() for t in DEFAULT_KEYWORDS.read_text().splitlines() if t.strip() and not t.startswith("#")]
    if ctx.args.keywords:
        terms += [t.strip() for t in Path(ctx.args.keywords).read_text().splitlines() if t.strip() and not t.startswith("#")]
    return list(dict.fromkeys(terms))


def _slug(term):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", term)


def collect(ctx):
    h, st, p = ctx.hosts, ctx.store, urllib.parse.quote(ctx.project)
    a, sk = h.analytics(ctx.project), ctx.since_sk
    wit = f"{h.core}/{p}/_apis/wit"
    st.get("areas", f"{wit}/classificationnodes/areas?$depth=10&api-version=7.1")
    st.get("iterations", f"{wit}/classificationnodes/iterations?$depth=10&api-version=7.1")
    st.get("teams", f"{h.core}/_apis/projects/{p}/teams?api-version=7.1")
    st.get("work-item-types", f"{wit}/workitemtypes?api-version=7.1")
    st.get("saved-queries", f"{wit}/queries?$depth=2&$expand=wiql&api-version=7.1")
    st.get("tags", f"{wit}/tags?api-version=7.1-preview.1")
    st.odata("range", a, "WorkItems?$apply=aggregate($count as Count,CreatedDate with min as First,ChangedDate with max as Last)")
    st.odata("type-state", a, "WorkItems?$apply=groupby((WorkItemType,State,StateCategory),aggregate($count as Count))")
    st.odata("created-by-year", a, "WorkItems?$apply=groupby((CreatedOn/Year,WorkItemType),aggregate($count as Count))")
    since24 = (ctx.today.replace(day=1) - dt.timedelta(days=730)).replace(day=1)
    st.odata("created-by-day", a, f"WorkItems?$apply=filter(CreatedDateSK ge {since24:%Y%m%d})/groupby((CreatedDateSK),aggregate($count as Count))")
    st.odata("closed-by-day", a, f"WorkItems?$apply=filter(ClosedDateSK ge {since24:%Y%m%d})/groupby((ClosedDateSK),aggregate($count as Count))")
    months, d = [], since24
    while d <= ctx.today:
        months.append(int(d.strftime("%Y%m%d")))
        d = (d.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
    st.odata("open-monthly", a, "WorkItemSnapshot?$apply=filter((" + " or ".join(f"DateSK eq {m}" for m in months)
             + ") and StateCategory ne 'Completed' and StateCategory ne 'Removed')/groupby((DateSK),aggregate($count as Count))")
    st.odata("items-open", a, f"WorkItems?$select={FIELDS}&$expand={EXPAND}&$filter=StateCategory ne 'Completed' and StateCategory ne 'Removed'")
    recent = st.odata("items-changed", a, f"WorkItems?$select={FIELDS}&$expand={EXPAND}&$filter=ChangedDateSK ge {sk}") or []
    ids = sorted({r["WorkItemId"] for r in recent})
    _batch(ctx, "relations-changed", ids, expand="relations")
    hits = {}
    for term in keywords(ctx):
        q = term.replace("'", "''")
        res = st.post(f"keyword/{_slug(term)}", f"{wit}/wiql?api-version=7.1",
                      {"query": "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND "
                                f"([System.Title] CONTAINS WORDS '{q}' OR [System.Description] CONTAINS WORDS '{q}')"})
        hits[term] = [w["id"] for w in (res or {}).get("workItems", [])]
    changed = {r["WorkItemId"]: r["ChangedDate"] for r in recent}
    shortlist = sorted({i for v in hits.values() for i in v if i in changed}, key=lambda i: changed[i], reverse=True)
    shortlist = shortlist[:ctx.args.detail_cap]
    _batch(ctx, "detail", shortlist, expand="all")
    for i in shortlist:
        st.get(f"comments/{i}", f"{wit}/workItems/{i}/comments?api-version=7.1-preview.4")


def _batch(ctx, name, ids, expand):
    st = ctx.store
    if st.resume and st.status(name) == 200:
        return
    url = f"{ctx.hosts.core}/{urllib.parse.quote(ctx.project)}/_apis/wit/workitemsbatch?api-version=7.1"
    items, failed = [], 0
    for i in range(0, len(ids), 200):
        status, payload, _ = st.s.request(url, {"ids": ids[i:i + 200], "$expand": expand})
        if status == 200:
            items += payload.get("value", [])
        else:
            failed += 1
    st.save(name, url, 200, {"value": items, "failed_batches": failed}, "POST",
            {"ids": len(ids), "$expand": expand})


def _v(st, name):
    return (st.load(name) or {}).get("value", [])


def _depth(node):
    return 1 + max((_depth(c) for c in node.get("children", [])), default=0)


def _count_nodes(node):
    return 1 + sum(_count_nodes(c) for c in node.get("children", []))


def _by_month(rows, key):
    out = collections.Counter()
    for r in rows:
        out[str(r[key])[:6]] += r["Count"]
    return dict(sorted(out.items()))


def analyse(ctx):
    st, since = ctx.store, ctx.since_iso
    rng = (_v(st, "range") or [{}])[0]
    by_year = collections.defaultdict(lambda: collections.Counter())
    for r in _v(st, "created-by-year"):
        by_year[(r.get("CreatedOn") or {}).get("Year")][r["WorkItemType"]] += r["Count"]
    created_m, closed_m = _by_month(_v(st, "created-by-day"), "CreatedDateSK"), _by_month(_v(st, "closed-by-day"), "ClosedDateSK")
    open_items, changed = _v(st, "items-open"), _v(st, "items-changed")
    stale_cut = (ctx.today - dt.timedelta(days=730)).isoformat()
    live = [i for i in open_items if (i.get("ChangedDate") or "") >= stale_cut]
    tags = collections.Counter(t for i in changed for t in (i.get("TagNames") or "").split("; ") if t)
    sync_tagged = sum(1 for i in changed if any(SYNC_TAG.match(t) for t in (i.get("TagNames") or "").split("; ")))
    root_area = sum(1 for i in changed if "\\" not in ((i.get("Area") or {}).get("AreaPath") or ""))
    root_iter = sum(1 for i in changed if "\\" not in ((i.get("Iteration") or {}).get("IterationPath") or ""))
    created_window = [i for i in changed if (i.get("CreatedDate") or "") >= since]
    creators = collections.Counter((i.get("CreatedBy") or {}).get("UserName") for i in created_window)
    rel = _v(st, "relations-changed")
    links = collections.Counter()
    linked = 0
    for w in rel:
        kinds = [r["rel"] + (":" + r["url"].split("/")[-2] if r["rel"] == "ArtifactLink" else "")
                 for r in w.get("relations") or []]
        links.update(kinds)
        linked += any(k.startswith("ArtifactLink") for k in kinds)
    hits, hits_recent = {}, {}
    changed_ids = {i["WorkItemId"] for i in changed}
    for f in sorted(st.root.glob("keyword/*.json")):
        if f.name.endswith(".meta.json"):
            continue
        meta = st.meta(f"keyword/{f.stem}") or {}
        term = re.search(r"CONTAINS WORDS '((?:[^']|'')*)'", (meta.get("body") or {}).get("query", ""))
        term = term.group(1).replace("''", "'") if term else f.stem
        ids = [w["id"] for w in (st.load(f"keyword/{f.stem}") or {}).get("workItems", [])]
        hits[term], hits_recent[term] = len(ids), sum(1 for i in ids if i in changed_ids)
    detail = {w["id"]: w for w in _v(st, "detail")}
    term_of = collections.defaultdict(list)
    for f in st.root.glob("keyword/*.json"):
        if not f.name.endswith(".meta.json"):
            for w in (st.load(f"keyword/{f.stem}") or {}).get("workItems", []):
                if w["id"] in detail:
                    term_of[w["id"]].append(f.stem.replace("_", " "))
    sync_comments = 0
    for i in detail:
        texts = [c.get("text", "") for c in (st.load(f"comments/{i}") or {}).get("comments", [])]
        sync_comments += any(SYNC_COMMENT.search(t) for t in texts)
    shortlist = [{"id": i, "type": w["fields"].get("System.WorkItemType"), "state": w["fields"].get("System.State"),
                  "changed": w["fields"].get("System.ChangedDate", "")[:10], "terms": ", ".join(sorted(term_of[i]))[:80],
                  "title": redact(w["fields"].get("System.Title", ""))[:100]}
                 for i, w in sorted(detail.items(), key=lambda x: x[1]["fields"].get("System.ChangedDate", ""), reverse=True)]
    in_flight = [{"id": i["WorkItemId"], "type": i["WorkItemType"], "state": i["State"], "priority": i.get("Priority"),
                  "changed": (i.get("ChangedDate") or "")[:10], "title": redact(i.get("Title"))[:100]}
                 for i in sorted(live, key=lambda x: x.get("ChangedDate") or "", reverse=True)
                 if i.get("StateCategory") in ("InProgress", "Resolved")]
    areas, iters = st.load("areas") or {}, st.load("iterations") or {}
    return {
        "window_start": since[:10],
        "items": rng.get("Count"), "first_created": (rng.get("First") or "")[:10], "last_changed": (rng.get("Last") or "")[:10],
        "created_by_year": {str(y): dict(c) for y, c in sorted(by_year.items(), key=lambda x: x[0] or 0)},
        "created_by_month": created_m, "closed_by_month": closed_m,
        "open_monthly": {str(r["DateSK"]): r["Count"] for r in sorted(_v(st, "open-monthly"), key=lambda r: r["DateSK"])},
        "type_state": [{"type": r["WorkItemType"], "state": r["State"], "category": r["StateCategory"], "count": r["Count"]}
                       for r in sorted(_v(st, "type-state"), key=lambda r: (r["WorkItemType"], r["State"]))],
        "open": len(open_items), "open_stale_two_years": len(open_items) - len(live),
        "live_queue_by_type": dict(collections.Counter(i["WorkItemType"] for i in live)),
        "live_queue_by_priority": dict(sorted(collections.Counter(str(i.get("Priority")) for i in live).items())),
        "changed_in_window": len(changed), "created_in_window": len(created_window),
        "creators": len(creators), "creator_counts": [c for _, c in creators.most_common()],
        "assignees": len({(i.get("AssignedTo") or {}).get("UserName") for i in changed if i.get("AssignedTo")}),
        "at_root_area": root_area, "at_root_iteration": root_iter,
        "area_nodes": _count_nodes(areas) if areas else None, "iteration_nodes": _count_nodes(iters) if iters else None,
        "teams": [t["name"] for t in _v(st, "teams")],
        "saved_queries": [c["name"] for q in _v(st, "saved-queries") if q.get("name") == "Shared Queries"
                          for c in q.get("children", [])],
        "sync_tagged": sync_tagged, "sync_comment_items": sync_comments, "detail_items": len(detail),
        "hotfix_tagged": sum(1 for i in changed if any(HOTFIX.search(t) for t in (i.get("TagNames") or "").split("; "))),
        "top_tags": [t for t, _ in tags.most_common(20) if not SYNC_TAG.match(t)],
        "linked_to_code": linked, "link_kinds": dict(links.most_common(12)),
        "keyword_hits": hits, "keyword_hits_in_window": hits_recent,
        "shortlist": shortlist, "in_flight": in_flight[:100],
    }


def render(m):
    out = [f"Window: items changed since {m['window_start']}.", "",
           "## Is the board live", "",
           md_table(["Measure", "Value"], [
               ["Work items", m["items"]], ["First created", m["first_created"]], ["Last changed", m["last_changed"]],
               ["Changed in window", m["changed_in_window"]], ["Created in window", m["created_in_window"]],
               ["Open", m["open"]], ["Open, unchanged for two years", m["open_stale_two_years"]]]),
           md_table(["Year", "Created", "By type"],
                    [[y, sum(c.values()), "; ".join(f"{k} {v}" for k, v in sorted(c.items()))] for y, c in m["created_by_year"].items()]),
           md_table(["Month", "Created", "Closed", "Open on the 1st"],
                    [[k, m["created_by_month"].get(k, 0), m["closed_by_month"].get(k, 0),
                      m["open_monthly"].get(k + "01", "")] for k in sorted(set(m["created_by_month"]) | set(m["closed_by_month"]))]),
           "## How it is used", "",
           md_table(["Measure", "Value"], [
               ["Area nodes / iteration nodes", f"{m['area_nodes']} / {m['iteration_nodes']}"],
               ["Changed items at the root area / root iteration", f"{m['at_root_area']} / {m['at_root_iteration']}"],
               ["Teams", ", ".join(m["teams"])],
               ["Shared queries", ", ".join(m["saved_queries"])],
               ["Changed items with an external-tracker tag", m["sync_tagged"]],
               ["Shortlisted items whose comments mention a sync", f"{m['sync_comment_items']} of {m['detail_items']}"],
               ["Hot-fix tagged", m["hotfix_tagged"]],
               ["Creators in window (items each)", f"{m['creators']} ({', '.join(map(str, m['creator_counts']))})"],
               ["Assignees in window", m["assignees"]],
               ["Changed items linked to commits, pull requests or builds", m["linked_to_code"]]]),
           "An external-tracker tag or sync comment means another system may be the system of record.", "",
           md_table(["Link kind", "Count"], sorted(m["link_kinds"].items(), key=lambda x: -x[1])),
           "Top tags: " + (", ".join(m["top_tags"]) or "none") + "", "",
           "## Type and state", "",
           md_table(["Type", "State", "Category", "Count"], [[r["type"], r["state"], r["category"], r["count"]] for r in m["type_state"]]),
           md_table(["Live queue by type", "Count"], sorted(m["live_queue_by_type"].items(), key=lambda x: -x[1])),
           md_table(["Live queue by priority", "Count"], sorted(m["live_queue_by_priority"].items())),
           "## In flight", "",
           md_table(["Id", "Type", "State", "Priority", "Changed", "Title"],
                    [[i["id"], i["type"], i["state"], i["priority"], i["changed"], i["title"]] for i in m["in_flight"]]),
           "## Keyword hits", "",
           md_table(["Term", "All items", "Changed in window"],
                    [[t, m["keyword_hits"][t], m["keyword_hits_in_window"][t]] for t in sorted(m["keyword_hits"])]),
           "## Shortlist: keyword hits changed in the window, detail fetched", "",
           "Read each item's description and comments in raw before judging it; titles alone miss the overlap.", "",
           md_table(["Id", "Type", "State", "Changed", "Terms", "Title"],
                    [[s["id"], s["type"], s["state"], s["changed"], s["terms"], s["title"]] for s in m["shortlist"]])]
    return "\n".join(out)
