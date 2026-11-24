# Cost Explorer (CE)

## Contents

- [Cost and Usage Queries](#cost-and-usage-queries)
- [Forecasting](#forecasting)
- [Dimension and Tag Discovery](#dimension-and-tag-discovery)
- [Filter Expression Patterns](#filter-expression-patterns)
- [Reserved Instance Analysis](#reserved-instance-analysis)
- [Savings Plans Analysis](#savings-plans-analysis)
- [Cost Anomaly Detection](#cost-anomaly-detection)
- [Cost Categories](#cost-categories)
- [Cost Allocation Tags](#cost-allocation-tags)
- [Rightsizing Recommendations](#rightsizing-recommendations)
- [Commitment Purchase Analysis](#commitment-purchase-analysis)
- [Useful jq Patterns](#useful-jq-patterns)
- [Best Practices](#best-practices)

---

## Cost and Usage Queries

### Get Cost and Usage

Primary command for retrieving cost and usage metrics.

**Available metrics:** `BlendedCost`, `UnblendedCost`, `AmortizedCost`, `NetAmortizedCost`, `NetUnblendedCost`, `UsageQuantity`, `NormalizedUsageAmount`

```sh
# Monthly costs for a quarter
aws ce get-cost-and-usage \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost"

# Daily costs grouped by service
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-03-27 \
    --granularity DAILY \
    --metrics "UnblendedCost" "UsageQuantity" \
    --group-by Type=DIMENSION,Key=SERVICE

# Group by cost allocation tag
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=TAG,Key=Environment

# Group by two dimensions (max 2)
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE Type=DIMENSION,Key=REGION

# Filter by service and linked account
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "BlendedCost" \
    --filter '{
        "And": [
            {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Compute Cloud - Compute"]}},
            {"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": ["123456789012"]}}
        ]
    }'
```

### Get Cost and Usage with Resources

Like `get-cost-and-usage` but includes resource-level detail (e.g., individual EC2 instance IDs). Must be enabled in Cost Explorer Settings. Filter is **required**. Limited to last 14 days.

```sh
# Resource-level EC2 costs
aws ce get-cost-and-usage-with-resources \
    --time-period Start=2026-03-20,End=2026-03-27 \
    --granularity DAILY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Compute Cloud - Compute"]}}'
```

## Forecasting

### Cost Forecast

Predicts future spending based on historical data.

**Metric values:** `BLENDED_COST`, `UNBLENDED_COST`, `AMORTIZED_COST`, `NET_UNBLENDED_COST`, `NET_AMORTIZED_COST`

```sh
# Monthly cost forecast
aws ce get-cost-forecast \
    --time-period Start=2026-03-26,End=2026-04-26 \
    --metric UNBLENDED_COST \
    --granularity MONTHLY

# Daily forecast with 80% confidence interval
aws ce get-cost-forecast \
    --time-period Start=2026-03-26,End=2026-04-26 \
    --metric UNBLENDED_COST \
    --granularity DAILY \
    --prediction-interval-level 80
```

### Usage Forecast

Predicts future usage quantities. Start date must be today or later.

```sh
aws ce get-usage-forecast \
    --time-period Start=2026-03-26,End=2026-04-26 \
    --metric USAGE_QUANTITY \
    --granularity DAILY \
    --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Compute Cloud - Compute"]}}'
```

## Dimension and Tag Discovery

### Get Dimension Values

Discover available filter values for a given dimension. Essential for building filters.

**Key dimensions:** `AZ`, `INSTANCE_TYPE`, `LINKED_ACCOUNT`, `PAYER_ACCOUNT`, `SERVICE`, `USAGE_TYPE`, `REGION`, `RECORD_TYPE`, `OPERATING_SYSTEM`, `TENANCY`, `DATABASE_ENGINE`, `CACHE_ENGINE`, `DEPLOYMENT_OPTION`, `PLATFORM`, `LEGAL_ENTITY_NAME`, `INVOICING_ENTITY`, `BILLING_ENTITY`

```sh
# List all services with costs
aws ce get-dimension-values \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --dimension SERVICE

# List all linked accounts
aws ce get-dimension-values \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --dimension LINKED_ACCOUNT

# Search for specific instance types
aws ce get-dimension-values \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --dimension INSTANCE_TYPE \
    --search-string "m5"

# List all regions with usage
aws ce get-dimension-values \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --dimension REGION
```

### Get Tags

Query available cost allocation tag keys and values.

```sh
# List all cost allocation tag keys
aws ce get-tags \
    --time-period Start=2026-03-01,End=2026-04-01

# Get values for a specific tag key
aws ce get-tags \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --tag-key "Environment"

# Search for tag values matching a pattern
aws ce get-tags \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --tag-key "Project" \
    --search-string "prod"
```

## Filter Expression Patterns

The `--filter` parameter uses a nested Expression structure shared across most CE commands.

```sh
# Simple: single dimension
--filter '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon S3"]}}'

# AND: multiple conditions
--filter '{
    "And": [
        {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon EC2"]}},
        {"Dimensions": {"Key": "REGION", "Values": ["us-east-1"]}}
    ]
}'

# OR: either condition
--filter '{
    "Or": [
        {"Dimensions": {"Key": "REGION", "Values": ["us-east-1"]}},
        {"Dimensions": {"Key": "REGION", "Values": ["us-west-2"]}}
    ]
}'

# NOT: exclude credits and refunds
--filter '{"Not": {"Dimensions": {"Key": "RECORD_TYPE", "Values": ["Credit", "Refund"]}}}'

# Tag-based filter
--filter '{"Tags": {"Key": "Environment", "Values": ["production"]}}'

# Cost Category filter
--filter '{"CostCategories": {"Key": "Team", "Values": ["Engineering"]}}'

# Match options (EQUALS, STARTS_WITH, ENDS_WITH, CONTAINS, ABSENT)
--filter '{
    "Dimensions": {
        "Key": "LINKED_ACCOUNT_NAME",
        "MatchOptions": ["STARTS_WITH"],
        "Values": ["prod"]
    }
}'
```

## Reserved Instance Analysis

### Reservation Utilization

How well your Reserved Instances are being used (% of purchased hours consumed).

```sh
# Monthly RI utilization
aws ce get-reservation-utilization \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY

# Grouped by subscription
aws ce get-reservation-utilization \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY \
    --group-by Type=DIMENSION,Key=SUBSCRIPTION_ID
```

### Reservation Coverage

How much usage is covered by RIs vs On-Demand.

```sh
# RI coverage by service
aws ce get-reservation-coverage \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY \
    --group-by Type=DIMENSION,Key=SERVICE

# EC2 RI coverage by instance type
aws ce get-reservation-coverage \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY \
    --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
    --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Compute Cloud - Compute"]}}'
```

### Reservation Purchase Recommendations

Recommends which RIs to buy to reduce costs.

**Payment options:** `NO_UPFRONT`, `PARTIAL_UPFRONT`, `ALL_UPFRONT`, `LIGHT_UTILIZATION`, `MEDIUM_UTILIZATION`, `HEAVY_UTILIZATION`

```sh
# EC2 RI purchase recommendations
aws ce get-reservation-purchase-recommendation \
    --service "Amazon Elastic Compute Cloud - Compute" \
    --lookback-period-in-days THIRTY_DAYS \
    --term-in-years ONE_YEAR \
    --payment-option NO_UPFRONT

# RDS RI recommendations (3-year, partial upfront)
aws ce get-reservation-purchase-recommendation \
    --service "Amazon Relational Database Service" \
    --term-in-years THREE_YEARS \
    --payment-option PARTIAL_UPFRONT
```

## Savings Plans Analysis

### Savings Plans Utilization

```sh
# Monthly SP utilization
aws ce get-savings-plans-utilization \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY

# Detailed per-plan utilization
aws ce get-savings-plans-utilization-details \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY
```

### Savings Plans Coverage

```sh
# SP coverage grouped by service
aws ce get-savings-plans-coverage \
    --time-period Start=2026-01-01,End=2026-04-01 \
    --granularity MONTHLY \
    --group-by Type=DIMENSION,Key=SERVICE
```

### Savings Plans Purchase Recommendations

**SP types:** `COMPUTE_SP`, `EC2_INSTANCE_SP`, `SAGEMAKER_SP`, `DATABASE_SP`

```sh
aws ce get-savings-plans-purchase-recommendation \
    --savings-plans-type COMPUTE_SP \
    --term-in-years ONE_YEAR \
    --payment-option NO_UPFRONT \
    --lookback-period-in-days THIRTY_DAYS
```

## Cost Anomaly Detection

### Create Anomaly Monitor

**Monitor types:** `DIMENSIONAL` (monitors a dimension like SERVICE), `CUSTOM` (uses an Expression filter)

```sh
# Service-level anomaly monitor
aws ce create-anomaly-monitor \
    --anomaly-monitor '{
        "MonitorName": "ServiceMonitor",
        "MonitorType": "DIMENSIONAL",
        "MonitorDimension": "SERVICE"
    }'

# Custom monitor for a specific account
aws ce create-anomaly-monitor \
    --anomaly-monitor '{
        "MonitorName": "ProductionAccountMonitor",
        "MonitorType": "CUSTOM",
        "MonitorSpecification": {
            "Dimensions": {"Key": "LINKED_ACCOUNT", "Values": ["123456789012"]}
        }
    }'
```

### Create Anomaly Subscription

Subscribe to anomaly alerts via email or SNS.

**Frequency:** `DAILY`, `IMMEDIATE`, `WEEKLY`

```sh
aws ce create-anomaly-subscription \
    --anomaly-subscription '{
        "MonitorArnList": ["arn:aws:ce::123456789012:anomalymonitor/abc123"],
        "Subscribers": [{"Address": "team@example.com", "Type": "EMAIL"}],
        "SubscriptionName": "DailyAnomalyAlerts",
        "Frequency": "DAILY",
        "ThresholdExpression": {
            "Dimensions": {
                "Key": "ANOMALY_TOTAL_IMPACT_ABSOLUTE",
                "Values": ["100"],
                "MatchOptions": ["GREATER_THAN_OR_EQUAL"]
            }
        }
    }'

# SNS subscriber
aws ce create-anomaly-subscription \
    --anomaly-subscription '{
        "MonitorArnList": ["arn:aws:ce::123456789012:anomalymonitor/abc123"],
        "Subscribers": [{"Address": "arn:aws:sns:us-east-1:123456789012:cost-alerts", "Type": "SNS"}],
        "SubscriptionName": "ImmediateAnomalyAlerts",
        "Frequency": "IMMEDIATE"
    }'
```

### Retrieve and Manage Anomalies

```sh
# Get all anomalies in the last 30 days
aws ce get-anomalies \
    --date-interval StartDate=2026-02-24,EndDate=2026-03-26

# Get anomalies with impact > $200
aws ce get-anomalies \
    --date-interval StartDate=2026-02-24 \
    --total-impact NumericOperator=GREATER_THAN,StartValue=200

# List all monitors and subscriptions
aws ce get-anomaly-monitors
aws ce get-anomaly-subscriptions

# Provide feedback on an anomaly
aws ce provide-anomaly-feedback \
    --anomaly-id "anomaly-id-here" \
    --feedback YES  # YES=anomaly, NO=not anomaly, PLANNED_ACTIVITY

# Delete monitor or subscription
aws ce delete-anomaly-monitor --monitor-arn "arn:aws:ce::123456789012:anomalymonitor/abc123"
aws ce delete-anomaly-subscription --subscription-arn "arn:aws:ce::123456789012:anomalysubscription/abc123"
```

## Cost Categories

### Create Cost Category

Define custom categories with rules to classify costs.

```sh
aws ce create-cost-category-definition \
    --name "Environment" \
    --rule-version CostCategoryExpression.v1 \
    --rules '[
        {"Value": "Production", "Rule": {"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": ["111111111111"]}}},
        {"Value": "Development", "Rule": {"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": ["222222222222"]}}},
        {"Value": "Staging", "Rule": {"Tags": {"Key": "Environment", "Values": ["staging"]}}}
    ]' \
    --default-value "Other"
```

### Manage Cost Categories

```sh
# List all cost categories
aws ce list-cost-category-definitions

# Get category names and values with costs
aws ce get-cost-categories \
    --time-period Start=2026-03-01,End=2026-04-01

# Describe a specific cost category
aws ce describe-cost-category-definition \
    --cost-category-arn "arn:aws:ce::123456789012:costcategory/abc123"

# Delete a cost category
aws ce delete-cost-category-definition \
    --cost-category-arn "arn:aws:ce::123456789012:costcategory/abc123"
```

## Cost Allocation Tags

### Manage Cost Allocation Tags

```sh
# List all active cost allocation tags
aws ce list-cost-allocation-tags --status Active

# List user-defined tags only
aws ce list-cost-allocation-tags --type UserDefined

# Activate tags for cost allocation (max 20 per call)
aws ce update-cost-allocation-tags-status \
    --cost-allocation-tags-status '[
        {"TagKey": "Environment", "Status": "Active"},
        {"TagKey": "Project", "Status": "Active"}
    ]'

# Backfill cost data for newly activated tags
aws ce start-cost-allocation-tag-backfill \
    --backfill-from "2026-01-01"

# Check backfill status
aws ce list-cost-allocation-tag-backfill-history
```

## Rightsizing Recommendations

Identifies idle or underutilized EC2 instances and recommends downsizing or termination.

```sh
# Get EC2 rightsizing recommendations
aws ce get-rightsizing-recommendation --service AmazonEC2

# Filter by region
aws ce get-rightsizing-recommendation \
    --service AmazonEC2 \
    --filter '{"Dimensions": {"Key": "REGION", "Values": ["US East (N. Virginia)"]}}'
```

## Commitment Purchase Analysis

Analyze the impact of a planned Savings Plans purchase before buying.

```sh
# Start analysis for max savings
aws ce start-commitment-purchase-analysis \
    --commitment-purchase-analysis-configuration '{
        "SavingsPlansPurchaseAnalysisConfiguration": {
            "AnalysisType": "MAX_SAVINGS",
            "SavingsPlansToAdd": [{
                "PaymentOption": "NO_UPFRONT",
                "SavingsPlansType": "COMPUTE_SP",
                "TermInYears": "ONE_YEAR"
            }],
            "LookbackPeriodInHours": "THIRTY_DAYS"
        }
    }'
```

```sh
# Get analysis results
aws ce get-commitment-purchase-analysis \
    --analysis-id "analysis-id-here"

# List all analyses
aws ce list-commitment-purchase-analyses
```

## Useful jq Patterns

```sh
# Extract total cost per period
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
  | jq '.ResultsByTime[].Total.UnblendedCost.Amount'

# Table of service costs (TSV)
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
  | jq -r '.ResultsByTime[].Groups[] | [.Keys[0], .Metrics.UnblendedCost.Amount] | @tsv' \
  | sort -t$'\t' -k2 -rn

# Get forecast total
aws ce get-cost-forecast \
    --time-period Start=2026-03-26,End=2026-04-26 \
    --metric UNBLENDED_COST \
    --granularity MONTHLY \
  | jq '.Total.Amount'

# Top 10 services by cost
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-04-01 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
  | jq -r '[.ResultsByTime[].Groups[] | {service: .Keys[0], cost: (.Metrics.UnblendedCost.Amount | tonumber)}] | sort_by(-.cost) | .[0:10][] | "\(.cost | tostring | .[0:8])\t\(.service)"'

# Daily cost trend
aws ce get-cost-and-usage \
    --time-period Start=2026-03-01,End=2026-03-27 \
    --granularity DAILY \
    --metrics "UnblendedCost" \
  | jq -r '.ResultsByTime[] | [.TimePeriod.Start, .Total.UnblendedCost.Amount] | @tsv'
```

## Best Practices

| Practice                     | Description                                                    |
| :--------------------------- | :------------------------------------------------------------- |
| **Activate cost alloc tags** | Enable tags like Environment, Team, Project for cost breakdown |
| **Use cost categories**      | Create custom groupings that map to your org structure         |
| **Set up anomaly detection** | DIMENSIONAL monitor on SERVICE catches most spikes             |
| **Exclude credits/refunds**  | Filter out `RECORD_TYPE` credits for true spend analysis       |
| **Use AmortizedCost**        | Better reflects actual spending when using RIs or SPs          |
| **Review rightsizing**       | Check EC2 recommendations monthly for quick savings            |
| **Forecast regularly**       | Use `get-cost-forecast` to catch budget overruns early         |
| **API charges**              | CE API calls are not free: cache results, avoid tight loops   |
| **End date is exclusive**    | `End=2026-04-01` means through March 31, not April 1           |
| **Granularity limits**       | HOURLY only available for last 14 days                         |
