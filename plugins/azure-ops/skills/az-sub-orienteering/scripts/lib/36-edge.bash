#!/usr/bin/env bash
# Edge and ingress: load balancers, gateways, CDN, API Management.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_36_edge() {
    report_begin "Edge and ingress"

    emit_section "Load balancers"
    if ! skip_if_absent "Microsoft.Network/loadBalancers"; then
        run_az_json lbs network lb list || true
        emit_table "${AZSD_RAW_DIR}/lbs.json" "Name|RG|SKU|Public frontends|Private frontends|Rules|Inbound NAT" \
            '.[] | [.name, .resourceGroup, (.sku.name // "-"), ((.frontendIPConfigurations // .frontendIpConfigurations // []) | map(select(.publicIPAddress != null or .publicIpAddress != null)) | length), ((.frontendIPConfigurations // .frontendIpConfigurations // []) | map(select(.privateIPAddress != null or .privateIpAddress != null)) | length), ((.loadBalancingRules // []) | length), ((.inboundNatRules // []) | length)]'
    fi

    emit_section "Application Gateways and WAF policies"
    if ! skip_if_absent "Microsoft.Network/applicationGateways" "Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies"; then
        run_az_json appgw network application-gateway list || true
        run_az_json appgw-waf network application-gateway waf-policy list || true
        emit_table "${AZSD_RAW_DIR}/appgw.json" "Name|RG|SKU|Tier|Capacity|WAF policy|Listeners|State" \
            '.[] | [.name, .resourceGroup, (.sku.name // "-"), (.sku.tier // "-"), (.sku.capacity // .autoscaleConfiguration.maxCapacity // "-"), ((.firewallPolicy.id // "-") | split("/") | last), ((.httpListeners // []) | length), (.operationalState // "-")]'
        emit ""
        emit_table "${AZSD_RAW_DIR}/appgw-waf.json" "WAF policy|RG|State|Mode|Managed rule sets" \
            '.[] | [.name, .resourceGroup, (.policySettings.state // "-"), (.policySettings.mode // "-"), ((.managedRules.managedRuleSets // []) | map("\(.ruleSetType) \(.ruleSetVersion)") | join(", "))]'
    fi

    emit_section "Front Door and CDN"
    if ! skip_if_absent "Microsoft.Cdn/profiles" "Microsoft.Network/frontDoors" "Microsoft.Network/FrontDoorWebApplicationFirewallPolicies"; then
        run_az_json afd afd profile list || true
        run_az_json afd-endpoints resource list --resource-type "Microsoft.Cdn/profiles/afdEndpoints" || true
        run_az_json fd-waf resource list --resource-type "Microsoft.Network/FrontDoorWebApplicationFirewallPolicies" || true
        emit_columns "${AZSD_RAW_DIR}/afd.json" "Profile|RG|SKU|State" "name|resourceGroup|sku.name|provisioningState"
        emit ""
        emit_columns "${AZSD_RAW_DIR}/afd-endpoints.json" "Endpoint|RG" "name|resourceGroup"
        emit ""
        emit_columns "${AZSD_RAW_DIR}/fd-waf.json" "Front Door WAF policy|RG|SKU" "name|resourceGroup|sku.name"
    fi

    emit_section "API Management"
    if ! skip_if_absent "Microsoft.ApiManagement/service"; then
        run_az_json apim apim list || true
        emit_table "${AZSD_RAW_DIR}/apim.json" "Name|RG|SKU|Units|VNet type|Public access|Gateway URL" \
            '.[] | [.name, .resourceGroup, (.sku.name // "-"), (.sku.capacity // "-"), (.virtualNetworkType // "-"), (.publicNetworkAccess // "-"), (.gatewayUrl // "-")]'
    fi

    return 0
}

function module_36_edge_types() {
    cat <<'EOF'
Microsoft.Network/loadBalancers
Microsoft.Network/applicationGateways
Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies
Microsoft.Network/frontDoors
Microsoft.Network/FrontDoorWebApplicationFirewallPolicies
Microsoft.Cdn/profiles
Microsoft.Cdn/profiles/afdEndpoints
Microsoft.ApiManagement/service
Microsoft.Network/trafficManagerProfiles
EOF
}
