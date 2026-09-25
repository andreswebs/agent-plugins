#!/usr/bin/env bash
# Network topology, inside-out view: VNets, subnets, peerings, gateways, private link.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_22_network() {
    report_begin "Network topology"

    run_az_json vnets network vnet list || true
    run_az_json private-endpoints network private-endpoint list || true
    run_az_json nat-gateways network nat gateway list || true
    # Route tables, gateways and connections are RG-scoped at the CLI and their
    # properties are not expanded by `resource list`, so both the route-table
    # contents and the gateway SKU come back empty. One Resource Graph call
    # returns every one of them with properties intact.
    arg_query network-detail network-detail.kql || true
    # extension-backed or RG-scoped commands: read the resource type directly
    run_az_json private-dns-zones resource list --resource-type "Microsoft.Network/privateDnsZones" || true
    run_az_json firewalls resource list --resource-type "Microsoft.Network/azureFirewalls" || true
    run_az_json ddos-plans resource list --resource-type "Microsoft.Network/ddosProtectionPlans" || true
    run_az_json bastions resource list --resource-type "Microsoft.Network/bastionHosts" || true
    run_az_json dns-resolvers resource list --resource-type "Microsoft.Network/dnsResolvers" || true

    emit_section "Virtual networks"
    emit_table "${AZSD_RAW_DIR}/vnets.json" "Name|RG|Location|Address space|Custom DNS|Subnets|Peerings|DDoS" \
        '.[] | [.name, .resourceGroup, .location, ((.addressSpace.addressPrefixes // []) | join(", ")), ((.dhcpOptions.dnsServers // []) | join(", ")), ((.subnets // []) | length), ((.virtualNetworkPeerings // []) | length), ((.enableDdosProtection // false) | tostring)]'

    emit_section "Subnets"
    emit_table_from "${AZSD_RAW_DIR}/vnets.json" "VNet|Subnet|Prefix|NSG|Route table|Delegation|Service endpoints|PE policy" "subnets.jq"

    emit_section "Subnets without an NSG"
    # shellcheck disable=SC2016  # jq program
    emit_table "${AZSD_RAW_DIR}/vnets.json" "VNet|Subnet|Prefix|Delegation" \
        '.[] as $v | ($v.subnets // [])[] | select(.networkSecurityGroup == null) | [$v.name, .name, (.addressPrefix // "-"), ((.delegations // []) | map(.serviceName) | join(","))]'

    emit_section "VNet peerings"
    # shellcheck disable=SC2016  # jq program
    emit_table "${AZSD_RAW_DIR}/vnets.json" "VNet|Peering|State|Remote VNet|Remote subscription|Fwd traffic|Gateway transit|Use remote GW" \
        '.[] as $v | ($v.virtualNetworkPeerings // [])[] | [$v.name, .name, .peeringState, (.remoteVirtualNetwork.id | split("/") | last), (.remoteVirtualNetwork.id | split("/") | .[2]), (.allowForwardedTraffic // false), (.allowGatewayTransit // false), (.useRemoteGateways // false)]'

    emit_section "Route tables"
    emit "No route table on a subnet means that subnet egresses directly, without a firewall or NVA in the path."
    emit ""
    # shellcheck disable=SC2016  # jq program
    emit_table "${AZSD_RAW_DIR}/network-detail.json" "Name|RG|Routes|Subnets|Default route next hop" \
        '.[] | select(.type == "microsoft.network/routetables") | [.name, .resourceGroup, ((.properties.routes // []) | length), ((.properties.subnets // []) | length), (((.properties.routes // []) | map(select(.addressPrefix == "0.0.0.0/0")) | .[0] | "\(.nextHopType) \(.nextHopIpAddress // "")") // "-")]'

    emit_section "VPN and ExpressRoute gateways"
    # shellcheck disable=SC2016  # jq program
    emit_table "${AZSD_RAW_DIR}/network-detail.json" "Name|RG|Location|SKU|Type|VPN type|Generation|Active-active|BGP" \
        '.[] | select(.type == "microsoft.network/virtualnetworkgateways") | [.name, .resourceGroup, .location, (.properties.sku.name // "-"), (.properties.gatewayType // "-"), (.properties.vpnType // "-"), (.properties.vpnGatewayGeneration // "-"), ((.properties.activeActive // false) | tostring), ((.properties.enableBgp // false) | tostring)]'

    emit_section "Remote networks reached over a gateway"
    emit "A local network gateway defines the far side of a site-to-site link: the public address of the remote device and the address space it advertises. These are networks the estate trusts and that this sweep cannot see into."
    emit ""
    # shellcheck disable=SC2016  # jq program
    emit_table "${AZSD_RAW_DIR}/network-detail.json" "Name|RG|Remote gateway address|Remote address space|BGP ASN" \
        '.[] | select(.type == "microsoft.network/localnetworkgateways") | [.name, .resourceGroup, (.properties.gatewayIpAddress // "-"), ((.properties.localNetworkAddressSpace.addressPrefixes // []) | join(", ")), (.properties.bgpSettings.asn // "-")]'

    emit_section "Gateway connections"
    emit "A connection reporting **Connected** is carrying traffic now. Byte counters are cumulative since the connection was last reset."
    emit ""
    # shellcheck disable=SC2016  # jq program
    emit_table "${AZSD_RAW_DIR}/network-detail.json" "Name|RG|Status|Type|Protocol|Local gateway|Remote|BGP|In bytes|Out bytes" \
        '.[] | select(.type == "microsoft.network/connections") | [.name, .resourceGroup, (.properties.connectionStatus // "-"), (.properties.connectionType // "-"), (.properties.connectionProtocol // "-"), ((.properties.virtualNetworkGateway1.id // "-") | split("/") | last), ((.properties.localNetworkGateway2.id // .properties.virtualNetworkGateway2.id // "-") | split("/") | last), ((.properties.enableBgp // false) | tostring), (.properties.ingressBytesTransferred // "-"), (.properties.egressBytesTransferred // "-")]'

    emit_section "Firewalls, bastions, resolvers"
    local f
    for f in firewalls bastions dns-resolvers ddos-plans nat-gateways; do
        emit_subsection "${f}"
        emit_columns "${AZSD_RAW_DIR}/${f}.json" "Name|RG|Location|SKU" "name|resourceGroup|location|sku.name"
    done

    emit_section "Private endpoints"
    emit_table "${AZSD_RAW_DIR}/private-endpoints.json" "Name|RG|Subnet|Target|Group|State" \
        '.[] | [.name, .resourceGroup, ((.subnet.id // "-") | split("/") | last), (((.privateLinkServiceConnections // .manualPrivateLinkServiceConnections // [])[0].privateLinkServiceId // "-") | split("/") | .[-2:] | join("/")), (((.privateLinkServiceConnections // [])[0].groupIds // []) | join(",")), ((.privateLinkServiceConnections // [])[0].privateLinkServiceConnectionState.status // "-")]'

    emit_section "Private DNS zones"
    emit_table "${AZSD_RAW_DIR}/private-dns-zones.json" "Zone|RG|Record sets|VNet links" \
        '.[] | [.name, .resourceGroup, (.properties.numberOfRecordSets // "-"), (.properties.numberOfVirtualNetworkLinks // "-")]'

    return 0
}

function module_22_network_types() {
    cat <<'EOF'
Microsoft.Network/virtualNetworks
Microsoft.Network/routeTables
Microsoft.Network/privateEndpoints
Microsoft.Network/natGateways
Microsoft.Network/privateDnsZones
Microsoft.Network/privateDnsZones/virtualNetworkLinks
Microsoft.Network/virtualNetworkGateways
Microsoft.Network/localNetworkGateways
Microsoft.Network/connections
Microsoft.Network/azureFirewalls
Microsoft.Network/firewallPolicies
Microsoft.Network/ddosProtectionPlans
Microsoft.Network/bastionHosts
Microsoft.Network/dnsResolvers
Microsoft.Network/networkInterfaces
Microsoft.Network/networkWatchers
EOF
}
