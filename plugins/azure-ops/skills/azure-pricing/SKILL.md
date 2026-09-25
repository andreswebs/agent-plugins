---
name: azure-pricing
description: >
  Gather Azure service pricing data from the public Azure Retail Prices REST API.
  Use when the user needs cost estimates, pricing comparisons, or budgeting for
  Azure services — even if they don't explicitly mention "retail prices API."
  Covers querying the API, handling pagination, working around services that use
  non-obvious naming, filtering results with jq, and building cost estimates
  from raw pricing data.
compatibility: Requires curl and jq.
---

# Azure Retail Prices API

The [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices) is a public REST endpoint that returns pay-as-you-go pricing for all Azure services. No authentication required.

**Endpoint**: `https://prices.azure.com/api/retail/prices`

## When to Use

- Gather unit prices for Azure services
- Build cost estimates or budgets
- Compare pricing across regions, SKUs, or tiers
- Produce raw pricing data for spreadsheet import
- Verify Azure pricing assumptions with authoritative data

## API Basics

### Request Format

```txt
GET https://prices.azure.com/api/retail/prices?$filter=<OData filter>&currencyCode=<code>
```

Query parameters use OData `$filter` syntax. URL-encode the filter string (spaces as `%20`, quotes as `%27`). See [references/odata.md](references/odata.md) for the full OData filter syntax, operators, filterable fields, and URL-encoding rules.

### Response Shape

```json
{
  "Items": [
    {
      "retailPrice": 0.025,
      "unitPrice": 0.025,
      "armRegionName": "eastus",
      "skuName": "Standard",
      "meterName": "Operations",
      "productName": "Key Vault",
      "serviceName": "Key Vault",
      "unitOfMeasure": "10K",
      "priceType": "Consumption",
      "currencyCode": "USD"
    }
  ],
  "NextPageLink": "https://prices.azure.com/...&$skip=1000",
  "Count": 17
}
```

Key fields:

- `retailPrice` / `unitPrice` — the price (usually identical for PAYG)
- `serviceName` — the Azure service category
- `productName` — the specific product within the service
- `skuName` — the SKU or tier
- `meterName` — what is being metered (e.g., "vCPU Hours", "Data Stored")
- `unitOfMeasure` — the billing unit (e.g., "1 Hour", "1 GB", "10K", "1M")
- `armRegionName` — the Azure region (empty string for global services)
- `priceType` — "Consumption" (PAYG), "Reservation", or "DevTestConsumption"

### Pagination

The API returns a maximum of **1,000 items per page**. If there are more results, the response includes a `NextPageLink` field. Always check for it:

```bash
# Check if response is paginated
jq --raw-output '.NextPageLink // "none"' response.json

# Fetch next page
curl --silent "$(jq --raw-output '.NextPageLink' response.json)" > response-p2.json
```

Follow `NextPageLink` until it is `null`.

### Verification Script

After collecting data, verify all files have content:

```bash
for f in *.json; do
  count=$(jq '.Items | length' "$f" 2>/dev/null || echo "PARSE_ERROR")
  echo "$f: $count items"
done
```

Check for truncated data:

```bash
for f in *.json; do
  next=$(jq --raw-output '.NextPageLink // "none"' "$f" 2>/dev/null)
  if [[ "$next" != "none" && "$next" != "null" ]]; then
    echo "PAGINATED: $f"
  fi
done
```

## Writing Filters

### Common Filter Patterns

**By service name and region** (most common):

```
serviceName eq 'Key Vault' and armRegionName eq 'eastus' and currencyCode eq 'USD'
```

**PAYG only** (exclude reservations):

```
serviceName eq 'Service Bus' and armRegionName eq 'eastus' and currencyCode eq 'USD' and priceType eq 'Consumption'
```

**Substring match** (when exact `serviceName` is unknown):

```
contains(productName, 'Redis') and armRegionName eq 'eastus' and currencyCode eq 'USD'
```

**Global services** (no region filter — e.g., Front Door, Defender, DNS):

```
serviceName eq 'Azure Front Door Service' and currencyCode eq 'USD'
```

### curl Example

```bash
curl --silent 'https://prices.azure.com/api/retail/prices?$filter=serviceName%20eq%20%27Key%20Vault%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20currencyCode%20eq%20%27USD%27' \
  | tee output.json \
  | jq '[.Items[] | {skuName, meterName, unitOfMeasure, retailPrice}]'
```

### Useful jq Extraction Patterns

**Summary view** (the default — use for most services):

```bash
jq '[.Items[] | {skuName, meterName, unitOfMeasure, retailPrice}]' data.json
```

**With product name** (when the service has sub-products):

```bash
jq '[.Items[] | {productName, skuName, meterName, unitOfMeasure, retailPrice}]' data.json
```

**Unique product names** (discover what's inside a large dataset):

```bash
jq '[.Items[].productName] | unique' data.json
```

**Unique meter names** (understand billing dimensions):

```bash
jq '[.Items[].meterName] | unique' data.json
```

**Filter by SKU locally** (faster than re-querying the API):

```bash
jq '[.Items[] | select(.skuName | test("Premium|Standard"; "i")) | {skuName, meterName, unitOfMeasure, retailPrice}]' data.json
```

**Deduplicate by meter** (some services have duplicates across regions):

```bash
jq '[.Items[] | {skuName, meterName, unitOfMeasure, retailPrice}] | unique_by(.meterName)' data.json
```

**Filter by region locally** (when querying a global service):

```bash
jq '[.Items[] | select(.armRegionName == "eastus") | {skuName, meterName, unitOfMeasure, retailPrice}]' data.json
```

## Known Gotchas

These issues were discovered through real data-gathering experience. They are not documented in the API reference.

### 1. Service Name Mismatches

Some Azure services are **not queryable by their marketing name** using `serviceName eq '...'`. The `serviceName` field uses internal catalog names that don't always match what you'd expect.

**Known mismatches:**

| Marketing Name        | Works with `serviceName eq`? | Workaround                        |
| --------------------- | :--------------------------: | --------------------------------- |
| Azure Managed Redis   |              No              | `contains(productName, 'Redis')`  |
| Azure Cache for Redis |              No              | `contains(productName, 'Redis')`  |
| Azure OpenAI Service  |              No              | `contains(productName, 'OpenAI')` |
| NAT Gateway           |    No (not in API at all)    | Use published pricing page        |

When a query returns 0 items, try these fallbacks in order:

1. Use `contains(productName, '<keyword>')` instead of `serviceName eq`
2. Use `contains(serviceName, '<keyword>')` for partial matches
3. Check if the service is a global service and remove the `armRegionName` filter
4. Check the [Azure pricing page](https://azure.microsoft.com/en-us/pricing/) — the service may not be in the API

### 2. Services Not in the API

Some services have **no entries at all** in the Retail Prices API. NAT Gateway is a known example. For these, document the pricing manually from the official Azure pricing page and note the source.

### 3. Global Services Have No Region

Some services are global and have an empty `armRegionName`. If you filter by region and get 0 results, try removing the `armRegionName` filter:

**Known global services:**

- Azure Front Door Service
- Microsoft Defender for Cloud
- Azure DNS

For global services, filter results locally by region after fetching:

```bash
jq '[.Items[] | select(.armRegionName == "eastus" or .armRegionName == "")]' data.json
```

### 4. Large Result Sets and Pagination

Some services return thousands of items across multiple pages:

| Service                      | Approximate Items | Pages |
| ---------------------------- | ----------------: | ----: |
| Storage                      |            ~1,500 |     2 |
| Microsoft Defender for Cloud |            ~2,300 |     3 |
| Azure Front Door Service     |              ~340 |     1 |
| Azure OpenAI (via contains)  |              ~800 |     1 |

Always check `NextPageLink` and follow pagination. Save each page to a separate file (e.g., `service.json`, `service-p2.json`, `service-p3.json`).

To combine pages for local filtering:

```bash
cat service.json service-p2.json service-p3.json | \
  jq --slurp '[.[].Items[]] | length'
```

### 5. Reservation vs. PAYG Prices

Many services return both pay-as-you-go and reservation prices. Reservation prices are dramatically higher per-unit because they cover longer periods (1-year, 3-year). To get only PAYG:

- Add `priceType eq 'Consumption'` to the filter, or
- Filter locally: `select(.priceType == "Consumption")`

Note: not all services support this filter. Some (like Key Vault) don't have a `priceType` distinction.

### 6. Duplicate Entries

Some services return multiple entries for the same meter at the same price — often because the API includes both current and legacy SKU records, or entries for multiple pricing tiers (e.g., tiered pricing at different volume levels with a zero price for the free tier and the actual price for the paid tier). Use `unique_by(.meterName)` or inspect duplicates manually.

## Converting Prices to Monthly Costs

Standard conversion factors:

| Unit               | Conversion                  |
| ------------------ | --------------------------- |
| per hour           | × 730 (hours/month)         |
| per day            | × 30.4 (days/month)         |
| per GB/month       | direct (already monthly)    |
| per second         | × 2,628,000 (seconds/month) |
| per 10K operations | estimate operation volume   |
| per 1M queries     | estimate query volume       |

## Workflow

1. **Identify services** — list every Azure service to price
2. **Choose tiers** — determine the SKU/tier per environment (e.g., dev vs prod)
3. **Query the API** — one query per service, save raw JSON
4. **Verify** — check item counts, pagination, and 0-result queries
5. **Fix broken queries** — use the fallback strategies from Known Gotchas
6. **Extract prices** — use jq to pull relevant SKU prices from the raw data
7. **Calculate monthly costs** — apply usage assumptions and conversion factors
8. **Document** — produce the cost estimate with sources and assumptions
