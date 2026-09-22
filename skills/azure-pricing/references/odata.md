# OData Filter Syntax for Azure Retail Prices API

The API uses [OData v4 `$filter`](https://www.odata.org/documentation/) query parameters. Filters are passed as a single `$filter` query parameter and must be URL-encoded.

## Operators

### Comparison

| Operator | Meaning               | Example                      |
| -------- | --------------------- | ---------------------------- |
| `eq`     | Equals                | `serviceName eq 'Key Vault'` |
| `ne`     | Not equals            | `priceType ne 'Reservation'` |
| `gt`     | Greater than          | `retailPrice gt 0`           |
| `ge`     | Greater than or equal | `retailPrice ge 0.01`        |
| `lt`     | Less than             | `retailPrice lt 1`           |
| `le`     | Less than or equal    | `retailPrice le 0.5`         |

### Logical

| Operator | Meaning | Example                                                    |
| -------- | ------- | ---------------------------------------------------------- |
| `and`    | AND     | `serviceName eq 'Key Vault' and armRegionName eq 'eastus'` |
| `or`     | OR      | `skuName eq 'Standard' or skuName eq 'Premium'`            |

Parentheses group expressions: `(skuName eq 'A' or skuName eq 'B') and armRegionName eq 'eastus'`

### String Functions

| Function     | Meaning         | Example                             |
| ------------ | --------------- | ----------------------------------- |
| `contains`   | Substring match | `contains(productName, 'Redis')`    |
| `startswith` | Prefix match    | `startswith(meterName, 'Standard')` |
| `endswith`   | Suffix match    | `endswith(meterName, 'Hours')`      |

`contains` is the most useful — it works as a fallback when the exact `serviceName` is unknown.

## Filterable Fields

These fields can be used in `$filter` expressions:

| Field           | Type   | Notes                                              |
| --------------- | ------ | -------------------------------------------------- |
| `serviceName`   | string | Azure service category                             |
| `productName`   | string | Specific product within the service                |
| `skuName`       | string | SKU or tier name                                   |
| `meterName`     | string | What is being metered                              |
| `armRegionName` | string | Azure region; empty for global services            |
| `currencyCode`  | string | e.g., `USD`, `EUR`, `GBP`                          |
| `priceType`     | string | `Consumption`, `Reservation`, `DevTestConsumption` |

## URL Encoding

The filter string must be URL-encoded in the query parameter:

| Character | Encoded |
| --------- | ------- |
| space     | `%20`   |
| `'`       | `%27`   |
| `(`       | `%28`   |
| `)`       | `%29`   |
| `,`       | `%2C`   |

### Example

Raw filter:

```txt
serviceName eq 'Key Vault' and armRegionName eq 'eastus' and currencyCode eq 'USD'
```

URL-encoded:

```txt
serviceName%20eq%20%27Key%20Vault%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20currencyCode%20eq%20%27USD%27
```

Full URL:

```txt
https://prices.azure.com/api/retail/prices?$filter=serviceName%20eq%20%27Key%20Vault%27%20and%20armRegionName%20eq%20%27eastus%27%20and%20currencyCode%20eq%20%27USD%27
```

## Pagination

The API supports `$skip` for pagination (automatically included in `NextPageLink`). There is no `$top` parameter — the API always returns up to 1,000 items per page.
