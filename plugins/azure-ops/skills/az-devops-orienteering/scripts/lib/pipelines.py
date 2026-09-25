"""Pipelines: history actually held, deployments, approvals, agents, capacity, failure pairs."""
import collections
import re
import urllib.parse

from .core import md_table, redact

SCOPE = "project"
TITLE = "Pipelines: history, agents and capacity"
SOFTWARE_KEYS = re.compile(r"^(Agent\.(Version|OSVersion|ComputerName)|DotNetFramework(_[\d.]+)?|MSBuild(_[\d.]+)?|"
                           r"SqlPackage|VisualStudio(_[\d.]+)?|PowerShell|node(\.js)?|npm|java|sqlcmd|MSDeploy)$", re.I)
FAILED = ("failed", "partiallySucceeded")
PAIR_CAP_PER_STAGE = 5


def collect(ctx):
    h, st, p = ctx.hosts, ctx.store, urllib.parse.quote(ctx.project)
    a, sk, since = h.analytics(ctx.project), ctx.since_sk, ctx.since_iso
    st.odata("runs-by-pipeline", a, f"PipelineRuns?$apply=filter(CompletedDateSK ge {sk})/groupby((Pipeline/PipelineName,RunOutcome,RunReason),"
             "aggregate($count as Count,TotalDurationSeconds with average as AvgSeconds))")
    st.odata("runs-by-day", a, f"PipelineRuns?$apply=filter(CompletedDateSK ge {sk})/groupby((CompletedDateSK,Pipeline/PipelineName,RunOutcome),"
             "aggregate($count as Count))")
    st.odata("runs-range", a, "PipelineRuns?$apply=groupby((Pipeline/PipelineName),aggregate($count as Count,"
             "CompletedDate with min as First,CompletedDate with max as Last))")
    st.get("build-definitions", f"{h.core}/{p}/_apis/build/definitions?includeLatestBuilds=true&api-version=7.1")
    st.get_paged("builds", f"{h.core}/{p}/_apis/build/builds?minTime={since}&queryOrder=finishTimeDescending&$top=1000&api-version=7.1")
    st.get("release-definitions", f"{h.vsrm}/{p}/_apis/release/definitions?$expand=environments&api-version=7.1")
    deps = st.get_paged("deployments", f"{h.vsrm}/{p}/_apis/release/deployments?minStartedTime={since}&queryOrder=descending&$top=100&api-version=7.1") or []
    for status in ("approved", "rejected", "pending"):
        st.get_paged(f"approvals-{status}", f"{h.vsrm}/{p}/_apis/release/approvals?statusFilter={status}&typeFilter=preDeploy&$top=500&queryOrder=descending&api-version=7.1")
    envs = st.get("environments", f"{h.core}/{p}/_apis/distributedtask/environments?$top=100&api-version=7.1") or {}
    for e in envs.get("value", []):
        st.get(f"environment-checks/{e['id']}", f"{h.core}/{p}/_apis/pipelines/checks/configurations?resourceType=environment&resourceId={e['id']}&api-version=7.1-preview.1")
    pools = st.get("pools", f"{h.core}/_apis/distributedtask/pools?api-version=7.1") or {}
    for pool in pools.get("value", []):
        if not pool.get("isHosted"):
            st.get(f"pool-agents/{pool['id']}", f"{h.core}/_apis/distributedtask/pools/{pool['id']}/agents?includeCapabilities=true&includeLastCompletedRequest=true&api-version=7.1")
    dgs = st.get("deployment-groups", f"{h.core}/{p}/_apis/distributedtask/deploymentgroups?api-version=7.1") or {}
    for g in dgs.get("value", []):
        st.get(f"deployment-targets/{g['id']}", f"{h.core}/{p}/_apis/distributedtask/deploymentgroups/{g['id']}/targets?$expand=capabilities,lastCompletedRequest&api-version=7.1")
    st.get("secure-files", f"{h.core}/{p}/_apis/distributedtask/securefiles?api-version=7.1-preview.1")
    st.get("build-retention", f"{h.core}/{p}/_apis/build/retention?api-version=7.1")
    st.get("build-general-settings", f"{h.core}/{p}/_apis/build/generalsettings?api-version=7.1")
    st.get("release-settings", f"{h.vsrm}/{p}/_apis/release/releasesettings?api-version=7.1-preview.1")
    for tag, hosted in (("Private", "false"), ("Public", "true"), ("Private", "true")):
        st.get(f"resourceusage-{tag.lower()}-hosted-{hosted}", f"{h.core}/_apis/distributedtask/resourceusage?parallelismTag={tag}&poolIsHosted={hosted}&includeRunningRequests=false&api-version=7.1-preview.1")
    _collect_pairs(ctx, deps)


def _pairs(deps):
    """For each failed deployment, the next passing deployment of the same definition and stage."""
    by_stage = collections.defaultdict(list)
    for d in deps:
        by_stage[(d["releaseDefinition"]["id"], d["releaseEnvironment"]["name"])].append(d)
    pairs = []
    for items in by_stage.values():
        items.sort(key=lambda d: d.get("startedOn") or "")
        found = 0
        for i, d in enumerate(reversed(items)):
            if d.get("deploymentStatus") not in FAILED:
                continue
            idx = len(items) - 1 - i
            nxt = next((x for x in items[idx + 1:] if x.get("deploymentStatus") == "succeeded"), None)
            pairs.append((d, nxt))
            found += 1
            if found >= PAIR_CAP_PER_STAGE:
                break
    return pairs


def _collect_pairs(ctx, deps):
    h, st, p = ctx.hosts, ctx.store, urllib.parse.quote(ctx.project)
    releases = set()
    for f, s in _pairs(deps):
        releases.add(f["release"]["id"])
        if s:
            releases.add(s["release"]["id"])
    for rid in sorted(releases):
        st.get(f"release-detail/{rid}", f"{h.vsrm}/{p}/_apis/release/releases/{rid}?api-version=7.1")
    for f, s in _pairs(deps):
        for d, role in ((f, "failed"), (s, "passed")):
            if not d:
                continue
            for task, _phase in _stage_tasks(st, d):
                if role == "failed" and task.get("status") != "failed" and not _is_init(task):
                    continue
                if role == "passed" and not _is_init(task):
                    continue
                if task.get("logUrl"):
                    st.text(f"task-logs/{d['release']['id']}-{d['releaseEnvironment']['id']}-{task['id']}", task["logUrl"])
        if s:
            failing = {t["name"] for t, _ in _stage_tasks(st, f) if t.get("status") == "failed"}
            for task, _ in _stage_tasks(st, s):
                if task["name"] in failing and task.get("logUrl"):
                    st.text(f"task-logs/{s['release']['id']}-{s['releaseEnvironment']['id']}-{task['id']}", task["logUrl"])


def _is_init(task):
    return task.get("name") in ("Initialize job", "Initialize Agent")


def _stage_tasks(st, dep):
    rel = st.load(f"release-detail/{dep['release']['id']}") or {}
    for env in rel.get("environments", []):
        if env.get("id") != dep["releaseEnvironment"]["id"]:
            continue
        steps = env.get("deploySteps") or []
        step = next((s for s in steps if s.get("attempt") == dep.get("attempt")), steps[-1] if steps else None)
        for phase in (step or {}).get("releaseDeployPhases", []):
            for job in phase.get("deploymentJobs", []):
                for t in job.get("tasks", []):
                    t = dict(t)
                    t["_agent"] = job.get("job", {}).get("agentName")
                    yield t, phase.get("name")


def _agent_version(st, dep):
    for t, _ in _stage_tasks(st, dep):
        if _is_init(t):
            log = st.root / f"task-logs/{dep['release']['id']}-{dep['releaseEnvironment']['id']}-{t['id']}.log"
            if log.exists():
                m = re.search(r"Current agent version: '([^']+)'", log.read_text())
                if m:
                    return m.group(1)
    return None


def _failure_row(st, f, s):
    rel = st.load(f"release-detail/{f['release']['id']}") or {}
    failed = [(t, ph) for t, ph in _stage_tasks(st, f) if t.get("status") == "failed"]
    t, ph = failed[0] if failed else ({}, None)
    err = redact("; ".join(i.get("message", "") for i in t.get("issues") or [])).splitlines()
    row = {"release": rel.get("name") or f["release"]["name"], "stage": f["releaseEnvironment"]["name"],
           "started": (f.get("startedOn") or "")[:16], "status": f["deploymentStatus"], "phase": ph,
           "task": t.get("name"), "task_version": (t.get("task") or {}).get("version"), "agent": t.get("_agent"),
           "agent_version": _agent_version(st, f), "revision": rel.get("releaseDefinitionRevision"),
           "error": (err[0] if err else "")[:160], "next_pass": None, "identical": None}
    if s:
        srel = st.load(f"release-detail/{s['release']['id']}") or {}
        same = [x for x, _ in _stage_tasks(st, s) if x.get("name") == t.get("name")]
        stask = same[0] if same else {}
        row["next_pass"] = srel.get("name") or s["release"]["name"]
        row["identical"] = all([
            srel.get("releaseDefinitionRevision") == row["revision"],
            stask.get("_agent") == row["agent"],
            (stask.get("task") or {}).get("version") == row["task_version"],
            _agent_version(st, s) == row["agent_version"],
        ])
    return row


def analyse(ctx):
    st = ctx.store
    runs = (st.load("runs-by-pipeline") or {}).get("value", [])
    per = collections.defaultdict(lambda: collections.Counter())
    dur = collections.defaultdict(float)
    for r in runs:
        name = (r.get("Pipeline") or {}).get("PipelineName") or "(unnamed: deleted pipeline)"
        per[name]["runs"] += r["Count"]
        per[name][f"outcome:{r['RunOutcome']}"] += r["Count"]
        per[name][f"reason:{r['RunReason']}"] += r["Count"]
        dur[name] += (r.get("AvgSeconds") or 0) * r["Count"]
    build_rows = [{"pipeline": n, "runs": c["runs"], "failed": c["outcome:Failed"],
                   "scheduled": c["reason:Schedule"], "commit": c["reason:IndividualCI"] + c["reason:BatchedCI"],
                   "manual": c["reason:Manual"], "mean_seconds": round(dur[n] / c["runs"]) if c["runs"] else None}
                  for n, c in sorted(per.items())]
    ranges = [{"pipeline": (r.get("Pipeline") or {}).get("PipelineName") or "(unnamed: deleted pipeline)",
               "runs": r["Count"], "first": (r.get("First") or "")[:10] or None, "last": (r.get("Last") or "")[:10] or None}
              for r in (st.load("runs-range") or {}).get("value", [])]
    fails_by_month = collections.Counter()
    for r in (st.load("runs-by-day") or {}).get("value", []):
        if r["RunOutcome"] == "Failed":
            fails_by_month[(str(r["CompletedDateSK"])[:6], (r.get("Pipeline") or {}).get("PipelineName"))] += r["Count"]

    builds = (st.load("builds") or {}).get("value", [])
    defs = (st.load("build-definitions") or {}).get("value", [])
    def_rows = [{"name": d["name"], "path": d.get("path"), "status": d.get("queueStatus"),
                 "repo_type": (d.get("repository") or {}).get("type"), "created": (d.get("createdDate") or "")[:10],
                 "latest": ((d.get("latestBuild") or {}).get("finishTime") or "")[:10] or None} for d in defs]

    deps = (st.load("deployments") or {}).get("value", [])
    stage = collections.defaultdict(lambda: collections.Counter())
    stage_dates = collections.defaultdict(set)
    for d in deps:
        k = (d["releaseDefinition"]["name"], d["releaseEnvironment"]["name"])
        stage[k][d["deploymentStatus"]] += 1
        stage[k][f"reason:{d.get('reason')}"] += 1
        stage_dates[k].add((d.get("startedOn") or "")[:10])
    dep_rows = [{"definition": k[0], "stage": k[1], "total": sum(v for x, v in c.items() if not x.startswith("reason:")),
                 "succeeded": c["succeeded"], "partly": c["partiallySucceeded"], "failed": c["failed"],
                 "automated": c["reason:automated"], "manual": c["reason:manual"], "days": len(stage_dates[k])}
                for k, c in sorted(stage.items())]
    appr = collections.defaultdict(lambda: {"automated": 0, "manual": 0, "approvers": set()})
    for a in (st.load("approvals-approved") or {}).get("value", []):
        k = (a.get("releaseDefinition", {}).get("name"), a.get("releaseEnvironment", {}).get("name"))
        if a.get("isAutomated"):
            appr[k]["automated"] += 1
        else:
            appr[k]["manual"] += 1
            appr[k]["approvers"].add((a.get("approvedBy") or a.get("approver") or {}).get("uniqueName"))
    appr_rows = [{"definition": k[0], "stage": k[1], "automated": v["automated"], "manual": v["manual"],
                  "approvers": len(v["approvers"])} for k, v in sorted(appr.items(), key=lambda x: str(x[0]))]

    pairs = [_failure_row(st, f, s) for f, s in _pairs(deps)]

    agents = []
    for f in sorted(st.root.glob("deployment-targets/*.json")) + sorted(st.root.glob("pool-agents/*.json")):
        if f.name.endswith(".meta.json"):
            continue
        group = f.parent.name + "/" + f.stem
        for item in (st.load(f"{f.parent.name}/{f.stem}") or {}).get("value", []):
            ag = item.get("agent", item)
            caps = ag.get("systemCapabilities") or {}
            agents.append({"agent": ag.get("name"), "where": group, "machine": caps.get("Agent.ComputerName"),
                           "version": ag.get("version"), "status": ag.get("status"),
                           "os": (ag.get("osDescription") or "")[:40],
                           "last_job": ((ag.get("lastCompletedRequest") or {}).get("finishTime") or "")[:10] or None,
                           "software": {k: v for k, v in caps.items() if SOFTWARE_KEYS.match(k)
                                        and not re.search(r"[;=]", str(v))}})
    machines = collections.Counter(a["machine"] for a in agents if a["machine"] and a["status"] == "online")

    ret = st.load("build-retention") or {}
    rel_ret = (st.load("release-settings") or {}).get("retentionSettings", {})
    usage = {}
    for f in sorted(st.root.glob("resourceusage-*.json")):
        if not f.name.endswith(".meta.json"):
            lim = (st.load(f.stem) or {}).get("resourceLimit") or {}
            usage[f.stem.replace("resourceusage-", "")] = lim.get("totalCount")
    general = st.load("build-general-settings") or {}
    held = {"builds_rest_from": min((b.get("finishTime") or "9") for b in builds)[:10] if builds else None,
            "deployments_from": min((d.get("startedOn") or "9") for d in deps)[:10] if deps else None,
            "analytics_from": min((r["first"] for r in ranges if r["first"]), default=None)}
    return {
        "window_start": ctx.since_iso[:10],
        "held": held,
        "retention": {"build_runs_days": (ret.get("purgeRuns") or {}).get("value"),
                      "build_artifacts_days": (ret.get("purgeArtifacts") or {}).get("value"),
                      "release_days": (rel_ret.get("defaultEnvironmentRetentionPolicy") or {}).get("daysToKeep"),
                      "release_count": (rel_ret.get("defaultEnvironmentRetentionPolicy") or {}).get("releasesToKeep"),
                      "credential_scan": ((st.load("release-settings") or {}).get("complianceSettings") or {}).get("checkForCredentialsAndOtherSecrets")},
        "analytics_ranges": ranges,
        "builds_by_pipeline": build_rows,
        "build_failures_by_month": [{"month": k[0], "pipeline": k[1], "failed": v} for k, v in sorted(fails_by_month.items())],
        "branches_built": dict(collections.Counter(b.get("sourceBranch") for b in builds).most_common(10)),
        "build_requesters": [c for _, c in collections.Counter((b.get("requestedFor") or {}).get("uniqueName") for b in builds).most_common()],
        "build_definitions": def_rows,
        "deployments_by_stage": dep_rows,
        "approvals_by_stage": appr_rows,
        "failure_pairs": pairs,
        "agents": sorted(agents, key=lambda a: (a["status"] != "online", a["machine"] or "", a["agent"] or "")),
        "machines_with_several_online_agents": sorted(m for m, n in machines.items() if n > 1),
        "offline_agents": sum(1 for a in agents if a["status"] != "online"),
        "parallel_jobs": usage,
        "yaml_environments": len((st.load("environments") or {}).get("value", [])),
        "secure_files": len((st.load("secure-files") or {}).get("value", [])),
        "classic_creation_disabled": general.get("disableClassicPipelineCreation"),
    }


def render(m):
    h, r = m["held"], m["retention"]
    online = [a for a in m["agents"] if a["status"] == "online"]
    soft_keys = sorted({k for a in online for k in a["software"]})
    out = [f"Window requested: since {m['window_start']}.", "",
           "## History actually held", "",
           "Every count below covers only what these sources still hold. State the window beside any number.", "",
           md_table(["Source", "Held from"], [["Build records (REST)", h["builds_rest_from"]],
                                              ["Release deployments (REST)", h["deployments_from"]],
                                              ["Pipeline runs (Analytics)", h["analytics_from"]]]),
           md_table(["Retention setting", "Value"], [["Build runs kept, days", r["build_runs_days"]],
                                                     ["Build artifacts kept, days", r["build_artifacts_days"]],
                                                     ["Releases kept by default, days", r["release_days"]],
                                                     ["Releases kept by default, count", r["release_count"]],
                                                     ["Credential scan on release definitions", r["credential_scan"]]]),
           md_table(["Pipeline (Analytics)", "Runs", "First", "Last"],
                    [[x["pipeline"], x["runs"], x["first"], x["last"]] for x in m["analytics_ranges"]]),
           "## Build runs", "",
           md_table(["Pipeline", "Runs", "Failed", "Scheduled", "Commit-triggered", "Manual", "Mean seconds"],
                    [[b["pipeline"], b["runs"], b["failed"], b["scheduled"], b["commit"], b["manual"], b["mean_seconds"]]
                     for b in m["builds_by_pipeline"]]),
           md_table(["Month", "Pipeline", "Failed runs"], [[f["month"], f["pipeline"], f["failed"]] for f in m["build_failures_by_month"]]),
           md_table(["Branch built (REST records)", "Builds"], sorted(m["branches_built"].items(), key=lambda x: -x[1])),
           f"Build requesters: {len(m['build_requesters'])} (builds each: {', '.join(map(str, m['build_requesters']))}).", "",
           md_table(["Definition", "Folder", "Status", "Repository type", "Created", "Latest build"],
                    [[d["name"], d["path"], d["status"], d["repo_type"], d["created"], d["latest"]] for d in m["build_definitions"]]),
           "## Deployments", "",
           md_table(["Release definition", "Stage", "Total", "Succeeded", "Partly", "Failed", "Automated", "Manual", "Days deployed"],
                    [[d["definition"], d["stage"], d["total"], d["succeeded"], d["partly"], d["failed"], d["automated"],
                      d["manual"], d["days"]] for d in m["deployments_by_stage"]]),
           md_table(["Release definition", "Stage", "Automatic approvals", "Manual approvals", "Distinct approvers"],
                    [[a["definition"], a["stage"], a["automated"], a["manual"], a["approvers"]] for a in m["approvals_by_stage"]]),
           "## Failed deployments and the next pass", "",
           "`Identical` compares definition revision, agent, agent version and task version with the next passing "
           "deployment of the same stage. Identical means the change that fixed it lies outside Azure DevOps.", "",
           md_table(["Release", "Stage", "Started", "Status", "Phase", "Task", "Task version", "Agent", "Agent version",
                     "Revision", "Error", "Next pass", "Identical"],
                    [[p["release"], p["stage"], p["started"], p["status"], p["phase"], p["task"], p["task_version"],
                      p["agent"], p["agent_version"], p["revision"], p["error"], p["next_pass"],
                      "" if p["identical"] is None else ("yes" if p["identical"] else "no")] for p in m["failure_pairs"]]),
           "## Agents", "",
           f"Offline registrations: {m['offline_agents']}. Machines with more than one online agent: "
           f"{', '.join(m['machines_with_several_online_agents']) or 'none'}.", "",
           md_table(["Agent", "Group or pool", "Machine", "Version", "Status", "OS", "Last job"],
                    [[a["agent"], a["where"], a["machine"], a["version"], a["status"], a["os"], a["last_job"]] for a in m["agents"]]),
           "Software reported by online agents (capability keys; environment variables are never reported):", "",
           md_table(["Capability"] + [a["agent"] for a in online],
                    [[k] + [str(a["software"].get(k, ""))[-60:] for a in online] for k in soft_keys]),
           "## Capacity and settings", "",
           md_table(["Parallelism", "Total count"], sorted(m["parallel_jobs"].items())),
           f"YAML environments: {m['yaml_environments']}. Secure files: {m['secure_files']}. "
           f"Classic pipeline creation disabled: {m['classic_creation_disabled']}.", ""]
    return "\n".join(out)
