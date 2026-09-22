# Flatten az resource list into CSV rows with a header line.
["name", "type", "kind", "location", "resource_group", "sku_name", "sku_tier", "identity", "tags"],
(.[] | [
    .name,
    .type,
    (.kind // ""),
    .location,
    .resourceGroup,
    (.sku.name // ""),
    (.sku.tier // ""),
    (.identity.type // ""),
    ((.tags // {}) | to_entries | map("\(.key)=\(.value)") | join(";"))
])
| @csv
