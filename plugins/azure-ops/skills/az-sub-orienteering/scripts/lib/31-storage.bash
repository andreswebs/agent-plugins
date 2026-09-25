#!/usr/bin/env bash
# Storage accounts: the most commonly exposed managed service.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_31_storage() {
    report_begin "Storage accounts"

    if skip_if_absent "Microsoft.Storage/storageAccounts"; then
        return 0
    fi

    run_az_json accounts storage account list || true

    emit_section "Accounts"
    emit_table "${AZSD_RAW_DIR}/accounts.json" "Name|RG|Kind|SKU|HNS|Public access|Default action|Blob public|Shared key|Min TLS|HTTPS only|Infra encryption" \
        '.[] | [.name, .resourceGroup, .kind, .sku.name, (.isHnsEnabled // false), (.publicNetworkAccess // "-"), (.networkRuleSet.defaultAction // "-"), (.allowBlobPublicAccess // false), (if .allowSharedKeyAccess == false then "disabled" else "enabled" end), (.minimumTlsVersion // "-"), (.enableHttpsTrafficOnly // false), (.encryption.requireInfrastructureEncryption // false)]'

    emit_section "Network rules"
    emit_table "${AZSD_RAW_DIR}/accounts.json" "Name|Default action|Bypass|IP rules|VNet rules|Private endpoints" \
        '.[] | [.name, (.networkRuleSet.defaultAction // "-"), (.networkRuleSet.bypass // "-"), ((.networkRuleSet.ipRules // []) | map(.ipAddressOrRange) | join(", ")), ((.networkRuleSet.virtualNetworkRules // []) | length), ((.privateEndpointConnections // []) | length)]'

    emit_section "Blob containers per account"
    emit "Listing needs data-plane RBAC (Storage Blob Data Reader) on each account; a failure here is a permissions fact, not an empty account."
    local acc
    while IFS=$'\t' read -r acc _rg _rid; do
        [ -z "${acc}" ] && continue
        emit_subsection "${acc}"
        if ! run_az_json "containers-${acc}" storage container list --account-name "${acc}" --auth-mode login; then
            emit "_(could not list; see raw/${AZSD_MODULE}/containers-${acc}.json.err)_"
            continue
        fi
        emit_table "${AZSD_RAW_DIR}/containers-${acc}.json" "Container|Public access|Legal hold|Immutability|Last modified" \
            '.[] | [.name, (.properties.publicAccess // "none"), (.properties.hasLegalHold // false), (.properties.hasImmutabilityPolicy // false), (.properties.lastModified // "-")]'
    done < <(inventory_of_type "Microsoft.Storage/storageAccounts")

    return 0
}

function module_31_storage_types() {
    cat <<'EOF'
Microsoft.Storage/storageAccounts
Microsoft.Storage/storageAccounts/blobServices
Microsoft.Storage/storageAccounts/fileServices
Microsoft.Storage/storageAccounts/queueServices
Microsoft.Storage/storageAccounts/tableServices
EOF
}
