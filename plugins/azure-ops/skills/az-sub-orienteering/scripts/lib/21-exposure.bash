#!/usr/bin/env bash
# Network perimeter, outside-in view: what in this subscription is reachable
# or authenticates weakly, regardless of service.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_21_exposure() {
    report_begin "Exposure: public reachability and weak authentication"

    arg_query public-network-access exposure.kql || true
    arg_query local-auth local-auth.kql || true
    arg_query legacy-tls legacy-tls.kql || true
    run_az_json public-ips network public-ip list || true
    run_az_json nsgs network nsg list || true
    run_az_json dns-zones network dns zone list || true

    emit_section "Public IP addresses"
    emit_table "${AZSD_RAW_DIR}/public-ips.json" "Name|RG|Address|SKU|Allocation|Attached to|DNS label" \
        '.[] | [.name, .resourceGroup, (.ipAddress // "-"), (.sku.name // "-"), (.publicIPAllocationMethod // .publicIpAllocationMethod // "-"), ((.ipConfiguration.id // .natGateway.id // "-") | split("/") | .[-3:] | join("/")), (.dnsSettings.fqdn // "-")]'

    emit_section "Public IPs not attached to anything"
    emit_table "${AZSD_RAW_DIR}/public-ips.json" "Name|RG|Address" \
        '.[] | select(.ipConfiguration == null and .natGateway == null) | [.name, .resourceGroup, (.ipAddress // "-")]'

    emit_section "NSG inbound rules open to any source"
    emit_table_from "${AZSD_RAW_DIR}/nsgs.json" "NSG|Rule|Priority|Source|Ports|Protocol|Subnets|NICs" "nsg-permissive-rules.jq"

    emit_section "PaaS resources with public network access enabled"
    emit "From Resource Graph. A private endpoint elsewhere does not by itself close this; the setting must be Disabled."
    emit ""
    emit_columns "${AZSD_RAW_DIR}/public-network-access.json" "Type|Name|RG|Location|Signal" "type|name|resourceGroup|location|signal"

    emit_section "Local (non-Entra) authentication"
    emit_columns "${AZSD_RAW_DIR}/local-auth.json" "Type|Name|RG|Local auth" "type|name|resourceGroup|localAuth"

    emit_section "Minimum TLS below 1.2"
    emit_columns "${AZSD_RAW_DIR}/legacy-tls.json" "Type|Name|RG|Min TLS" "type|name|resourceGroup|tls"

    emit_section "Public DNS zones"
    emit "Names published here are the externally discoverable surface."
    emit ""
    emit_columns "${AZSD_RAW_DIR}/dns-zones.json" "Zone|RG|Record sets|Name servers" "name|resourceGroup|numberOfRecordSets|nameServers"

    return 0
}

function module_21_exposure_types() {
    echo "Microsoft.Network/publicIPAddresses"
    echo "Microsoft.Network/networkSecurityGroups"
    echo "Microsoft.Network/dnszones"
}
