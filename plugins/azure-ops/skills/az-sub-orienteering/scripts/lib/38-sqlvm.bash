#!/usr/bin/env bash
# SQL Server on virtual machines: version, edition, licence and management mode
# from the SQL IaaS extension's resource, and SQL images it does not know about.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_38_sqlvm() {
    report_begin "SQL Server on virtual machines"

    if skip_if_absent "Microsoft.SqlVirtualMachine/SqlVirtualMachines" "Microsoft.Compute/virtualMachines"; then
        return 0
    fi

    run_az_json sqlvms sql vm list || true
    arg_query sql-images sql-vm-images.kql || true

    emit_section "Registered with the SQL IaaS extension"
    emit "Version comes from the image offer the extension recorded (\`SQL2019-WS2019\` is SQL Server 2019 on Windows Server 2019). An in-place upgrade inside the VM may not be reflected: confirm with \`SELECT @@VERSION\` before sizing a target on it."
    emit ""
    emit_table "${AZSD_RAW_DIR}/sqlvms.json" "SQL VM|RG|Image offer|Edition|Licence|Management|Least privilege|VM" \
        '.[] | [.name, .resourceGroup, (.sqlImageOffer // "-"), (.sqlImageSku // "-"), (.sqlServerLicenseType // "-"), (.sqlManagement // "-"), (.leastPrivilegeMode // "-"), ((.virtualMachineResourceId // "-") | split("/") | last)]'
    emit ""
    emit "Licence \`PAYG\` bills the SQL Server licence by the hour on top of compute; \`AHUB\` applies an existing licence with Software Assurance; \`DR\` is a free passive replica. Management \`LightWeight\` or \`NoAgent\` exposes no automated backup, patching or assessment settings at the control plane."

    local vm rg _rid
    while IFS=$'\t' read -r vm rg _rid; do
        [ -z "${vm}" ] && continue
        az_rest_json "detail-${vm}" GET \
            "https://management.azure.com/subscriptions/${AZSD_SUBSCRIPTION_ID}/resourceGroups/${rg}/providers/Microsoft.SqlVirtualMachine/sqlVirtualMachines/${vm}?api-version=2023-10-01&\$expand=*" || true
    done < <(inventory_of_type "Microsoft.SqlVirtualMachine/SqlVirtualMachines")

    local details="${AZSD_RAW_DIR}/details.json"
    find "${AZSD_RAW_DIR}" -maxdepth 1 -name 'detail-*.json' -type f -print0 |
        xargs -0 --no-run-if-empty jq --slurp '[.[] | select(type == "object" and has("properties"))]' >"${details}" 2>/dev/null ||
        echo "[]" >"${details}"
    [ -s "${details}" ] || echo "[]" >"${details}"

    emit_section "Automated backup, patching and assessment"
    # shellcheck disable=SC2016  # jq program
    emit_table "${details}" "SQL VM|Auto backup|Backup retention days|Auto patching|Patch window|Assessment|Availability group" \
        '.[] | .properties as $p | [.name, ($p.autoBackupSettings.enable // "-"), ($p.autoBackupSettings.retentionPeriod // "-"), ($p.autoPatchingSettings.enable // "-"), (if $p.autoPatchingSettings.dayOfWeek then "\($p.autoPatchingSettings.dayOfWeek) \($p.autoPatchingSettings.maintenanceWindowStartingHour // "?"):00" else "-" end), ($p.assessmentSettings.enable // "-"), (($p.sqlVirtualMachineGroupResourceId // "-") | split("/") | last)]'

    emit_section "SQL Server images not registered with the extension"
    emit "VMs built from a Microsoft SQL Server marketplace image with no SQL VM resource. Their version, edition and licence are invisible at the control plane. SQL Server installed by hand on a plain Windows image does not appear here or anywhere else in this sweep."
    emit ""
    if ! emit_if_unread "${AZSD_RAW_DIR}/sql-images.json"; then
        # shellcheck disable=SC2016  # jq program, $registered is bound with --slurpfile
        emit_table "${AZSD_RAW_DIR}/sql-images.json" "VM|RG|Offer|SKU|Power state" \
            '($registered[0] | map(.virtualMachineResourceId // "" | ascii_downcase)) as $known | .[] | select(.id as $id | $known | index($id) | not) | [.name, .resourceGroup, .offer, .sku, (.powerState | sub("^PowerState/"; ""))]' \
            --slurpfile registered "${AZSD_RAW_DIR}/sqlvms.json"
    fi

    return 0
}

function module_38_sqlvm_types() {
    cat <<'EOF'
Microsoft.SqlVirtualMachine/SqlVirtualMachines
Microsoft.SqlVirtualMachine/SqlVirtualMachineGroups
EOF
}
