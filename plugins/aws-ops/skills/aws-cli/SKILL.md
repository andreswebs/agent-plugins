---
name: aws-cli
description: "Run, script and plan operations on AWS accounts with the `aws` CLI. Use when a task touches an AWS account and uses the `aws` command: running or scripting commands, planning a change, querying cost or pricing, or fixing credential, region and permission errors."
---

# AWS CLI

Every command runs against a real account, so each one has a **blast radius**: the account and its environment tier (prod, staging, dev), the region, and the resources it can change. Work these steps before running anything, and again whenever the profile, account or region changes.

1. **Establish where you are.** Run `aws sts get-caller-identity` and `aws configure get region` with the profile the task uses, and name the tier with its source: `aws iam list-account-aliases` first, then the profile name, then the user. When the task carries an account or region (an ARN carries both, a console URL only the region), they win over the configured ones; pass the region with `--region`. In scripts, pass `--region` or set `AWS_REGION` explicitly rather than inheriting it. A NotFound on the resource the task names means the account or region is wrong: ask the user which profile to use. Done when the reply states the account ID, the caller ARN, the region and the tier with its source, and they are the ones that hold the task's resource.
2. **Classify each command.** Mark every planned command read-only (it returns data and changes nothing in the account) or mutating (it creates, changes, deletes, starts, stops, attaches, invokes or tags anything). Verbs such as `describe-*`, `list-*`, `get-*`, `batch-get-*` and `wait` are hints, not proof; when unsure, read the command's help or treat it as mutating. Also mark each command whose output can carry secrets (`ecs describe-task-definition`, `lambda get-function-configuration`, `ssm get-parameter --with-decryption`, `secretsmanager get-secret-value`), and narrow it with `--query` to the fields the task needs. Done when no command is unmarked.
3. **Confirm every mutating command.** Before running one, state its blast radius and get the user's confirmation; no mutating command is exempt. The user's request is that confirmation only when it names the target as precisely as the blast radius does; when you filled in any part of it, including a tier that step 1 took from a profile name rather than an alias or the user, state the blast radius and wait for the reply. Run it first with `--dry-run` where the service supports it. Done when each mutating command has a stated blast radius and an explicit confirmation, or was dropped.

When planning a change rather than running it, steps 1 and 2 still hold, and the plan states the blast radius of each mutating command.

## References

| Reference                                                  | Open when                                                                                         |
| :--------------------------------------------------------- | :------------------------------------------------------------------------------------------------ |
| [Setup](references/setup.md)                               | installing or configuring the CLI, profiles, SSO, credential errors, debugging a failure          |
| [Advanced patterns](references/advanced-cli-patterns.md)   | writing JMESPath queries, paginating, waiting on state, scripting or batching commands            |
| [IAM and security](references/iam-security.md)             | working with users, roles, policies, STS, MFA or cross-account access                             |
| [Lambda](references/lambda.md)                             | deploying, configuring or invoking functions, layers, aliases, function URLs                      |
| [ECS](references/ecs.md)                                   | running clusters, services or tasks, or diagnosing a stuck or failed ECS or CodeDeploy deployment |
| [EKS](references/eks.md)                                   | managing clusters, node groups, kubeconfig or IRSA                                                |
| [ECR](references/ecr.md)                                   | pushing or pulling images, registry auth, scanning, lifecycle policies                            |
| [S3](references/s3.md)                                     | managing buckets or objects, syncing, presigning, lifecycle rules                                 |
| [DynamoDB](references/dynamodb.md)                         | managing tables or items, queries, streams, backups                                               |
| [Aurora and RDS](references/aurora.md)                     | managing database clusters, Serverless v2, cloning, blue/green deployments                        |
| [Glue](references/glue.md)                                 | working with the Data Catalog, crawlers, ETL jobs or workflows                                    |
| [MSK](references/msk.md)                                   | managing Kafka clusters, provisioned or serverless                                                |
| [Kinesis](references/kinesis.md)                           | managing data streams, Firehose delivery or consumers                                             |
| [Secrets and parameters](references/private-parameters.md) | reading or writing Parameter Store or Secrets Manager values, rotation                            |
| [VPC and networking](references/vpc-networking.md)         | working with VPCs, subnets, route tables, security groups or endpoints                            |
| [Bastion and tunneling](references/bastion-tunneling.md)   | reaching a private host: SSM sessions, port forwarding, SSH through a bastion                     |
| [GitHub CI/CD](references/github-cicd.md)                  | wiring GitHub Actions to AWS with OIDC, or using CodeBuild                                        |
| [CloudWatch](references/cloudwatch.md)                     | creating or inspecting alarms, reading metrics, querying logs with Logs Insights                  |
| [Cost Explorer](references/ce.md)                          | analysing cost and usage, forecasts, anomalies, RI and Savings Plans coverage                     |
| [Pricing](references/pricing.md)                           | looking up the list price of a service or instance type                                           |

To check a flag, an API shape, a service limit or regional availability, search the AWS documentation with the `aws-knowledge` MCP tools when they are available; otherwise use `aws <service> <command> help`.
