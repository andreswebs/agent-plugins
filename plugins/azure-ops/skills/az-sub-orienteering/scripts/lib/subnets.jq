# Every subnet across all VNets. Input: az network vnet list.
# Rows: [vnet, subnet, prefix, nsg, route table, delegation, service endpoints, private endpoint policy]

def last_segment: if . == null then "-" else split("/") | last end;

[ .[] as $v
  | ($v.subnets // [])[]
  | [
      $v.name,
      .name,
      (.addressPrefix // ((.addressPrefixes // []) | join(","))),
      (.networkSecurityGroup.id | last_segment),
      (.routeTable.id | last_segment),
      ((.delegations // []) | map(.serviceName) | join(",")),
      ((.serviceEndpoints // []) | map(.service) | join(",")),
      (.privateEndpointNetworkPolicies // "-")
    ]
]
