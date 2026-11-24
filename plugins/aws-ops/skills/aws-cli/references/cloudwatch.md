# CloudWatch

## Contents

- [Alarms](#alarms)
- [Lambda Functions](#lambda-functions)
- [API Gateway](#api-gateway)
- [DynamoDB](#dynamodb)
- [EC2 Instances](#ec2-instances)
- [RDS Databases](#rds-databases)
- [ECS Services](#ecs-services)
- [SQS Queues](#sqs-queues)
- [Application Load Balancer](#application-load-balancer)
- [Composite Alarms](#composite-alarms)
- [Alarm Actions](#alarm-actions)
- [Alarm Guidelines](#alarm-guidelines)
- [Inspecting Alarms and Metrics](#inspecting-alarms-and-metrics)
- [Logs Insights](#logs-insights)
- [Dashboards](#dashboards)

---

## Alarms

`put-metric-alarm` creates an alarm, or silently replaces an existing alarm of
the same name in the same region. Check with `describe-alarms --alarm-names`
first when the name may already be in use.

Dimensions must match the metric exactly, every dimension and no extras, or
the alarm stays in `INSUFFICIENT_DATA`. Confirm them with `list-metrics`
before creating the alarm:

```bash
aws cloudwatch list-metrics --namespace AWS/Lambda --metric-name Errors \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}"
```

Percentiles use `--extended-statistic p99` in place of `--statistic`.

## Lambda Functions

### Error Count Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "lambda-${FUNCTION_NAME}-errors-critical" \
    --alarm-description "Lambda error count exceeded threshold" \
    --namespace AWS/Lambda --metric-name Errors \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 10 --comparison-operator GreaterThanOrEqualToThreshold \
    --treat-missing-data notBreaching
```

### Duration Alarm (Approaching Timeout)

The threshold is 80% of the function timeout, in milliseconds:

```bash
TIMEOUT_SECONDS=$(aws lambda get-function-configuration \
    --function-name "${FUNCTION_NAME}" --query Timeout --output text)

aws cloudwatch put-metric-alarm \
    --alarm-name "lambda-${FUNCTION_NAME}-duration-warning" \
    --alarm-description "Lambda duration approaching timeout" \
    --namespace AWS/Lambda --metric-name Duration \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
    --statistic Maximum --period 300 --evaluation-periods 2 \
    --threshold "$((TIMEOUT_SECONDS * 800))" \
    --comparison-operator GreaterThanOrEqualToThreshold
```

### Throttle Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "lambda-${FUNCTION_NAME}-throttles-warning" \
    --alarm-description "Lambda function is being throttled" \
    --namespace AWS/Lambda --metric-name Throttles \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 5 --comparison-operator GreaterThanOrEqualToThreshold
```

### Concurrent Executions Alarm

Set the threshold below the function's reserved concurrency, or below the
account limit when it has none
(`aws lambda get-function-concurrency`, `aws lambda get-account-settings`):

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "lambda-${FUNCTION_NAME}-concurrency-warning" \
    --alarm-description "Lambda concurrent executions high" \
    --namespace AWS/Lambda --metric-name ConcurrentExecutions \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
    --statistic Maximum --period 60 --evaluation-periods 2 \
    --threshold 100 --comparison-operator GreaterThanOrEqualToThreshold
```

## API Gateway

These use the REST API metrics, keyed by `ApiName`. Add
`Name=Stage,Value="${STAGE}"` to alarm on one stage. HTTP APIs publish
`5xx`, `4xx` and `Latency` keyed by `ApiId` instead.

### 5XX Error Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "api-${API_NAME}-5xx-critical" \
    --alarm-description "API Gateway 5XX errors exceeded threshold" \
    --namespace AWS/ApiGateway --metric-name 5XXError \
    --dimensions Name=ApiName,Value="${API_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 10 --comparison-operator GreaterThanOrEqualToThreshold
```

### 4XX Error Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "api-${API_NAME}-4xx-warning" \
    --alarm-description "API Gateway 4XX errors exceeded threshold" \
    --namespace AWS/ApiGateway --metric-name 4XXError \
    --dimensions Name=ApiName,Value="${API_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 2 \
    --threshold 50 --comparison-operator GreaterThanOrEqualToThreshold
```

### Latency Alarm

`Latency` is in milliseconds:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "api-${API_NAME}-latency-warning" \
    --alarm-description "API Gateway p99 latency exceeded threshold" \
    --namespace AWS/ApiGateway --metric-name Latency \
    --dimensions Name=ApiName,Value="${API_NAME}" \
    --extended-statistic p99 --period 300 --evaluation-periods 2 \
    --threshold 2000 --comparison-operator GreaterThanOrEqualToThreshold
```

## DynamoDB

### Read Throttle Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ddb-${TABLE_NAME}-read-throttles-warning" \
    --alarm-description "DynamoDB read requests being throttled" \
    --namespace AWS/DynamoDB --metric-name ReadThrottleEvents \
    --dimensions Name=TableName,Value="${TABLE_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 5 --comparison-operator GreaterThanOrEqualToThreshold \
    --treat-missing-data notBreaching
```

### Write Throttle Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ddb-${TABLE_NAME}-write-throttles-warning" \
    --alarm-description "DynamoDB write requests being throttled" \
    --namespace AWS/DynamoDB --metric-name WriteThrottleEvents \
    --dimensions Name=TableName,Value="${TABLE_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 5 --comparison-operator GreaterThanOrEqualToThreshold \
    --treat-missing-data notBreaching
```

Throttling on a global secondary index is reported with an extra
`GlobalSecondaryIndexName` dimension; alarm on it separately.

### Consumed Capacity Alarm

For a provisioned table. The metric's 5-minute `Sum` is compared against 80%
of the provisioned units per second times the 300 seconds in the period:

```bash
RCU=$(aws dynamodb describe-table --table-name "${TABLE_NAME}" \
    --query Table.ProvisionedThroughput.ReadCapacityUnits --output text)

aws cloudwatch put-metric-alarm \
    --alarm-name "ddb-${TABLE_NAME}-read-capacity-warning" \
    --alarm-description "DynamoDB consumed read capacity approaching provisioned" \
    --namespace AWS/DynamoDB --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value="${TABLE_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 2 \
    --threshold "$((RCU * 300 * 8 / 10))" \
    --comparison-operator GreaterThanOrEqualToThreshold
```

Repeat with `ConsumedWriteCapacityUnits` and `WriteCapacityUnits` for writes.
On-demand tables report `0` provisioned units; alarm on throttles instead.

## EC2 Instances

### CPU Utilization Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ec2-${INSTANCE_ID}-cpu-warning" \
    --alarm-description "EC2 CPU utilization high" \
    --namespace AWS/EC2 --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value="${INSTANCE_ID}" \
    --statistic Average --period 300 --evaluation-periods 3 \
    --threshold 80 --comparison-operator GreaterThanOrEqualToThreshold
```

### Status Check Failed Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ec2-${INSTANCE_ID}-status-check-critical" \
    --alarm-description "EC2 status check failed" \
    --namespace AWS/EC2 --metric-name StatusCheckFailed \
    --dimensions Name=InstanceId,Value="${INSTANCE_ID}" \
    --statistic Maximum --period 60 --evaluation-periods 2 \
    --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold
```

To recover the instance automatically, add
`--alarm-actions "arn:aws:automate:${AWS_REGION}:ec2:recover"` to an alarm on
`StatusCheckFailed_System`.

### Disk Space Alarm (Requires CloudWatch Agent)

The agent's dimensions depend on its configuration, commonly `InstanceId`,
`path`, `device` and `fstype`. Copy them from `list-metrics`:

```bash
aws cloudwatch list-metrics --namespace CWAgent --metric-name disk_used_percent \
    --dimensions Name=InstanceId,Value="${INSTANCE_ID}" Name=path,Value=/

aws cloudwatch put-metric-alarm \
    --alarm-name "ec2-${INSTANCE_ID}-disk-warning" \
    --alarm-description "EC2 disk space usage high" \
    --namespace CWAgent --metric-name disk_used_percent \
    --dimensions Name=InstanceId,Value="${INSTANCE_ID}" Name=path,Value=/ \
        Name=device,Value="${DEVICE}" Name=fstype,Value="${FSTYPE}" \
    --statistic Average --period 300 --evaluation-periods 2 \
    --threshold 85 --comparison-operator GreaterThanOrEqualToThreshold
```

## RDS Databases

For Aurora, alarm per instance with `DBInstanceIdentifier`, or per cluster
with `DBClusterIdentifier`.

### CPU Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "rds-${DB_INSTANCE_ID}-cpu-warning" \
    --alarm-description "RDS CPU utilization high" \
    --namespace AWS/RDS --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
    --statistic Average --period 300 --evaluation-periods 3 \
    --threshold 80 --comparison-operator GreaterThanOrEqualToThreshold
```

### Connection Count Alarm

The threshold is 80% of `max_connections`. The parameter group often holds a
formula such as `{DBInstanceClassMemory/12582880}` rather than a number; in
that case read the live value from the database (`SHOW max_connections;` on
PostgreSQL, `SELECT @@max_connections;` on MySQL):

```bash
aws rds describe-db-parameters --db-parameter-group-name "${DB_PARAMETER_GROUP}" \
    --query "Parameters[?ParameterName=='max_connections'].ParameterValue" \
    --output text

aws cloudwatch put-metric-alarm \
    --alarm-name "rds-${DB_INSTANCE_ID}-connections-warning" \
    --alarm-description "RDS connection count approaching limit" \
    --namespace AWS/RDS --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
    --statistic Average --period 300 --evaluation-periods 2 \
    --threshold "$((MAX_CONNECTIONS * 8 / 10))" \
    --comparison-operator GreaterThanOrEqualToThreshold
```

### Free Storage Space Alarm

`FreeStorageSpace` is in bytes; 10 GiB is `10737418240`. Aurora storage grows
automatically and reports `FreeLocalStorage` per instance instead:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "rds-${DB_INSTANCE_ID}-storage-critical" \
    --alarm-description "RDS free storage space low" \
    --namespace AWS/RDS --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_ID}" \
    --statistic Average --period 300 --evaluation-periods 1 \
    --threshold 10737418240 --comparison-operator LessThanThreshold
```

## ECS Services

### Running Task Count Alarm

`RunningTaskCount` is published only when Container Insights is enabled on
the cluster (`aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --include SETTINGS`):

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ecs-${SERVICE_NAME}-tasks-critical" \
    --alarm-description "ECS service has no running tasks" \
    --namespace ECS/ContainerInsights --metric-name RunningTaskCount \
    --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        Name=ServiceName,Value="${SERVICE_NAME}" \
    --statistic Average --period 300 --evaluation-periods 2 \
    --threshold 1 --comparison-operator LessThanThreshold \
    --treat-missing-data breaching
```

### Service CPU Utilization Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ecs-${SERVICE_NAME}-cpu-warning" \
    --alarm-description "ECS service CPU utilization high" \
    --namespace AWS/ECS --metric-name CPUUtilization \
    --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        Name=ServiceName,Value="${SERVICE_NAME}" \
    --statistic Average --period 300 --evaluation-periods 3 \
    --threshold 80 --comparison-operator GreaterThanOrEqualToThreshold
```

### Service Memory Utilization Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "ecs-${SERVICE_NAME}-memory-warning" \
    --alarm-description "ECS service memory utilization high" \
    --namespace AWS/ECS --metric-name MemoryUtilization \
    --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        Name=ServiceName,Value="${SERVICE_NAME}" \
    --statistic Average --period 300 --evaluation-periods 2 \
    --threshold 85 --comparison-operator GreaterThanOrEqualToThreshold
```

## SQS Queues

### Queue Depth Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "sqs-${QUEUE_NAME}-depth-warning" \
    --alarm-description "SQS queue depth exceeded threshold" \
    --namespace AWS/SQS --metric-name ApproximateNumberOfMessagesVisible \
    --dimensions Name=QueueName,Value="${QUEUE_NAME}" \
    --statistic Maximum --period 300 --evaluation-periods 2 \
    --threshold 1000 --comparison-operator GreaterThanOrEqualToThreshold
```

### Age of Oldest Message Alarm

The threshold is in seconds:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "sqs-${QUEUE_NAME}-age-warning" \
    --alarm-description "SQS messages not being processed in time" \
    --namespace AWS/SQS --metric-name ApproximateAgeOfOldestMessage \
    --dimensions Name=QueueName,Value="${QUEUE_NAME}" \
    --statistic Maximum --period 300 --evaluation-periods 1 \
    --threshold 300 --comparison-operator GreaterThanOrEqualToThreshold
```

For a dead-letter queue, alarm on `ApproximateNumberOfMessagesVisible` with a
threshold of `1`: any message there is a failure.

## Application Load Balancer

The `LoadBalancer` and `TargetGroup` dimensions are the ARN suffixes,
`app/<name>/<id>` and `targetgroup/<name>/<id>`:

```bash
LB_DIMENSION=$(aws elbv2 describe-load-balancers --names "${LB_NAME}" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text | sed 's|.*:loadbalancer/||')
TG_DIMENSION=$(aws elbv2 describe-target-groups --names "${TG_NAME}" \
    --query 'TargetGroups[0].TargetGroupArn' --output text | sed 's|.*:||')
```

### Unhealthy Targets Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "alb-${TG_NAME}-unhealthy-critical" \
    --alarm-description "ALB has unhealthy targets" \
    --namespace AWS/ApplicationELB --metric-name UnHealthyHostCount \
    --dimensions Name=LoadBalancer,Value="${LB_DIMENSION}" \
        Name=TargetGroup,Value="${TG_DIMENSION}" \
    --statistic Average --period 300 --evaluation-periods 2 \
    --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold
```

### Target 5XX Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "alb-${LB_NAME}-5xx-critical" \
    --alarm-description "ALB target 5XX errors exceeded threshold" \
    --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count \
    --dimensions Name=LoadBalancer,Value="${LB_DIMENSION}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 10 --comparison-operator GreaterThanOrEqualToThreshold \
    --treat-missing-data notBreaching
```

### Response Time Alarm

`TargetResponseTime` is in seconds:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "alb-${LB_NAME}-latency-warning" \
    --alarm-description "ALB p99 response time exceeded threshold" \
    --namespace AWS/ApplicationELB --metric-name TargetResponseTime \
    --dimensions Name=LoadBalancer,Value="${LB_DIMENSION}" \
    --extended-statistic p99 --period 300 --evaluation-periods 2 \
    --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold
```

## Composite Alarms

A composite alarm combines existing alarms with a rule over their states
(`ALARM`, `OK`, `INSUFFICIENT_DATA`, joined by `AND`, `OR`, `NOT`). Create
the member alarms first, without actions, and put the actions on the
composite to cut noise:

```bash
aws cloudwatch put-composite-alarm \
    --alarm-name "service-health-critical" \
    --alarm-description "Overall service health degraded" \
    --alarm-rule 'ALARM("lambda-orders-errors-critical") OR ALARM("api-orders-latency-warning") OR ALARM("lambda-orders-throttles-warning")' \
    --alarm-actions "${SNS_TOPIC_ARN}"
```

## Alarm Actions

### SNS Notifications

```bash
SNS_TOPIC_ARN=$(aws sns create-topic --name cloudwatch-alarms \
    --query TopicArn --output text)

# The recipient must confirm the subscription from the email it receives
aws sns subscribe --topic-arn "${SNS_TOPIC_ARN}" \
    --protocol email --notification-endpoint "${ALERT_EMAIL}"
```

Attach the topic when creating the alarm, with `--alarm-actions` for the
`ALARM` state and `--ok-actions` for recovery:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "lambda-${FUNCTION_NAME}-errors-critical" \
    --namespace AWS/Lambda --metric-name Errors \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}" \
    --statistic Sum --period 300 --evaluation-periods 1 \
    --threshold 10 --comparison-operator GreaterThanOrEqualToThreshold \
    --alarm-actions "${SNS_TOPIC_ARN}" --ok-actions "${SNS_TOPIC_ARN}"
```

### Auto Scaling Action

A step scaling policy returns an ARN that an alarm can invoke. This one, for
an EC2 Auto Scaling group, adds one instance between 1 and 2 seconds of
response time and two above that, relative to an alarm threshold of 1:

```bash
POLICY_ARN=$(aws autoscaling put-scaling-policy \
    --auto-scaling-group-name "${ASG_NAME}" \
    --policy-name scale-out-on-latency \
    --policy-type StepScaling --adjustment-type ChangeInCapacity \
    --step-adjustments MetricIntervalLowerBound=0,MetricIntervalUpperBound=1,ScalingAdjustment=1 \
        MetricIntervalLowerBound=1,ScalingAdjustment=2 \
    --query PolicyARN --output text)
```

Pass `--alarm-actions "${POLICY_ARN}"` to the response time alarm above. ECS
services and DynamoDB tables scale through
`aws application-autoscaling put-scaling-policy` instead.

## Alarm Guidelines

### Thresholds

- **CPU and memory:** warning at 70-80%, critical at 80-90%, adjusted for the
  workload's normal bursts.
- **Error rate:** derive from the SLA (99.9% availability allows a 0.1% error
  rate) and the service's normal error rate; set separate thresholds per error
  type.
- **Latency:** alarm on p99 for user-facing APIs; warning at 80% of the SLA
  target, critical at 100%.

### Evaluation Periods

- **Fast-changing metrics** (error counts, failed health checks): 1-2 periods.
- **Slow-changing metrics** (CPU, memory, disk): 3-5 periods.
- **Cost and usage metrics** (daily spend, resource counts): long periods,
  such as `--period 86400`.

Use `--datapoints-to-alarm` with `--evaluation-periods` for "M out of N"
alarms that ignore a single spike, for example 3 of 5.

### Missing Data

`--treat-missing-data` takes:

- `notBreaching` for intermittent workloads, where no data means no traffic;
- `breaching` for always-on services, where no data means something stopped;
- `missing` (the default) to keep the alarm state unchanged and distinguish
  gaps from real readings;
- `ignore` to keep evaluating on the data points that exist.

### Naming

Name alarms `<service>-<resource>-<metric>-<severity>`, for example
`lambda-orders-errors-critical`, so `describe-alarms --alarm-name-prefix`
selects by service and severity.

### Actions

- Separate SNS topics by severity: critical to the on-call pager, warning to
  chat or email.
- Put the service, the threshold and a runbook link in `--alarm-description`.
- Remediate automatically where the fix is safe: scaling on CPU, EC2 recover
  on system status checks.
- Fight alarm fatigue: tune thresholds on observed patterns, use composite
  alarms, and review alarms that fire without action.

## Inspecting Alarms and Metrics

```bash
# Alarms currently firing
aws cloudwatch describe-alarms --state-value ALARM \
    --query 'MetricAlarms[].[AlarmName,StateReason]' --output table

# Alarms by name prefix, including composites
aws cloudwatch describe-alarms --alarm-name-prefix "lambda-" \
    --alarm-types MetricAlarm CompositeAlarm

# Alarms watching one metric
aws cloudwatch describe-alarms-for-metric \
    --namespace AWS/Lambda --metric-name Errors \
    --dimensions Name=FunctionName,Value="${FUNCTION_NAME}"

# State changes of one alarm
aws cloudwatch describe-alarm-history --alarm-name "${ALARM_NAME}" \
    --history-item-type StateUpdate --max-records 20

# Metrics available in a namespace
aws cloudwatch list-metrics --namespace AWS/SQS \
    --query 'Metrics[].Dimensions[].Value' --output text | tr '\t' '\n' | sort -u
```

Read metric values with `get-metric-data`, which takes several queries and
metric math in one call:

```bash
aws cloudwatch get-metric-data \
    --start-time "$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --metric-data-queries '[
      {"Id": "errors", "MetricStat": {"Metric": {"Namespace": "AWS/Lambda",
        "MetricName": "Errors", "Dimensions": [{"Name": "FunctionName",
        "Value": "'"${FUNCTION_NAME}"'"}]}, "Period": 300, "Stat": "Sum"}},
      {"Id": "invocations", "MetricStat": {"Metric": {"Namespace": "AWS/Lambda",
        "MetricName": "Invocations", "Dimensions": [{"Name": "FunctionName",
        "Value": "'"${FUNCTION_NAME}"'"}]}, "Period": 300, "Stat": "Sum"}},
      {"Id": "error_rate", "Expression": "100 * errors / invocations"}
    ]'
```

On macOS without GNU `date`, use `date -u -v-3H +%Y-%m-%dT%H:%M:%SZ`.

Test an alarm's actions by forcing its state; the next evaluation resets it:

```bash
aws cloudwatch set-alarm-state --alarm-name "${ALARM_NAME}" \
    --state-value ALARM --state-reason "Testing alarm actions"
```

## Logs Insights

A query runs asynchronously: `start-query` returns a query ID, and
`get-query-results` returns `Running` until the status is `Complete`.
Times are epoch seconds.

```bash
QUERY_ID=$(aws logs start-query \
    --log-group-names "/aws/lambda/${FUNCTION_NAME}" \
    --start-time "$(date -u -d '-1 hour' +%s)" --end-time "$(date -u +%s)" \
    --query-string 'fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100' \
    --query queryId --output text)

until [ "$(aws logs get-query-results --query-id "${QUERY_ID}" \
    --query status --output text)" = "Complete" ]; do sleep 2; done

aws logs get-query-results --query-id "${QUERY_ID}" --query results
```

The polling loop never ends on a `Failed`, `Cancelled` or `Timeout` status;
check for those in scripts.

### Queries

Errors in the window, newest first:

```txt
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

Error count by type, for JSON logs with an `error_type` field:

```txt
stats count() by error_type
| sort count desc
```

p99 latency by service, for JSON logs with `duration` and `service_name`
fields:

```txt
stats percentile(duration, 99) by service_name
```

Lambda's own `REPORT` lines carry duration and memory without structured
logging:

```txt
filter @type = "REPORT"
| stats max(@duration) as max_ms, avg(@duration) as avg_ms,
    max(@maxMemoryUsed / 1000 / 1000) as max_mem_mb by bin(5m)
```

## Dashboards

```bash
aws cloudwatch list-dashboards
aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" \
    --query DashboardBody --output text | jq .

# Replaces the whole dashboard body
aws cloudwatch put-dashboard --dashboard-name "${DASHBOARD_NAME}" \
    --dashboard-body file://dashboard.json
```

A service dashboard usually carries:

- **Service overview:** request count, error count and percentage, latency
  (p50, p95, p99), availability.
- **Resource utilisation:** CPU and memory by service, network throughput,
  disk I/O.
- **Cost:** daily spend by service, month-to-date cost, budget utilisation.
- **Security:** failed sign-ins, IAM policy changes, security group changes,
  GuardDuty findings.
