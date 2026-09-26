# Permissions the sweep needs

Working record for building a least-privilege role that can run the whole
orienteering suite and nothing else. **The role is expressed in Terraform and
every action string is verified against the live provider catalogue, but it has
not been applied or run.** Provisioning is below; the validation procedure is at
the end.

Why bother: a discovery engagement that asks for Owner gets either a long
security review or a quiet refusal, and deserves both. A read-only role that can
be read in one screen is easier to grant, easier to audit, and easier to revoke.

## What the suite actually calls

Every call is a `list`, `show` or `read`. There are no writes, no `listKeys` on
Key Vault, and no `--method post` except the three service endpoints below.
Verified by inspection: all module calls route through one `az_json` helper, and
no create/delete/update/set/start/stop verb appears anywhere in the scripts.

### Control plane, by module

| Module          | Provider surface it reads                                                                                                                                                                       |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `inventory`     | `Microsoft.Resources` (subscriptions, resource groups, resources, tags), `Microsoft.Authorization/locks`, provider registrations, and `Microsoft.Management/managementGroups` for the hierarchy |
| `identity`      | `Microsoft.Authorization` role assignments and custom role definitions, `Microsoft.ManagedIdentity` user-assigned identities                                                                    |
| `exposure`      | `Microsoft.Network` public IPs, NSGs, DNS zones — plus Resource Graph                                                                                                                           |
| `network`       | `Microsoft.Network` VNets, subnets, peerings, route tables, NAT gateways, private endpoints, gateways, firewalls, bastions                                                                      |
| `governance`    | `Microsoft.Authorization` policy assignments and exemptions, `Microsoft.PolicyInsights` policy states                                                                                           |
| `defender`      | `Microsoft.Security` pricings, contacts, settings, assessments, auto-provisioning                                                                                                               |
| `observability` | `Microsoft.Insights` (diagnostic settings, action groups, alert rules), `Microsoft.OperationalInsights` workspaces                                                                              |
| `activity`      | `Microsoft.Insights` activity log event values                                                                                                                                                  |
| `cost`          | `Microsoft.CostManagement` query                                                                                                                                                                |
| `advisor`       | `Microsoft.Advisor` recommendations                                                                                                                                                             |
| `compute`       | `Microsoft.Compute`, `Microsoft.ContainerService`, `Microsoft.Web`, `Microsoft.ContainerRegistry`, `Microsoft.App`                                                                              |
| `storage`       | `Microsoft.Storage` accounts, and blob containers (see the data-plane note)                                                                                                                     |
| `data`          | `Microsoft.Sql`, `Microsoft.DBforPostgreSQL`, `Microsoft.DBforMySQL`, `Microsoft.DocumentDB`, `Microsoft.Cache`, including firewall rules                                                       |
| `keyvault`      | `Microsoft.KeyVault` vaults, and vault objects (see the data-plane note)                                                                                                                        |
| `messaging`     | `Microsoft.ServiceBus`, `Microsoft.EventHub`, `Microsoft.EventGrid`                                                                                                                             |
| `ai`            | `Microsoft.CognitiveServices` accounts and deployments, `Microsoft.MachineLearningServices`, `Microsoft.Search`                                                                                 |
| `edge`          | `Microsoft.Network` application gateways and WAF policies, `Microsoft.Cdn`, `Microsoft.ApiManagement`                                                                                           |
| `backup`        | `Microsoft.RecoveryServices` vaults and protected items                                                                                                                                         |
| `sqlvm`         | `Microsoft.SqlVirtualMachine` SQL VMs and groups, plus Resource Graph for VMs built from a SQL Server image                                                                                      |
| (every run)     | The caller's own role assignments, for the provenance block in `summary.md`; covered by `Microsoft.Authorization/roleAssignments/read`                                                          |

### Three endpoints that are not ordinary resource reads

| Endpoint                            | Needs                                 | Note                                                                                                 |
| ----------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `Microsoft.ResourceGraph/resources` | Resource Graph read                   | Reads across every subscription the principal can see; results cap at 1000 rows                      |
| `Microsoft.CostManagement/query`    | Cost Management Reader, or equivalent | It is an **action**, not a read, so a role built only from `*/read` will not cover it                |
| `Microsoft.Management/getEntities`  | Management group read                 | Fails harmlessly if the principal has no management-group scope; the hierarchy section is then blank |

## The two data-plane reads, which control-plane RBAC does not cover

This is the part that surprises people, and it is worth stating plainly:
**Owner does not grant data-plane access.**

**Key Vault objects.** Listing secrets, keys and certificates is a data-plane
operation. On a vault using **access policies** (`enableRbacAuthorization: false`),
_no_ Azure RBAC role grants it — not Reader, not Key Vault Administrator, not
Owner. Access comes only from an entry in the vault's own access-policy list.
Observed directly: a principal holding Owner at management-group scope, with
effective `actions: ["*"]`, was refused on all six vaults in an estate where
every vault used access policies. On an RBAC-enabled vault, Key Vault Reader
covers listing object names without values.

**Blob containers.** `az storage container list` reaches the data plane. Without
`--auth-mode login` the CLI falls back to the account key, which requires
`Microsoft.Storage/storageAccounts/listKeys/action` — a genuinely privileged
operation that hands over full access to the account's data. A least-privilege
role should **not** include `listKeys`; grant **Storage Blob Data Reader**
instead and have the suite pass `--auth-mode login`. The suite does pass it, so
no account key is ever needed and `listKeys` stays out of the role.

## The role

Built from `*/read` on the providers above, plus the Cost Management action.

Every action string below was checked against the live catalogue, glob-matched
against the full operation list for all 34 namespaces:

```sh
az provider operation show --namespace "${NAMESPACE}" --output json |
    jq -r '[.operations[]?.name] + [.resourceTypes[]?.operations[]?.name] | .[]'
```

Re-run that check whenever an action is added. A wrong string fails silently by
granting nothing, and three of the originally drafted strings were wrong in
exactly that way — `policyStates/read`, which the governance module never calls;
and a missing `getEntities/action` and `providers/read`, without which the
hierarchy and provider-registration sections read nothing. Note that
`az provider operation show` returns nested resource-type operations separately
from top-level ones, so a query that reads only `.operations[]` sees about 1% of
the catalogue and will wrongly report a valid string as missing. Casing does not
matter: Azure matches action strings case-insensitively.

```json
{
  "Name": "Discovery Sweep Reader",
  "Description": "Read-only discovery of an Azure subscription. No data-plane access, no key retrieval, no writes.",
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resources/read",
    "Microsoft.Resources/tags/read",
    "Microsoft.Resources/providers/read",
    "Microsoft.Resources/subscriptions/providers/read",
    "Microsoft.Management/managementGroups/read",
    "Microsoft.Management/getEntities/action",
    "Microsoft.Authorization/locks/read",
    "Microsoft.Authorization/roleAssignments/read",
    "Microsoft.Authorization/roleDefinitions/read",
    "Microsoft.Authorization/policyAssignments/read",
    "Microsoft.Authorization/policyExemptions/read",
    "Microsoft.PolicyInsights/*/read",
    "Microsoft.PolicyInsights/policyStates/queryResults/action",
    "Microsoft.PolicyInsights/policyStates/summarize/action",
    "Microsoft.ManagedIdentity/userAssignedIdentities/read",
    "Microsoft.ResourceGraph/resources/read",
    "Microsoft.CostManagement/query/action",
    "Microsoft.Advisor/recommendations/read",
    "Microsoft.Security/*/read",
    "Microsoft.Insights/*/read",
    "Microsoft.OperationalInsights/workspaces/read",
    "Microsoft.Network/*/read",
    "Microsoft.Compute/*/read",
    "Microsoft.ContainerService/managedClusters/read",
    "Microsoft.ContainerRegistry/registries/read",
    "Microsoft.App/*/read",
    "Microsoft.Web/sites/read",
    "Microsoft.Web/serverfarms/read",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Sql/*/read",
    "Microsoft.DBforPostgreSQL/*/read",
    "Microsoft.DBforMySQL/*/read",
    "Microsoft.DocumentDB/databaseAccounts/read",
    "Microsoft.Cache/redis/read",
    "Microsoft.KeyVault/vaults/read",
    "Microsoft.ServiceBus/*/read",
    "Microsoft.EventHub/*/read",
    "Microsoft.EventGrid/*/read",
    "Microsoft.CognitiveServices/accounts/read",
    "Microsoft.CognitiveServices/accounts/deployments/read",
    "Microsoft.MachineLearningServices/workspaces/read",
    "Microsoft.Search/searchServices/read",
    "Microsoft.Cdn/profiles/read",
    "Microsoft.ApiManagement/service/read",
    "Microsoft.RecoveryServices/vaults/read",
    "Microsoft.RecoveryServices/vaults/backupProtectedItems/read",
    "Microsoft.SqlVirtualMachine/sqlVirtualMachines/read",
    "Microsoft.SqlVirtualMachine/sqlVirtualMachineGroups/read"
  ],
  "NotActions": [
    "Microsoft.Storage/storageAccounts/listKeys/action",
    "Microsoft.Storage/storageAccounts/listAccountSas/action",
    "Microsoft.Storage/storageAccounts/listServiceSas/action"
  ],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["/subscriptions/<subscription-id>"]
}
```

Deliberately excluded, and each exclusion is the point of the exercise:

- `Microsoft.Storage/storageAccounts/listKeys/action` and the two SAS actions —
  each hands over the data. `storageAccounts/read` does not pull them in today,
  so the `NotActions` are there to survive someone later widening that line to
  `Microsoft.Storage/*/read`.
- `Microsoft.KeyVault/vaults/secrets/read` and any `DataActions` — the suite
  reports object _names and counts_, never values, and should never be able to
  read a secret.
- Anything ending `/write`, `/delete`, or `/action` other than the Cost
  Management query.

Alongside the role, grant separately and only where the estate needs it:

| Grant                                                                                    | For                 | Why not in the role                                                                |
| ---------------------------------------------------------------------------------------- | ------------------- | ---------------------------------------------------------------------------------- |
| **Cost Management Reader**                                                               | the `cost` module   | Simpler than getting the query action right, and it is the documented role         |
| **Storage Blob Data Reader**                                                             | container listing   | A data-plane role; cannot be expressed in `Actions`                                |
| **Key Vault Reader**, or an access-policy entry with `list` on secrets/keys/certificates | vault object counts | RBAC-enabled vaults take the role; access-policy vaults take only the policy entry |

## Provisioning it

[`../assets/az-sub-orienteering-permissions.tf`](../assets/az-sub-orienteering-permissions.tf)
is the whole thing in one self-contained file: an Entra application and service
principal, the custom role above, the built-in assignments that cover what a
custom role cannot express, and optional Key Vault access-policy entries. Nothing
in it is destructive, but it creates a principal and grants it access, so the
`apply` is the user's to run.

### Two scope options

The `assignment_scope` variable is the only difference between them. The action
list does not change, so widening the blast radius is one reviewable input
rather than a different role.

|                         | `subscription` (default)                                                         | `management_group`                                                                                                                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Grant scope             | One subscription                                                                 | Every subscription under the group, including ones added later                                                                                                                                      |
| Extra input             | —                                                                                | `management_group_id`, the group's ID rather than its display name; the tenant root group's ID is the tenant GUID                                                                                   |
| Who can apply it        | Owner or User Access Administrator on the subscription                           | The same at the group; **at the tenant root group this usually needs the Entra "Access management for Azure resources" elevation first**, which is a tenant-wide change and a separate conversation |
| Management Group Reader | Assigned separately when `management_group_id` is set, for the hierarchy section | Not needed; the custom role carries `getEntities` at a scope that satisfies it                                                                                                                      |
| Cross-tenant reach      | None                                                                             | None. A management group grant cannot reach a subscription in another tenant                                                                                                                        |

```sh
terraform apply -var subscription_id="${SUBSCRIPTION_ID}"

terraform apply \
    -var subscription_id="${SUBSCRIPTION_ID}" \
    -var assignment_scope=management_group \
    -var management_group_id="${MANAGEMENT_GROUP_ID}"
```

`subscription_id` is required either way: the `azurerm` provider needs a
subscription to authenticate against even when nothing is assigned there.

### What the wide option does not do for you

- **The sweep still runs one subscription at a time.** The scripts pin
  `--subscription` per run, so a group-scoped principal is one that _can_ read
  the estate, not a sweep that does. Loop, as the cross-subscription section of
  the skill shows. The `sweep_subscriptions_command` output enumerates what the
  principal can now see, filtered to the tenant.
- **Resource Graph widens with it.** Those queries already read every
  subscription the principal can see, and cap at 1000 rows. The exposure and
  network tables become a lower bound across the whole estate at once, which is
  a much easier cap to hit than on one subscription.
- **Key Vault access policies get no shortcut.** Access-policy vaults still take
  one entry each; there is no group-level equivalent. The list just gets longer.

Prefer the narrow option unless the engagement genuinely covers the whole group.
The argument this document opens with — that a role readable in one screen gets
granted where Owner gets reviewed — applies to scope as much as to actions, and
a group-scope request reopens the review that the narrow role was built to
avoid. Several subscription-scope applies cost a few more invocations and keep
the grant legible to whoever signs it off.

## How to validate it

The role is only proven by running the suite as a principal that holds it and
nothing else.

1. Apply the Terraform above with `assignment_scope = "subscription"`. It
   creates a fresh principal with no other assignments, which is the condition
   the test depends on; reusing an existing principal proves nothing.
2. Run the full sweep as that principal against a subscription known to contain
   a broad mix of resource types.
3. **Read "Calls that failed" in `summary.md`, not just the exit code.** The
   suite continues past a failed call, so a run can complete "19 of 19" with
   modules that read nothing. That table groups every `.err` under `raw/` by
   module and cause. Each is either a missing permission or a tooling defect,
   and the two must be told apart before anything is added to the role.
4. Compare report-by-report against a run by a principal with Reader, to find
   sections that silently emptied.

## Known traps when reading the results

Three observed cases where a failure was reported as a finding, all misleading
in the same direction: they made an absence of access look like an absence of
risk. All three are fixed, and the fixes are the reason for the suite's current
failure handling.

- **A throttled Cost Management call rendered as "the caller may lack Cost
  Management Reader, or the subscription is billed through a channel that hides
  cost".** A billing run minutes later returned the figures. The cost module
  now tells `empty`, `throttled`, `denied` and `error` apart.
- **A failed route-table call rendered as "none found".** The command errored on
  a missing argument. Every table helper now checks for a `.err` first and
  prints "could not read" with the cause.
- **An unregistered resource provider rendered as "The specified subscription
  does not exist".** The subscription existed and every other module read it.
  The cause is now worded as an unregistered provider, which is itself evidence
  that the service was never used there.

A `.json.err` beside a data-plane call is a fact about the caller, not about the
resource. Report it as "could not read", never as "none".
