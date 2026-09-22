# Cost Management query response -> rows [dimension, cost, currency], descending.
# Column order follows .properties.columns; grouping dimension is whichever
# column is neither the cost nor the currency.

.properties as $p
| ($p.columns | map(.name)) as $cols
| (($cols | index("PreTaxCost")) // ($cols | index("Cost"))) as $ci
| ($cols | index("Currency")) as $cu
| ($cols | to_entries | map(select(.value != "PreTaxCost" and .value != "Cost" and .value != "Currency")) | .[0].key) as $di
| [ ($p.rows // [])[]
    | [ .[$di], ((.[$ci] * 100 | round) / 100), (if $cu == null then "-" else .[$cu] end) ]
  ]
| sort_by(-.[1])
