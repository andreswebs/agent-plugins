# Pricing (Price List API)

## Contents

- [Service Discovery](#service-discovery)
- [Attribute Discovery](#attribute-discovery)
- [Product Pricing Queries](#product-pricing-queries)
- [Filter Patterns](#filter-patterns)
- [Price List Files](#price-list-files)
- [Common Service Codes](#common-service-codes)
- [Useful jq Patterns](#useful-jq-patterns)
- [Best Practices](#best-practices)

---

> **Region note:** The Pricing API is only available in `us-east-1` and `ap-south-1`. Always specify `--region us-east-1` (or set it in your profile or env var).

Commands below assume the region has been set (directly or in profile):

```sh
export AWS_REGION="us-east-1"
```

## Service Discovery

### List All Service Codes

```sh
# List all available service codes
aws pricing describe-services \
    --query 'Services[*].ServiceCode' \
    --output json

# Count available services
aws pricing describe-services \
    --query 'length(Services)'

# Search for a service by keyword (e.g., "EC2")
aws pricing describe-services \
    --query 'Services[?contains(ServiceCode, `EC2`)].ServiceCode' \
    --output table
```

### Get Service Attributes

```sh
# List all attribute names for a service
aws pricing describe-services \
    --service-code AmazonEC2 \
    --query 'Services[0].AttributeNames' \
    --output json

# Get attributes for RDS
aws pricing describe-services \
    --service-code AmazonRDS \
    --query 'Services[0].AttributeNames'

# Get attributes for Lambda
aws pricing describe-services \
    --service-code AWSLambda \
    --query 'Services[0].AttributeNames'
```

## Attribute Discovery

### Get Values for an Attribute

```sh
# List all EC2 instance types
aws pricing get-attribute-values \
    --service-code AmazonEC2 \
    --attribute-name instanceType \
    --query 'AttributeValues[*].Value' \
    --output json

# List all available regions (location names)
aws pricing get-attribute-values \
    --service-code AmazonEC2 \
    --attribute-name location \
    --query 'AttributeValues[*].Value' \
    --output table

# List all operating systems for EC2
aws pricing get-attribute-values \
    --service-code AmazonEC2 \
    --attribute-name operatingSystem \
    --query 'AttributeValues[*].Value'

# List all volume types for EC2
aws pricing get-attribute-values \
    --service-code AmazonEC2 \
    --attribute-name volumeType \
    --query 'AttributeValues[*].Value'

# List RDS database engines
aws pricing get-attribute-values \
    --service-code AmazonRDS \
    --attribute-name databaseEngine \
    --query 'AttributeValues[*].Value'

# List S3 storage classes
aws pricing get-attribute-values \
    --service-code AmazonS3 \
    --attribute-name storageClass \
    --query 'AttributeValues[*].Value'
```

## Product Pricing Queries

### EC2 Instance Pricing

```sh
# Get on-demand pricing for a specific EC2 instance type
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=instanceType,Value=m5.xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
        Type=TERM_MATCH,Field=tenancy,Value=Shared \
        Type=TERM_MATCH,Field=capacitystatus,Value=Used \
        Type=TERM_MATCH,Field=preInstalledSw,Value=NA

# Get pricing for a GPU instance
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=instanceType,Value=p4d.24xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
        Type=TERM_MATCH,Field=tenancy,Value=Shared \
        Type=TERM_MATCH,Field=capacitystatus,Value=Used \
        Type=TERM_MATCH,Field=preInstalledSw,Value=NA
```

### RDS Pricing

```sh
# Get RDS pricing for a specific instance class
aws pricing get-products \
    --service-code AmazonRDS \
    --filters \
        Type=TERM_MATCH,Field=instanceType,Value=db.r6g.xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=databaseEngine,Value=Aurora\ MySQL \
        Type=TERM_MATCH,Field=deploymentOption,Value="Single-AZ"
```

### Lambda Pricing

```sh
# Get Lambda pricing
aws pricing get-products \
    --service-code AWSLambda \
    --filters \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
    --max-items 10
```

### S3 Pricing

```sh
# Get S3 storage pricing
aws pricing get-products \
    --service-code AmazonS3 \
    --filters \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=storageClass,Value="General Purpose" \
    --max-items 10
```

### EBS Volume Pricing

```sh
# Get EBS gp3 pricing
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=volumeType,Value="General Purpose" \
        Type=TERM_MATCH,Field=volumeApiName,Value=gp3 \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)"
```

### Data Transfer Pricing

```sh
# Get data transfer pricing
aws pricing get-products \
    --service-code AWSDataTransfer \
    --filters \
        Type=TERM_MATCH,Field=fromLocation,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=toLocation,Value="External" \
    --max-items 5
```

## Filter Patterns

### Filter Types

| Type         | Behavior                              | Example Use                  |
| :----------- | :------------------------------------ | :--------------------------- |
| `TERM_MATCH` | Exact match on field value            | Instance type, region, OS    |
| `EQUALS`     | Exact match (identical to TERM_MATCH) | Service code, attribute name |
| `CONTAINS`   | Substring match                       | Partial names, descriptions  |
| `ANY_OF`     | Match any of multiple values          | Multiple instance types      |
| `NONE_OF`    | Exclude specific values               | Exclude certain regions      |

### Multiple Filters (AND logic)

```sh
# All filters are ANDed together
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=instanceType,Value=m5.xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
        Type=TERM_MATCH,Field=tenancy,Value=Shared
```

### Using CONTAINS Filter

```sh
# Find products with "xlarge" in the instance type
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=CONTAINS,Field=instanceType,Value=xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
    --max-items 20
```

## Price List Files

### List Available Price Lists

```sh
# List EC2 price lists for a region
aws pricing list-price-lists \
    --service-code AmazonEC2 \
    --effective-date 2026-03-01 \
    --currency-code USD

# List EC2 price lists for a specific region
aws pricing list-price-lists \
    --service-code AmazonEC2 \
    --effective-date 2026-03-01 \
    --currency-code USD \
    --region-code us-east-1

# List Savings Plan price lists
aws pricing list-price-lists \
    --service-code ComputeSavingsPlans \
    --effective-date 2026-03-01 \
    --currency-code USD
```

### Get Price List Download URL

```sh
# Get download URL for a specific price list
# (use PriceListArn from list-price-lists output)
aws pricing get-price-list-file-url \
    --price-list-arn "arn:aws:pricing::123456789012:price-list/AmazonEC2/USD/us-east-1" \
    --file-format json

# Download and inspect the price list
URL=$(aws pricing get-price-list-file-url \
    --price-list-arn "$PRICE_LIST_ARN" \
    --file-format json \
    --query 'Url' --output text)
curl -sL "$URL" | jq '.products | length'
```

## Common Service Codes

| Service Code                 | Service                  |
| :--------------------------- | :----------------------- |
| `AmazonEC2`                  | EC2 instances, EBS, IPs  |
| `AmazonRDS`                  | RDS and Aurora           |
| `AmazonS3`                   | S3 storage               |
| `AWSLambda`                  | Lambda functions         |
| `AmazonDynamoDB`             | DynamoDB tables          |
| `AmazonElastiCache`          | ElastiCache              |
| `AmazonEKS`                  | EKS clusters             |
| `AmazonECS`                  | ECS (Fargate pricing)    |
| `AmazonCloudFront`           | CloudFront distributions |
| `AWSDataTransfer`            | Data transfer fees       |
| `AmazonKinesisFirehose`      | Kinesis Firehose         |
| `AmazonMSK`                  | Managed Kafka            |
| `AmazonSageMaker`            | SageMaker                |
| `AmazonRedshift`             | Redshift clusters        |
| `ComputeSavingsPlans`        | Compute Savings Plans    |
| `MachineLearingSavingsPlans` | ML Savings Plans         |

## Useful jq Patterns

```sh
# Extract on-demand hourly price for EC2
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=instanceType,Value=m5.xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
        Type=TERM_MATCH,Field=tenancy,Value=Shared \
        Type=TERM_MATCH,Field=capacitystatus,Value=Used \
        Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
    | jq -r '
        .PriceList[] | fromjson |
        .terms.OnDemand | to_entries[0].value |
        .priceDimensions | to_entries[0].value |
        "\(.description) - $\(.pricePerUnit.USD)/hr"
    '
```

```sh
# Compare pricing across instance types
for INSTANCE in m5.large m5.xlarge m5.2xlarge; do
    PRICE=$(aws pricing get-products \
        --region us-east-1 \
        --service-code AmazonEC2 \
        --filters \
            Type=TERM_MATCH,Field=instanceType,Value=$INSTANCE \
            Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
            Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
            Type=TERM_MATCH,Field=tenancy,Value=Shared \
            Type=TERM_MATCH,Field=capacitystatus,Value=Used \
            Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
        | jq -r '
            .PriceList[] | fromjson |
            .terms.OnDemand | to_entries[0].value |
            .priceDimensions | to_entries[0].value |
            .pricePerUnit.USD
        ')
    echo "$INSTANCE: \$$PRICE/hr"
done

# List all product families for a service
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
    --max-items 100 \
    | jq -r '[.PriceList[] | fromjson | .product.productFamily] | unique[]'

# Extract product attributes and price into a flat summary
aws pricing get-products \
    --service-code AmazonEC2 \
    --filters \
        Type=TERM_MATCH,Field=instanceType,Value=m5.xlarge \
        Type=TERM_MATCH,Field=location,Value="US East (N. Virginia)" \
        Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
        Type=TERM_MATCH,Field=tenancy,Value=Shared \
        Type=TERM_MATCH,Field=capacitystatus,Value=Used \
        Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
    | jq -r '
        .PriceList[] | fromjson |
        {
            instanceType: .product.attributes.instanceType,
            vcpu: .product.attributes.vcpu,
            memory: .product.attributes.memory,
            storage: .product.attributes.storage,
            price: (.terms.OnDemand | to_entries[0].value |
                    .priceDimensions | to_entries[0].value |
                    .pricePerUnit.USD)
        }
    '
```

## Best Practices

- Always specify region `us-east-1` or `ap-south-1`; the Pricing API is only available in those regions
- Use `describe-services` first to discover valid service codes and attribute names
- Use `get-attribute-values` to discover valid filter values before querying products
- Use location names (e.g., `"US East (N. Virginia)"`), not region codes, in filters
- Narrow filters as much as possible; broad queries return large payloads and may be slow
- The `PriceList` entries in `get-products` output are JSON strings; use `jq fromjson` to parse them
- Use `--max-items` to limit results during exploration; remove for complete data
- For bulk pricing data, use `list-price-lists` + `get-price-list-file-url` to download full price files
- Price list files can be very large (hundreds of MB); filter or stream with jq
- Pricing data is updated periodically; use `list-price-lists` with `--effective-date` for point-in-time
