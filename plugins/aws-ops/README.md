# aws-ops

Skills and MCP servers for operating AWS accounts: run and plan operations
with the AWS CLI across compute, data, networking, security, observability
and cost, and look things up in the AWS documentation.

## Skills

| Skill     | What it does                                                                                                                                                                                                                                                                                                                                                    | Claude Code        |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| `aws-cli` | Confirms the account, region and blast radius before any mutating command, then routes to references for setup and credentials, scripting patterns, ECS, EKS, ECR, Lambda, S3, DynamoDB, Aurora, Glue, Kinesis, MSK, VPC networking, bastion tunneling, IAM and security, secrets, CloudWatch alarms and Logs Insights, Cost Explorer, pricing and GitHub CI/CD | `/aws-ops:aws-cli` |

Every skill also loads on its own when a request matches its description.

## MCP servers

| Server          | Transport                                      | Credentials |
| --------------- | ---------------------------------------------- | ----------- |
| `aws-knowledge` | Remote, `https://knowledge-mcp.global.api.aws` | None        |

The AWS Knowledge MCP server searches and reads AWS documentation, API
references, What's New posts and regional availability. It does not touch any
AWS account.

## Requirements

- `aws-cli`: AWS CLI v2 with a configured profile or credentials, and `jq`.
  Some references also use the Session Manager plugin for SSM sessions and
  tunnels, `kubectl` for EKS, `docker` for ECR, and `psql` or `mysql` for
  Aurora.

## Compatibility

| Client                      | Reads                                                                                                |
| --------------------------- | ---------------------------------------------------------------------------------------------------- |
| Claude Code                 | `.claude-plugin/plugin.json`, `skills/`, and `mcp.json` through the manifest's `mcpServers` redirect |
| Agent Plugins 1.0.0 clients | `plugin.json`, `skills/`, `mcp.json`                                                                 |

## Install

In Claude Code:

```sh
claude plugin marketplace add andreswebs/agent-plugins
claude plugin install aws-ops@andreswebs
```

For other clients and for project-wide setup, see the
[marketplace README](https://github.com/andreswebs/agent-plugins#install).

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [MIT License](LICENSE).
