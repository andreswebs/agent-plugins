"""Repositories: how change reaches each branch, and what protects it."""
import collections
import statistics
import urllib.parse

from .core import ZERO_ID, days_between, md_table, percentile, redact

SCOPE = "project"
TITLE = "Repositories: review, branches and history"
MIN_REVIEWERS = "Minimum number of reviewers"


def collect(ctx):
    h, st, p = ctx.hosts, ctx.store, urllib.parse.quote(ctx.project)
    git = f"{h.core}/{p}/_apis/git"
    repos = (st.get("repositories", f"{git}/repositories?includeHidden=true&api-version=7.1") or {}).get("value", [])
    for r in repos:
        rid, n = r["id"], r["name"]
        st.get_skip(f"pullrequests/{n}", f"{git}/repositories/{rid}/pullrequests?searchCriteria.status=all&api-version=7.1")
        st.get(f"refs/{n}", f"{git}/repositories/{rid}/refs?peelTags=true&api-version=7.1")
        st.get(f"branch-stats/{n}", f"{git}/repositories/{rid}/stats/branches?api-version=7.1")
        st.get_skip(f"pushes/{n}", f"{git}/repositories/{rid}/pushes?searchCriteria.includeRefUpdates=true&api-version=7.1", page=1000)
    st.get("policy-configurations", f"{h.core}/{p}/_apis/policy/configurations?api-version=7.1")
    st.get_paged("builds", f"{h.core}/{p}/_apis/build/builds?minTime={ctx.since_iso}&queryOrder=finishTimeDescending&$top=1000&api-version=7.1")
    st.get("tfvc-root", f"{h.core}/{p}/_apis/tfvc/items?scopePath=$/&recursionLevel=OneLevel&api-version=7.1")
    st.get("tfvc-changesets", f"{h.core}/{p}/_apis/tfvc/changesets?$top=5&api-version=7.1")
    st.get("recycle-bin", f"{git}/recycleBin/repositories?api-version=7.1-preview.1")


def _covers(scope, repo_id, default_ref, ref):
    if scope.get("repositoryId") not in (None, repo_id):
        return False
    kind = scope.get("matchKind", "Exact")
    if kind == "DefaultBranch":
        return ref == default_ref
    target = scope.get("refName")
    if target is None:
        return True
    return ref == target if kind == "Exact" else ref.startswith(target)


def _scope_text(scope, names):
    repo = names.get(scope.get("repositoryId"), "every repository") if scope.get("repositoryId") else "every repository"
    kind = scope.get("matchKind", "Exact")
    if kind == "DefaultBranch":
        return f"default branch of {repo}"
    ref = scope.get("refName")
    if ref is None:
        return f"all branches of {repo}"
    return f"{'branches under ' if kind == 'Prefix' else ''}{ref.replace('refs/heads/', '')} in {repo}"


def _approved_by_other(pr):
    author = pr["createdBy"].get("uniqueName")
    return any(r.get("vote", 0) >= 5 and not r.get("isContainer") and r.get("uniqueName") != author
               for r in pr.get("reviewers") or [])


def _approved_by_author_only(pr):
    author = pr["createdBy"].get("uniqueName")
    votes = [r for r in pr.get("reviewers") or [] if r.get("vote", 0) >= 5]
    return bool(votes) and all(r.get("uniqueName") == author for r in votes)


def analyse(ctx):
    st, since = ctx.store, ctx.since_iso
    repos = (st.load("repositories") or {}).get("value", [])
    names = {r["id"]: r["name"] for r in repos}
    policies = [pc for pc in (st.load("policy-configurations") or {}).get("value", []) if pc.get("isEnabled")]
    reviewer_scopes = [(s, pc) for pc in policies if pc["type"]["displayName"] == MIN_REVIEWERS and pc.get("isBlocking")
                       for s in pc["settings"].get("scope", [])]
    builds = (st.load("builds") or {}).get("value", [])
    built = collections.Counter((b["repository"]["id"], b.get("sourceBranch")) for b in builds if b.get("repository"))

    policy_rows = [{"type": pc["type"]["displayName"], "blocking": pc.get("isBlocking"),
                    "scope": "; ".join(_scope_text(s, names) for s in pc["settings"].get("scope", [])) or "project",
                    "approvers": pc["settings"].get("minimumApproverCount"),
                    "creator_counts": pc["settings"].get("creatorVoteCounts")} for pc in policies]

    repo_rows, branch_rows, all_prs, divergence = [], [], [], []
    authors, approvers = collections.Counter(), collections.Counter()
    bypass_reasons = collections.Counter()
    for r in repos:
        n, rid, default = r["name"], r["id"], r.get("defaultBranch")
        prs = (st.load(f"pullrequests/{n}") or {}).get("value", [])
        pushes = (st.load(f"pushes/{n}") or {}).get("value", [])
        merge_ids = {p["lastMergeCommit"]["commitId"] for p in prs
                     if p.get("status") == "completed" and p.get("lastMergeCommit")}
        dates = [p["date"] for p in pushes]
        repo_rows.append({"repo": n, "size": r.get("size"), "disabled": r.get("isDisabled"),
                          "default": (default or "").replace("refs/heads/", ""),
                          "pushes_held": len(pushes), "first_push": min(dates)[:10] if dates else None,
                          "last_push": max(dates)[:10] if dates else None})
        window = [p for p in prs if p.get("status") == "completed" and (p.get("closedDate") or "") >= since]
        all_prs += window
        per = collections.defaultdict(lambda: collections.Counter())
        for p in window:
            ref = p["targetRefName"]
            c = per[ref]
            c["completed"] += 1
            c["independent"] += _approved_by_other(p)
            c["author_only"] += _approved_by_author_only(p)
            c["no_approval"] += not any(v.get("vote", 0) >= 5 for v in p.get("reviewers") or [])
            bypass = bool((p.get("completionOptions") or {}).get("bypassPolicy"))
            c["bypass"] += bypass
            if bypass:
                bypass_reasons[redact((p["completionOptions"].get("bypassReason") or "").strip().lower())[:60]] += 1
            authors[p["createdBy"].get("uniqueName")] += 1
            for v in p.get("reviewers") or []:
                if v.get("vote", 0) >= 5 and not v.get("isContainer") and v.get("uniqueName") != p["createdBy"].get("uniqueName"):
                    approvers[v.get("uniqueName")] += 1
        for push in pushes:
            if push["date"] < since:
                continue
            for u in push.get("refUpdates") or []:
                if not u["name"].startswith("refs/heads/") or u.get("newObjectId") == ZERO_ID:
                    continue
                c = per[u["name"]]
                c["pushes"] += 1
                if u["newObjectId"] not in merge_ids:
                    c["direct"] += 1
        for ref, _ in built.items():
            if ref[0] == rid:
                per[ref[1]]["builds"] += built[ref]
        for ref, c in per.items():
            covered = any(_covers(s, rid, default, ref) for s, _ in reviewer_scopes)
            branch_rows.append({"repo": n, "branch": ref.replace("refs/heads/", ""), "default": ref == default,
                                "review_policy": covered, **{k: c.get(k, 0) for k in
                                ("completed", "independent", "author_only", "no_approval", "bypass",
                                 "pushes", "direct", "builds")}})
        stats = (st.load(f"branch-stats/{n}") or {}).get("value", [])
        for b in stats:
            ref = "refs/heads/" + b["name"]
            if ref != default and (per.get(ref, {}).get("builds") or per.get(ref, {}).get("completed")):
                divergence.append({"repo": n, "branch": b["name"], "ahead": b.get("aheadCount"),
                                   "behind": b.get("behindCount"), "last_commit": (b.get("commit", {}).get("committer", {}).get("date") or "")[:10]})
        stale = sum(1 for b in stats if (b.get("commit", {}).get("committer", {}).get("date") or "") < since)
        repo_rows[-1].update({"branches": len(stats), "branches_stale": stale,
                              "tags": sum(1 for x in (st.load(f"refs/{n}") or {}).get("value", []) if x["name"].startswith("refs/tags/"))})

    merge_days = [days_between(p["creationDate"], p["closedDate"]) for p in all_prs]
    tfvc = (st.load("tfvc-changesets") or {}).get("value", [])
    return {
        "window_start": since[:10],
        "repositories": repo_rows,
        "policies": policy_rows,
        "branches": sorted(branch_rows, key=lambda r: (r["repo"], -r["builds"], -r["completed"])),
        "unprotected_built_branches": [f"{r['repo']}:{r['branch']}" for r in branch_rows if r["builds"] and not r["review_policy"]],
        "prs_completed": len(all_prs),
        "prs_independent": sum(_approved_by_other(p) for p in all_prs),
        "prs_author_only": sum(_approved_by_author_only(p) for p in all_prs),
        "prs_no_approval": sum(1 for p in all_prs if not any(v.get("vote", 0) >= 5 for v in p.get("reviewers") or [])),
        "prs_bypass": sum(1 for p in all_prs if (p.get("completionOptions") or {}).get("bypassPolicy")),
        "bypass_reasons": dict(bypass_reasons.most_common(10)),
        "authors": len(authors), "authors_top_share": [c for _, c in authors.most_common()],
        "approvers": len(approvers), "approvals_by_approver": [c for _, c in approvers.most_common()],
        "merge_days_median": round(statistics.median(merge_days), 2) if merge_days else None,
        "merge_days_p90": round(percentile(merge_days, 0.9), 2) if merge_days else None,
        "divergence": divergence,
        "tfvc_present": bool((st.load("tfvc-root") or {}).get("value")) and len((st.load("tfvc-root") or {}).get("value")) > 1,
        "tfvc_latest": {"id": tfvc[0]["changesetId"], "date": tfvc[0]["createdDate"][:10]} if tfvc else None,
        "recycle_bin_status": st.status("recycle-bin"),
    }


def render(m):
    def yes(b):
        return "yes" if b else "no"
    out = [f"Window: completed pull requests and pushes since {m['window_start']}.", "",
           "## Repositories", "",
           "`Pushes held from` shows paging reached the start of history.", "",
           md_table(["Repository", "Default", "Disabled", "Size", "Pushes held", "Pushes held from", "Last push",
                     "Branches", "Without a commit in window", "Tags"],
                    [[r["repo"], r["default"], yes(r["disabled"]), r["size"], r["pushes_held"], r["first_push"],
                      r["last_push"], r["branches"], r["branches_stale"], r["tags"]] for r in m["repositories"]]),
           "## Branch policies", "",
           "Scope is resolved from `matchKind`: a scope with no branch can mean each repository's default branch only.", "",
           md_table(["Policy", "Blocking", "Scope", "Approvers", "Author's vote counts"],
                    [[p["type"], yes(p["blocking"]), p["scope"], p["approvers"], p["creator_counts"]] for p in m["policies"]]),
           "## Change reaching each active branch", "",
           "Approval means a vote of approve or approve-with-suggestions from someone other than the author. "
           "Direct means a push whose commit is no completed pull request's merge commit.", "",
           md_table(["Repository", "Branch", "Default", "Blocking review policy", "Builds", "PRs completed",
                     "Approved by another", "Author only", "No approval", "Bypass", "Pushes", "Direct"],
                    [[r["repo"], r["branch"], yes(r["default"]), yes(r["review_policy"]), r["builds"], r["completed"],
                      r["independent"], r["author_only"], r["no_approval"], r["bypass"], r["pushes"], r["direct"]]
                     for r in m["branches"]]),
           f"Built branches with no blocking review policy: {', '.join(m['unprotected_built_branches']) or 'none'}.", "",
           "## Pull requests in the window", "",
           md_table(["Measure", "Value"], [
               ["Completed", m["prs_completed"]], ["Approved by another", m["prs_independent"]],
               ["Approved by author only", m["prs_author_only"]], ["No approving vote", m["prs_no_approval"]],
               ["Completed with policy bypass", m["prs_bypass"]],
               ["Authors", f"{m['authors']} (pull requests each: {', '.join(map(str, m['authors_top_share']))})"],
               ["Approvers other than the author", f"{m['approvers']} (approvals each: {', '.join(map(str, m['approvals_by_approver']))})"],
               ["Days open to merge, median / 90th percentile", f"{m['merge_days_median']} / {m['merge_days_p90']}"]]),
           md_table(["Bypass reason", "Count"], sorted(m["bypass_reasons"].items(), key=lambda x: -x[1])),
           "## Divergence from the default branch", "",
           md_table(["Repository", "Branch", "Ahead", "Behind", "Last commit"],
                    [[d["repo"], d["branch"], d["ahead"], d["behind"], d["last_commit"]] for d in m["divergence"]]),
           "## TFVC and deleted repositories", "",
           f"TFVC history present: {yes(m['tfvc_present'])}"
           + (f"; latest changeset {m['tfvc_latest']['id']} on {m['tfvc_latest']['date']}." if m["tfvc_latest"] else "."),
           f"Repository recycle bin: status {m['recycle_bin_status']}.", ""]
    return "\n".join(out)
