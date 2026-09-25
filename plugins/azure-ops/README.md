# azure-ops

Skills and MCP servers for operating Azure subscriptions and Azure DevOps
organisations: map an unfamiliar subscription or Azure DevOps organisation and
rank what to look at first, estimate costs from public retail prices, and look
things up in Microsoft Learn.

## Skills

| Skill | What it does | Claude Code |
| --- | --- | --- |
| `az-sub-orienteering` | Read-only sweep of a subscription you did not build: inventory, identity, exposure, network, governance, cost and more, then a ranked triage of the findings | `/azure-ops:az-sub-orienteering` |
| `az-devops-orienteering` | Read-only sweep of an Azure DevOps organisation you did not build: access, people and administrators, hidden projects, repository review controls, pipeline history and agents, boards and in-flight work, then a ranked triage | `/azure-ops:az-devops-orienteering` |
| `azure-pricing` | Queries the public Azure Retail Prices API for cost estimates and pricing comparisons | `/azure-ops:azure-pricing` |

Every skill also loads on its own when a request matches its description.

## MCP servers

| Server | Transport | Credentials |
| --- | --- | --- |
| `microsoft-learn` | Remote, `https://learn.microsoft.com/api/mcp` | None |

## Requirements

- `az-sub-orienteering`: Azure CLI with a logged-in session that can read the
  target subscription, `jq`, and GNU coreutils. Every call it makes is
  read-only. The skill's `references/permissions.md` describes the
  least-privilege role a sweep needs, and `assets/` holds a self-contained
  Terraform configuration that provisions it.
- `az-devops-orienteering`: Azure CLI with a session that can read the
  organisation, or a PAT in `AZURE_DEVOPS_EXT_PAT`, and `uv`. Every call is
  read-only. The skill's `references/permissions.md` lists what each module
  needs, and `references/identity.md` how to keep the Azure DevOps sign-in
  separate from Azure.
- `azure-pricing`: `curl` and `jq`. The API is public and needs no login.

## Compatibility

| Client | Reads |
| --- | --- |
| Claude Code | `.claude-plugin/plugin.json`, `skills/`, and `mcp.json` through the manifest's `mcpServers` redirect |
| Agent Plugins 1.0.0 clients | `plugin.json`, `skills/`, `mcp.json` |

The plugin ships only skills and MCP configuration, so it conforms fully to the
Agent Plugins specification.

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install azure-ops@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
