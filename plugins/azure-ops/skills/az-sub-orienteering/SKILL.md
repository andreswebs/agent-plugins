---
name: az-sub-orienteering
description: Orienteer an Azure subscription you did not build. Use when asked to discover, inventory, assess, or map an unfamiliar or inherited subscription, when someone asks what runs in a subscription or how exposed it is, when navigating or ranking the reports of a previous sweep, or when comparing several subscriptions. Also when asked what access a sweep needs, or how to provision a least-privilege role for one. The sweep itself is read-only; needs az CLI, jq, GNU coreutils.
metadata:
  argument-hint: "[subscription id] [--only module,...]"
---

# Azure subscription orienteering

Orienteering: a map good enough to prioritise with, before any depth. The sweep
builds the map; the triage guide turns it into a ranked route. Every call is
read-only.

The map covers the Azure control plane and nothing else. It never reaches inside
a virtual machine (SQL Agent jobs, SSIS, SSRS, IIS, file shares, local
accounts), and it never sees Azure DevOps, which is not an Azure resource
provider; `az-devops-orienteering` maps that. Say so wherever a sweep is
presented as an inventory of an estate, because on a lift-and-shift estate that
is where the workload lives.

## Steps

Script paths below are relative to this skill's directory.

1. **Aim.** Resolve the target subscription id: the argument, else
   `AZURE_SUBSCRIPTION_ID`, else ask. Confirm the session reaches it:

   ```sh
   az account show --subscription "${SUBSCRIPTION_ID}" --query "{name:name, tenant:tenantId}" --output table
   ```

   Done when the command prints the intended subscription in the intended tenant.
   A login prompt or wrong tenant is the user's to fix (`az login --tenant`).

2. **Sweep.**

   ```sh
   scripts/az-sub-discovery.bash --subscription "${SUBSCRIPTION_ID}"
   ```

   Output lands in `.local/tmp/az-sub-discovery/${SUBSCRIPTION_ID}/` at the
   project root; pass `--output-dir` only when the user names another place.
   A full run takes 2 to 15 minutes; the diagnostic-settings pass in
   `observability` dominates on large estates. Exit 0 means every module
   completed. Non-zero lists the failed modules on stderr; the other reports
   are still valid, and `--only mod,mod` re-runs just those.
   Done when `summary.md` exists and states `Modules completed N of N`, or every
   failed module has been re-run or written down as a gap.

   **Reading a summary after a partial run.** An output directory accumulates
   reports across runs, so `summary.md` describes _the last invocation_, not the
   state of the whole directory. A re-run never destroys a report: the previous
   version moves to `history/<its Generated time>/` first, so the two can be
   diffed. A filtered run (`--only` or `--skip`) says so
   in place of the completed count, names the filter, and reports when the last
   unfiltered sweep finished — every report in the list carries its own
   `Generated` timestamp, which is the authority. A full run with no failures
   records itself in `.last-full-sweep`. If that line reads `none recorded`, no
   complete sweep has finished in this directory since the tracking was added,
   and the reports are of mixed vintage.

   Each module empties its own `raw/<module>/` directory before it runs, so raw
   output always describes one run. That matters most for `*.json.err` files:
   they are the record of which calls were refused, and a stale one from an
   earlier version of a module reads as a live permissions denial.

3. **Navigate.** Read [references/reading-the-findings.md](references/reading-the-findings.md)
   and work the reports in its order. Done when every report listed in
   `summary.md` has been opened and every table in the priority reports has
   either yielded a finding or been noted as clean.

4. **Write `findings.md`** at the output dir root, in the structure the triage
   guide prescribes. Relative links to `reports/*.md` are fine; the file lives
   beside them. Done when every finding names its report and table, carries a
   rank, and the unexplored-territory and follow-ups sections are filled.

5. **Report back** in chat: subscription, modules completed, any failed calls
   with their cause, the top three findings with their rank, and the path to
   `findings.md`.

## Interface

| Flag                    | Effect                                                           |
| ----------------------- | ---------------------------------------------------------------- |
| `--subscription, -s ID` | Target. Default `AZURE_SUBSCRIPTION_ID`, else the az CLI default |
| `--output-dir, -o DIR`  | Where `raw/`, `reports/`, `summary.md` go                        |
| `--only MOD[,MOD]`      | Run only these modules; `inventory` is always included           |
| `--skip MOD[,MOD]`      | Skip modules                                                     |
| `--fail-fast`           | Abort on first failing module (default: continue, report at end) |
| `--list`                | Print modules in run order and exit                              |
| `AZSD_AZ_TIMEOUT`       | Seconds per az call, default 120                                 |
| `AZSD_LOG_LEVEL`        | `debug` shows every per-resource call                            |

## Modules, in run order

| Module          | Question it answers                                                         |
| --------------- | --------------------------------------------------------------------------- |
| `inventory`     | What is here: management group chain, RGs, every resource, providers, locks |
| `identity`      | Who can act: privileged and orphaned role assignments, custom roles, MIs    |
| `exposure`      | What is reachable or weakly authenticated, across every service at once     |
| `network`       | Topology: VNets, subnets without NSG, peerings, gateways, private link      |
| `governance`    | Policy assignments, non-compliance, exemptions, tag usage                   |
| `defender`      | Defender plans, contacts, unhealthy assessments                             |
| `observability` | Log sinks, activity-log export, alerting, diagnostic-settings coverage      |
| `activity`      | Who changed what in 30 days; failed operations; RBAC changes                |
| `cost`          | Month-to-date and last month by service, RG, location                       |
| `advisor`       | The platform's own ranked recommendations                                   |
| `compute`       | VMs, VMSS, AKS, Container Apps, App Service, ACR                            |
| `storage`       | Accounts, network rules, containers                                         |
| `data`          | PostgreSQL, MySQL, SQL, Cosmos DB, Redis, with firewall rules               |
| `keyvault`      | RBAC vs access policies, soft delete, purge protection, object counts       |
| `messaging`     | Service Bus, Event Hubs, Event Grid                                         |
| `ai`            | Cognitive Services and OpenAI deployments, ML workspaces, Search            |
| `edge`          | Load balancers, App Gateway and WAF, Front Door, APIM                       |
| `backup`        | Recovery Services and Backup vaults, protected items                        |
| `sqlvm`         | SQL Server on VMs: version, edition, licence, and SQL images not registered |

Service modules print `_(no resources of type ...)_` and return immediately
when the inventory holds none of their types.

## Output layout

```text
<output-dir>/
  summary.md            provenance, reports, failed calls, uncovered types, boundary
  findings.md           written in step 4
  reports/<module>.md   one report per module
  history/<Generated>/  earlier versions of replaced reports and summaries
  raw/<module>/*.json   every az response; *.json.err beside a failed call
  raw/inventory/all-resources.csv
```

Every report header carries a provenance line (tool version, tenant, caller
type and object id), so a report copied on its own still says where it came
from. The caller is never named by user principal name. Reports copied into a
shared record still need redacting where the estate itself holds personal data:
`identity.md` lists principal names, and firewall rules are often named for
people.

## Reading a failure correctly

A failed call renders in its report as "could not read" with a cause, and the
summary's "Calls that failed" table lists every one by module. Carry them into
`findings.md` as blind spots, never as empty results.

- An unregistered resource provider means the service was never used in that
  subscription: a finding, not a gap. `defender` reporting it means Defender for
  Cloud was never enabled.
- A denial on a data-plane call (Key Vault objects, blob containers, Log
  Analytics queries) is a fact about the caller's roles, not the resource.
- Resource Graph results are capped at 1000 rows per query; a `truncated`
  warning on stderr means the exposure tables are a lower bound.

## Several subscriptions

One run per subscription, one output dir each, then compare `summary.md` files:

```sh
for sub in $(az account list --query "[].id" --output tsv); do
    scripts/az-sub-discovery.bash --subscription "${sub}" || true
done
```

Or over a labelled list such as `BILLING_SUBS` (`label=id` pairs):

```sh
for pair in ${BILLING_SUBS}; do
    scripts/az-sub-discovery.bash --subscription "${pair#*=}" || true
done
```

### Cost across subscriptions

`az-billing-report.bash` is the complement to the per-subscription `cost`
module: one table of every subscription in `BILLING_SUBS` by total and by
service, in markdown and CSV. Run it only when the user asks for cross-subscription
cost or when comparing several sweeps; it is not part of a sweep.

```sh
export BILLING_SUBS="prod=${PROD_SUBSCRIPTION_ID} dev=${DEV_SUBSCRIPTION_ID}"
scripts/az-billing-report.bash            # month to date
scripts/az-billing-report.bash 2026-08    # one calendar month
```

Output: `billing-report-<period>.md` and `.csv` in `BILLING_OUT_DIR`, default
`.local/tmp/az-sub-discovery/billing/`. Retail rates only; reservations and
partner pricing are not reflected, so totals are for trend and chargeback, never
for invoice reconciliation. Needs `bc` in addition to `az` and `jq`.

## Permissions

What the suite reads, which calls are data-plane and therefore not covered by
any control-plane role, and a least-privilege role to replace asking for Owner:
[references/permissions.md](references/permissions.md). Read it before
requesting access for a new engagement, and whenever a report section comes back
empty.

### Setting the access up

Only when the user asks how to provision access. A sweep does not need this; it
needs credentials that already work, and offering to build a role unprompted
turns a read-only task into an infrastructure change.

[az-sub-orienteering-permissions.tf](assets/az-sub-orienteering-permissions.tf) is a
self-contained Terraform file creating the service principal, the custom role
and the built-in assignments. Two scope options, one variable apart:

| `assignment_scope` | Grants                                         | Ask the user which                      |
| ------------------ | ---------------------------------------------- | --------------------------------------- |
| `subscription`     | One subscription. The default                  | When the engagement names subscriptions |
| `management_group` | Every subscription under `management_group_id` | When it covers a whole tenant or group  |

Default to `subscription` and say why. The wide option reopens the security
review the narrow role exists to avoid, may need a tenant-wide Entra elevation
to apply at the root group, and does not make the sweep itself multi-subscription
— the scripts still run one subscription per invocation. The trade-offs are in
the permissions reference under "Provisioning it".

Never run `terraform apply` here. Hand the user the command; creating a
principal and granting it access to a client estate is theirs to approve.

## Extending

To add a module, a Resource Graph query, or a jq renderer, read
[references/extending.md](references/extending.md).
