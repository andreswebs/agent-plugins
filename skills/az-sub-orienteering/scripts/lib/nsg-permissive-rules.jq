# Inbound Allow rules reachable from anywhere. Input: az network nsg list.
# Rows: [nsg, rule, priority, source, ports, protocol, attached subnets, attached NICs]

def any_source:
    (.sourceAddressPrefix // "" | IN("*", "Internet", "0.0.0.0/0", "::/0"))
    or ((.sourceAddressPrefixes // []) | any(IN("*", "Internet", "0.0.0.0/0", "::/0")));

def ports:
    if (.destinationPortRanges // []) | length > 0 then (.destinationPortRanges | join(","))
    else (.destinationPortRange // "*")
    end;

[ .[] as $nsg
  | ($nsg.securityRules // [])[]
  | select(.direction == "Inbound" and .access == "Allow" and any_source)
  | [
      $nsg.name,
      .name,
      .priority,
      (.sourceAddressPrefix // ((.sourceAddressPrefixes // []) | join(","))),
      ports,
      .protocol,
      (($nsg.subnets // []) | length),
      (($nsg.networkInterfaces // []) | length)
    ]
]
| sort_by(.[0], .[2])
