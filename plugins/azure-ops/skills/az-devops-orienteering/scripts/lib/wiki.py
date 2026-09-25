"""Wiki: whether written documentation exists, and what it covers. Page trees only, never content."""
import urllib.parse

from .core import md_table

SCOPE = "project"
TITLE = "Wiki"


def collect(ctx):
    h, st, p = ctx.hosts, ctx.store, urllib.parse.quote(ctx.project)
    wikis = (st.get("wikis", f"{h.core}/{p}/_apis/wiki/wikis?api-version=7.1") or {}).get("value", [])
    for w in wikis:
        st.get(f"pages/{w['name']}", f"{h.core}/{p}/_apis/wiki/wikis/{w['id']}/pages?path=/&recursionLevel=full&api-version=7.1")


def _paths(node):
    yield node.get("path")
    for c in node.get("subPages") or []:
        yield from _paths(c)


def analyse(ctx):
    rows = []
    for w in (ctx.store.load("wikis") or {}).get("value", []):
        tree = ctx.store.load(f"pages/{w['name']}") or {}
        paths = [x for x in _paths(tree) if x and x != "/"] if tree else []
        top = sorted({x.split("/")[1] for x in paths if x.count("/") >= 1 and len(x.split("/")) > 1})
        rows.append({"wiki": w["name"], "type": w.get("type"), "pages": len(paths), "top_level": top[:30],
                     "tree_status": ctx.store.status(f"pages/{w['name']}")})
    return {"wikis": rows}


def render(m):
    if not m["wikis"]:
        return "No wiki exists in this project.\n"
    return md_table(["Wiki", "Type", "Pages", "Top-level sections", "Tree status"],
                    [[w["wiki"], w["type"], w["pages"], ", ".join(w["top_level"]), w["tree_status"]] for w in m["wikis"]])
