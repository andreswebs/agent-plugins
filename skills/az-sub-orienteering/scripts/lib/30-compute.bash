#!/usr/bin/env bash
# Compute: VMs, scale sets, AKS, Container Apps, App Service, Container Registry.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_30_compute() {
    report_begin "Compute and hosting"

    emit_section "Virtual machines"
    if ! skip_if_absent "Microsoft.Compute/virtualMachines"; then
        run_az_json vms vm list || true
        emit_table "${AZSD_RAW_DIR}/vms.json" "Name|RG|Size|OS|Image|Identity|Zones|Extensions" \
            '.[] | [.name, .resourceGroup, (.hardwareProfile.vmSize // "-"), (.storageProfile.osDisk.osType // "-"), ((.storageProfile.imageReference // {}) | "\(.publisher // "")/\(.offer // "")/\(.sku // "")"), (.identity.type // "None"), ((.zones // []) | join(",")), ((.resources // []) | map(.name | split("/") | last) | join(", "))]'
    fi

    emit_section "Virtual machine scale sets"
    if ! skip_if_absent "Microsoft.Compute/virtualMachineScaleSets"; then
        run_az_json vmss vmss list || true
        emit_table "${AZSD_RAW_DIR}/vmss.json" "Name|RG|SKU|Capacity|Orchestration|Upgrade policy" \
            '.[] | [.name, .resourceGroup, (.sku.name // "-"), (.sku.capacity // "-"), (.orchestrationMode // "-"), (.upgradePolicy.mode // "-")]'
    fi

    emit_section "AKS clusters"
    if ! skip_if_absent "Microsoft.ContainerService/managedClusters"; then
        run_az_json aks aks list || true
        emit_table "${AZSD_RAW_DIR}/aks.json" "Name|RG|Version|Private API|Local accounts|Entra RBAC|Network plugin|Policy|Node pools" \
            '.[] | [.name, .resourceGroup, (.kubernetesVersion // "-"), (.apiServerAccessProfile.enablePrivateCluster // false), (if .disableLocalAccounts == true then "disabled" else "enabled" end), (.aadProfile.enableAzureRbac // false), (.networkProfile.networkPlugin // "-"), (.networkProfile.networkPolicy // "-"), ((.agentPoolProfiles // []) | map("\(.name):\(.count)x\(.vmSize)") | join(", "))]'
    fi

    emit_section "Container Apps"
    if ! skip_if_absent "Microsoft.App/containerApps"; then
        arg_query container-apps container-apps.kql || true
        emit_columns "${AZSD_RAW_DIR}/container-apps.json" "Name|RG|Environment|External ingress|Port|Min|Max|Identity" \
            "name|resourceGroup|env|external|port|minReplicas|maxReplicas|identityType"
    fi

    emit_section "App Service plans and apps"
    if ! skip_if_absent "Microsoft.Web/sites" "Microsoft.Web/serverfarms"; then
        run_az_json plans appservice plan list || true
        run_az_json webapps webapp list || true
        emit_columns "${AZSD_RAW_DIR}/plans.json" "Plan|RG|SKU|Workers|Kind" "name|resourceGroup|sku.name|sku.capacity|kind"
        emit ""
        emit_table "${AZSD_RAW_DIR}/webapps.json" "App|RG|Kind|State|HTTPS only|Public access|Identity|Host names" \
            '.[] | [.name, .resourceGroup, (.kind // "-"), (.state // "-"), (.httpsOnly // false), (.publicNetworkAccess // "-"), (.identity.type // "None"), ((.enabledHostNames // []) | join("<br>"))]'
    fi

    emit_section "Container registries"
    if ! skip_if_absent "Microsoft.ContainerRegistry/registries"; then
        run_az_json acr acr list || true
        emit_table "${AZSD_RAW_DIR}/acr.json" "Name|RG|SKU|Admin user|Anonymous pull|Public access|Login server" \
            '.[] | [.name, .resourceGroup, (.sku.name // "-"), (.adminUserEnabled // false), (.anonymousPullEnabled // false), (.publicNetworkAccess // "-"), (.loginServer // "-")]'
    fi

    return 0
}

function module_30_compute_types() {
    cat <<'EOF'
Microsoft.Compute/virtualMachines
Microsoft.Compute/virtualMachines/extensions
Microsoft.Compute/virtualMachineScaleSets
Microsoft.Compute/disks
Microsoft.Compute/snapshots
Microsoft.Compute/sshPublicKeys
Microsoft.ContainerService/managedClusters
Microsoft.App/containerApps
Microsoft.App/managedEnvironments
Microsoft.App/jobs
Microsoft.Web/sites
Microsoft.Web/sites/slots
Microsoft.Web/serverfarms
Microsoft.ContainerRegistry/registries
EOF
}
