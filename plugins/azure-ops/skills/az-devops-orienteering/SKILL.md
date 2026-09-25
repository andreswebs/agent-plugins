---
name: az-devops-orienteering
description: Orienteer an Azure DevOps organisation you did not build. Use when asked to discover, inventory or assess an inherited Azure DevOps organisation or project, covering its repositories and review controls, pipelines and deployment history, boards and in-flight work, and its people, administrators and hidden projects; when navigating an earlier Azure DevOps sweep's reports; or when asked what access an Azure DevOps sweep needs, or how to sign in to one separately from Azure. The sweep is read-only; needs az CLI and uv.
metadata:
  argument-hint: "[organization URL] [--project NAME ...] [--only module,...]"
---

# Azure DevOps orienteering

Orienteering: a map good enough to prioritise with, before any depth. The
sweep builds the map from what the caller can read; the reading guide turns it
into ranked findings. Every call is a read. Script paths below are relative to
this skill's directory.

## Steps

1. **Aim.** Resolve the organisation URL (the argument, else
   `AZURE_DEVOPS_ORG`, else ask) and the identity. The sweep uses a PAT from
   `AZURE_DEVOPS_EXT_PAT` when set, otherwise an `az` token from the active
   `AZURE_CONFIG_DIR` profile. Confirm the profile and who it connects as:

   ```sh
   az account list --query "[].tenantId" --output tsv | sort -u
   az rest --resource 499b84ac-1321-427f-aa17-267ca6975798 \
     --url "${AZURE_DEVOPS_ORG}/_apis/connectionData" \
     --query "authenticatedUser.providerDisplayName" --output tsv
   ```

   Done when the profile holds one tenant (or `--tenant` is chosen) and the
   second command prints the intended identity. When the Azure DevOps identity
   differs from the Azure one, or the profile holds other tenants, read
   [references/identity.md](references/identity.md) before going further.
   When an Azure subscription sweep or inventory exists, write the
   engagement's server, database and application names to a keywords file for
   step 2.

2. **Sweep.**

   ```sh
   uv run scripts/az-devops-discovery.py --organization "${AZURE_DEVOPS_ORG}" \
     --project "${PROJECT}" --keywords "${KEYWORDS_FILE}"
   ```

   Omit `--project` to sweep every project the caller can read; omit
   `--keywords` to use the default terms only. Output lands in
   `.local/tmp/az-devops-discovery/<org>/` at the project root. Run it in the
   background with its log kept, and never filter the log down to failures:
   a quiet terminal is not a hung sweep. Exit 0 means every module completed;
   1 lists failed modules on stderr, the rest still valid, and
   `--resume --only mod` re-runs one while keeping good captures.
   Done when `summary.md` states `Modules completed N of N`, or every failed
   module has been re-run or written down as a gap.

3. **Navigate.** Read
   [references/reading-the-findings.md](references/reading-the-findings.md)
   and work the reports in its order. Done when every report listed in
   `summary.md` has been opened, every table has yielded a finding or been
   noted as clean, and every row of the summary's "Could not read" table is
   accounted for using [references/permissions.md](references/permissions.md).

4. **Write `findings.md`** at the output directory root, in the structure the
   reading guide prescribes. Done when every finding names its report and
   table, carries a confidence label and rank, every quantity is the queried
   number rather than a word like "most", and people appear only as counts and
   account types.

5. **Report back** in chat: organisation, projects, modules completed, the
   top three findings with their rank, and the path to `findings.md`.

## Interface

| Flag | Effect |
| --- | --- |
| `--organization URL` | `https://dev.azure.com/ORG` or `https://ORG.visualstudio.com`. Default `AZURE_DEVOPS_ORG` |
| `--project, -p NAME` | Repeatable. Default every project the caller can read |
| `--output-dir, -o DIR` | Where `raw/`, `reports/`, `summary.md` go |
| `--only MOD[,MOD]` / `--skip MOD[,MOD]` | Select modules; `access` always runs |
| `--since DAYS` | History window, default 365 |
| `--keywords FILE` | Extra Boards search terms, one per line, added to `assets/keywords.txt` |
| `--detail-cap N` | Most keyword hits fetched in full, default 200 |
| `--tenant ID` | Tenant for the `az` token request |
| `--resume` | Keep captures already saved with status 200 |
| `--render-only` | Rebuild reports from `raw/` with no network |
| `--list` | Print modules and exit |

## Modules, in run order

| Module | Scope | Question it answers |
| --- | --- | --- |
| `access` | organisation | What can this identity read, surface by surface |
| `org` | organisation | Who is here, who administers, which projects are hidden, what extensions and feeds exist |
| `repos` | project | How change reaches each branch: review policy, approvals, direct pushes, divergence, TFVC |
| `pipelines` | project | How much history is held, build and deployment outcomes, approvals, agents, capacity, failed-then-passed pairs |
| `boards` | project | Whether the board is live, how it is used, what is in flight, what touches the engagement |
| `wiki` | project | Whether written documentation exists, and its sections |

## Output layout

```text
<output-dir>/
  summary.md                    module status, report index, everything that could not be read
  findings.md                   written in step 4
  reports/<scope>/<module>.md   <scope> is _org or the project name
  reports/<scope>/<module>.json the numbers behind each report
  raw/<scope>/<module>/         every response as .json with .meta.json; task logs as .log
```

`raw/` holds names, email addresses and free text from work items and task
logs. Reports carry counts, account types and titles with addresses masked;
anything derived from `raw/` for a shared document is swept for personal data
first.

## Extending

To add a module, a capture, or a report table, read
[references/extending.md](references/extending.md).
