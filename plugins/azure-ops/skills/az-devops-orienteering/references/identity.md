# Identity

How the sweep signs in, and how to keep an Azure DevOps identity separate from
an Azure one. Read it when the two identities differ, when the `az` profile
holds more than one tenant, or when a PAT is in play.

## What the sweep uses

1. `AZURE_DEVOPS_EXT_PAT`, when set, sent as Basic authentication.
2. Otherwise a bearer token from
   `az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798`
   under the active `AZURE_CONFIG_DIR`, with `--tenant` when given.

The sweep's own order differs from the `azure-devops` CLI extension's, which
tries every tenant cached in the active profile first and uses a PAT only when
no `az login` token reaches the organisation. On a profile that holds other
organisations' tenants, the extension requests Azure DevOps tokens from each of
them while it searches, and silently ignores a PAT in the environment.

## One profile per identity

`AZURE_CONFIG_DIR` moves the whole `az` profile: token cache, accounts,
configuration, and by default installed extensions. Give the Azure DevOps
identity its own:

```sh
export AZ_DEVOPS_PROFILE="${HOME}/.azure-profiles/${PROFILE_NAME}"
mkdir -p "${AZ_DEVOPS_PROFILE}"
AZURE_CONFIG_DIR="${AZ_DEVOPS_PROFILE}" az login --tenant "${TENANT_ID}" --allow-no-subscriptions
```

`--allow-no-subscriptions` is needed when the identity holds no Azure role.
Activate it for a shell with `export AZURE_CONFIG_DIR="${AZ_DEVOPS_PROFILE}"`,
or for one command by prefixing the variable. A direnv `.envrc` that exports it
applies to every `az` call under that directory, and an agent's shell does not
load direnv, so set it explicitly on the sweep command.

Confirm the profile holds a single tenant before sweeping:

```sh
AZURE_CONFIG_DIR="${AZ_DEVOPS_PROFILE}" az account list --query "[].tenantId" --output tsv | sort -u
```

## Which tenant backs the organisation

An unauthenticated request to the organisation returns an
`x-vss-resourcetenant` header on its sign-in redirect; all zeros there does not
identify the tenant. After signing in, `_apis/connectionData` names the caller,
not the organisation's tenant. The `org` report's identity kinds are the best
available evidence; see the reading guide.

## PAT

Point `AZURE_CONFIG_DIR` at an empty directory and export the PAT from a secret
store, so no `az` login competes with it. Read-only scopes cover the sweep:
Code, Build, Release, Work Items, Analytics, Wiki, Project and Team, Graph,
Identity, Member Entitlement Management, Service Connections, Variable Groups,
Agent Pools, Test Management, Packaging and Audit Log, all Read. `az devops
login` stores a PAT in the OS keyring, outside `AZURE_CONFIG_DIR`, where
switching profiles cannot reach it; the environment variable avoids that.
