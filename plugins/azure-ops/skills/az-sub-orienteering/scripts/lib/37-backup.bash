#!/usr/bin/env bash
# Backup and recovery vaults: whether anything here can be restored.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_37_backup() {
    report_begin "Backup and recovery"

    emit_section "Recovery Services vaults"
    if ! skip_if_absent "Microsoft.RecoveryServices/vaults"; then
        run_az_json recovery-vaults backup vault list || true
        emit_table "${AZSD_RAW_DIR}/recovery-vaults.json" "Vault|RG|Location|SKU|Redundancy|Cross-region restore|Soft delete|Immutability" \
            '.[] | [.name, .resourceGroup, .location, (.sku.name // "-"), (.properties.redundancySettings.standardTierStorageRedundancy // "-"), (.properties.redundancySettings.crossRegionRestore // "-"), (.properties.securitySettings.softDeleteSettings.softDeleteState // "-"), (.properties.securitySettings.immutabilitySettings.state // "-")]'
        local vault rg
        while IFS=$'\t' read -r vault rg _rid; do
            [ -z "${vault}" ] && continue
            run_az_json "items-${vault}" backup item list --vault-name "${vault}" --resource-group "${rg}" || true
            emit_subsection "${vault}: protected items"
            emit_table "${AZSD_RAW_DIR}/items-${vault}.json" "Item|Type|Protection state|Last backup|Policy" \
                '.[] | [(.properties.friendlyName // .name), (.properties.workloadType // .properties.protectedItemType // "-"), (.properties.protectionState // "-"), (.properties.lastBackupTime // .properties.lastBackupStatus // "-"), ((.properties.policyId // "-") | split("/") | last)]'
        done < <(inventory_of_type "Microsoft.RecoveryServices/vaults")
    fi

    emit_section "Backup vaults (Data Protection)"
    if ! skip_if_absent "Microsoft.DataProtection/backupVaults"; then
        run_az_json backup-vaults resource list --resource-type "Microsoft.DataProtection/backupVaults" || true
        emit_columns "${AZSD_RAW_DIR}/backup-vaults.json" "Vault|RG|Location|Identity" "name|resourceGroup|location|identity.type"
    fi

    return 0
}

function module_37_backup_types() {
    echo "Microsoft.RecoveryServices/vaults"
    echo "Microsoft.DataProtection/backupVaults"
}
