#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Read-only orienteering sweep of an Azure DevOps organisation and its projects.

Usage:
  az-devops-discovery.py --organization URL [--project NAME ...] [options]

Writes raw/<scope>/<module>/*.json (+ .meta.json), reports/<scope>/<module>.md
and .json, and summary.md under the output directory. Exit 0 when every module
completed; 1 when any module failed (the others are still valid); 2 on usage
errors.
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import traceback
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib import access, boards, core, org, pipelines, repos, wiki  # noqa: E402

MODULES = [access, org, repos, pipelines, boards, wiki]
NAMES = {m.__name__.split(".")[-1]: m for m in MODULES}


class Ctx:
    def __init__(self, **kw):
        self.__dict__.update(kw)


def project_root():
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return Path(out.stdout.strip()) if out.returncode == 0 else Path.cwd()


def parse(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--organization", "--org", default=os.environ.get("AZURE_DEVOPS_ORG"),
                    help="https://dev.azure.com/ORG or https://ORG.visualstudio.com (default AZURE_DEVOPS_ORG)")
    ap.add_argument("--project", "-p", action="append", default=[],
                    help="project to sweep; repeatable; default every project the caller can read")
    ap.add_argument("--output-dir", "-o", help="default .local/tmp/az-devops-discovery/ORG/ at the project root")
    ap.add_argument("--only", help="comma-separated modules; access always runs")
    ap.add_argument("--skip", help="comma-separated modules to skip")
    ap.add_argument("--since", type=int, default=365, help="window in days for history (default 365)")
    ap.add_argument("--keywords", help="file of extra Boards search terms, one per line")
    ap.add_argument("--detail-cap", type=int, default=200, help="most keyword hits to fetch in full (default 200)")
    ap.add_argument("--tenant", help="tenant for the az token request")
    ap.add_argument("--timeout", type=int, default=60, help="seconds per request (default 60)")
    ap.add_argument("--resume", action="store_true", help="keep captures already saved with status 200")
    ap.add_argument("--render-only", action="store_true", help="rebuild reports from raw; no network")
    ap.add_argument("--list", action="store_true", help="print modules in run order and exit")
    return ap.parse_args(argv)


def main(argv):
    args = parse(argv)
    if args.list:
        for m in MODULES:
            print(f"{m.__name__.split('.')[-1]:10} {m.SCOPE:8} {m.TITLE}")
        return 0
    if not args.organization:
        print("--organization is required (or set AZURE_DEVOPS_ORG)", file=sys.stderr)
        return 2
    orgname = core.org_name_from_url(args.organization)
    out = Path(args.output_dir) if args.output_dir else project_root() / ".local/tmp/az-devops-discovery" / orgname
    selected = [m for m in MODULES]
    if args.only:
        want = set(args.only.split(",")) | {"access"}
        unknown = want - NAMES.keys()
        if unknown:
            print(f"unknown modules: {', '.join(sorted(unknown))}", file=sys.stderr)
            return 2
        selected = [m for m in MODULES if m.__name__.split(".")[-1] in want]
    if args.skip:
        skip = set(args.skip.split(",")) - {"access"}
        selected = [m for m in selected if m.__name__.split(".")[-1] not in skip]

    hosts = core.Hosts(orgname)
    auth = core.Auth(args.tenant)
    session = core.Session(auth, args.timeout)
    today = dt.date.today()
    since = today - dt.timedelta(days=args.since)
    base = dict(args=args, hosts=hosts, auth=auth, today=today,
                since_iso=f"{since}T00:00:00Z", since_sk=since.strftime("%Y%m%d"))

    projects = args.project
    if not projects:
        if args.render_only:
            projects = sorted(p.name for p in (out / "raw").iterdir() if p.is_dir() and p.name != "_org") \
                if (out / "raw").exists() else []
        else:
            status, payload, _ = session.request(f"{hosts.core}/_apis/projects?stateFilter=wellFormed&$top=500&api-version=7.1")
            if status != 200:
                print(f"cannot list projects (status {status}); pass --project", file=sys.stderr)
                return 1
            projects = sorted(p["name"] for p in payload.get("value", []))
    base["projects"] = projects

    started = dt.datetime.now(dt.timezone.utc)
    results = []
    for m in selected:
        name = m.__name__.split(".")[-1]
        scopes = ["_org"] if m.SCOPE == "org" else projects
        for scope in scopes:
            store = core.Store(session, out / "raw" / scope / name, args.resume or args.render_only)
            ctx = Ctx(store=store, project=None if scope == "_org" else scope, **base)
            try:
                if not args.render_only:
                    store.reset()
                    core.log(f"== {name} [{scope}]")
                    m.collect(ctx)
                metrics = m.analyse(ctx)
                rep = out / "reports" / scope
                rep.mkdir(parents=True, exist_ok=True)
                header = f"# {m.TITLE}: {orgname}" + ("" if scope == "_org" else f" / {scope}")
                (rep / f"{name}.md").write_text(f"{header}\n\nGenerated {dt.datetime.now(dt.timezone.utc):%Y-%m-%d %H:%M} UTC.\n\n"
                                                + m.render(metrics))
                (rep / f"{name}.json").write_text(json.dumps(metrics, indent=1, sort_keys=True, default=str))
                results.append((name, scope, "completed", store.failures()))
            except Exception as e:  # a failed module is reported, not fatal
                traceback.print_exc()
                results.append((name, scope, f"failed: {type(e).__name__}: {e}", store.failures() if store.root.exists() else []))

    write_summary(out, orgname, projects, results, started, args)
    failed = [r for r in results if r[2] != "completed"]
    for r in failed:
        print(f"module failed: {r[0]} [{r[1]}] {r[2]}", file=sys.stderr)
    print(out / "summary.md")
    return 1 if failed else 0


def write_summary(out, orgname, projects, results, started, args):
    access_m = out / "reports" / "_org" / "access.json"
    caller = json.loads(access_m.read_text()).get("caller") if access_m.exists() else None
    done = sum(1 for r in results if r[2] == "completed")
    filt = f" (filtered: only={args.only or '-'} skip={args.skip or '-'})" if args.only or args.skip else ""
    lines = [f"# Azure DevOps orienteering: {orgname}", "",
             f"Generated {dt.datetime.now(dt.timezone.utc):%Y-%m-%d %H:%M} UTC; sweep started {started:%Y-%m-%d %H:%M} UTC.",
             f"Caller: `{caller}`. Projects swept: {', '.join(projects) or 'none'}. Window: {args.since} days.",
             f"Modules completed {done} of {len(results)}{filt}.", "",
             "## Reports", ""]
    lines.append(core.md_table(["Module", "Scope", "Result", "Report"],
                               [[n, s, st, f"[reports/{s}/{n}.md](reports/{urllib.parse.quote(s)}/{n}.md)"] for n, s, st, _ in results]))
    lines += ["## Could not read", "",
              "Each row is a permissions or availability fact about the caller, not an empty resource.", ""]
    lines.append(core.md_table(["Module", "Scope", "Capture", "Status", "Message"],
                               [[n, s, c, code, msg] for n, s, _, fails in results for c, code, msg in fails]))
    (out / "summary.md").write_text("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
