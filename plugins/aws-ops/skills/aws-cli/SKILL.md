---
name: aws-cli
description: "Run, script and plan operations on AWS accounts with the `aws` CLI. Use when a task touches an AWS account and uses the `aws` command: running or scripting commands, planning a change, querying cost or pricing, or fixing credential, region and permission errors."
---

# AWS CLI

Every command runs against a real account, so each one has a **blast radius**: the account, region and resources it can change. Work these steps before running anything, and again whenever the profile, account or region changes.

1. **Establish where you are.** Run `aws sts get-caller-identity` and `aws configure get region` with the profile the task uses. In scripts, pass `--region` or set `AWS_REGION` explicitly rather than inheriting it. Done when the reply states the account ID, the caller ARN and the region.
2. **Classify each command.** Mark every planned command read-only (`describe-*`, `list-*`, `get-*`, `ls`) or mutating (anything that creates, changes, deletes, starts, stops, attaches, invokes or tags). Done when no command is unmarked.
3. **Confirm every mutating command.** Before running one, state its blast radius and get the user's confirmation; no mutating command is exempt. Run it first with `--dry-run` where the service supports it. Done when each mutating command has a stated blast radius and an explicit confirmation, or was dropped.

When planning a change rather than running it, steps 1 and 2 still hold, and the plan states the blast radius of each mutating command.

## References

| Reference                                                  | Open when                                                                                |
| :--------------------------------------------------------- | :--------------------------------------------------------------------------------------- |
| [Setup](references/setup.md)                               | installing or configuring the CLI, profiles, SSO, credential errors, debugging a failure |
| [Advanced patterns](references/advanced-cli-patterns.md)   | writing JMESPath queries, paginating, waiting on state, scripting or batching commands   |
| [IAM and security](references/iam-security.md)             | working with users, roles, policies, STS, MFA or cross-account access                    |
| [Lambda](references/lambda.md)                             | deploying, configuring or invoking functions, layers, aliases, function URLs             |
| [ECS](references/ecs.md)                                   | running clusters, services or tasks, including Fargate                                   |
| [EKS](references/eks.md)                                   | managing clusters, node groups, kubeconfig or IRSA                                       |
| [ECR](references/ecr.md)                                   | pushing or pulling images, registry auth, scanning, lifecycle policies                   |
| [S3](references/s3.md)                                     | managing buckets or objects, syncing, presigning, lifecycle rules                        |
| [DynamoDB](references/dynamodb.md)                         | managing tables or items, queries, streams, backups                                      |
| [Aurora and RDS](references/aurora.md)                     | managing database clusters, Serverless v2, cloning, blue/green deployments               |
| [Glue](references/glue.md)                                 | working with the Data Catalog, crawlers, ETL jobs or workflows                           |
| [MSK](references/msk.md)                                   | managing Kafka clusters, provisioned or serverless                                       |
| [Kinesis](references/kinesis.md)                           | managing data streams, Firehose delivery or consumers                                    |
| [Secrets and parameters](references/private-parameters.md) | reading or writing Parameter Store or Secrets Manager values, rotation                   |
| [VPC and networking](references/vpc-networking.md)         | working with VPCs, subnets, route tables, security groups or endpoints                   |
| [Bastion and tunneling](references/bastion-tunneling.md)   | reaching a private host: SSM sessions, port forwarding, SSH through a bastion            |
| [GitHub CI/CD](references/github-cicd.md)                  | wiring GitHub Actions to AWS with OIDC, or using CodeBuild                               |
| [CloudWatch](references/cloudwatch.md)                     | creating or inspecting alarms, reading metrics, querying logs with Logs Insights         |
| [Cost Explorer](references/ce.md)                          | analysing cost and usage, forecasts, anomalies, RI and Savings Plans coverage            |
| [Pricing](references/pricing.md)                           | looking up the list price of a service or instance type                                  |

To check a flag, an API shape, a service limit or regional availability, search the AWS documentation with the `aws-knowledge` MCP tools when they are available; otherwise use `aws <service> <command> help`.
