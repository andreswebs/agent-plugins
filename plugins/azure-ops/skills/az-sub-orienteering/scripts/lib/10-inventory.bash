#!/usr/bin/env bash
# Subscription context and the full resource inventory every other module reads.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_10_inventory() {
    report_begin "Subscription context and resource inventory"

    run_az_json subscription account show || true
    run_az_json resource-groups group list || true
    run_az_json providers provider list --query "[?registrationState=='Registered']" || true
    run_az_json locks lock list || true
    run_az_json subscription-tags tag list --resource-id "/subscriptions/${AZSD_SUBSCRIPTION_ID}" || true
    run_az_json all-resources resource list || true

    # getEntities is the one call that returns the management group chain with
    # only Reader on the subscription. OData has no parameter binding; the id
    # is a GUID validated by the runner.
    local entities_body="${AZSD_RAW_DIR}/entities.request.json"
    echo '{}' >"${entities_body}"
    az_rest_json entities POST \
        "https://management.azure.com/providers/Microsoft.Management/getEntities?api-version=2020-05-01&\$filter=name eq '${AZSD_SUBSCRIPTION_ID}'" \
        "${entities_body}" || true

    emit_section "Subscription"
    emit '```json'
    jq '{id, name: .name, tenantId, state, managedByTenants}' "${AZSD_RAW_DIR}/subscription.json" >>"${AZSD_REPORT_FILE}" 2>/dev/null || emit "{}"
    emit '```'

    emit_section "Management group chain (root first)"
    if [ "$(json_count "${AZSD_RAW_DIR}/entities.json")" = "0" ]; then
        emit "_(not available; caller may lack management group read access)_"
    else
        emit_table "${AZSD_RAW_DIR}/entities.json" "Chain|Display name|Parent" \
            '.value[]? | [((.properties.parentNameChain // []) | join(" / ")), (.properties.displayName // "-"), (.properties.parent.id // "-")]'
    fi

    emit_section "Subscription tags"
    emit_table "${AZSD_RAW_DIR}/subscription-tags.json" "Key|Value" \
        '(.properties.tags // {}) | to_entries[] | [.key, .value]'

    local total
    total="$(json_count "${AZSD_RAW_DIR}/all-resources.json")"
    emit_section "Totals"
    emit "- **Resources:** ${total}"
    emit "- **Resource groups:** $(count_or_unread "${AZSD_RAW_DIR}/resource-groups.json")"
    emit "- **Registered resource providers:** $(count_or_unread "${AZSD_RAW_DIR}/providers.json")"
    emit "- **CSV export:** \`raw/inventory/all-resources.csv\`"

    jq --raw-output --from-file "${AZSD_LIB_DIR}/inventory-csv.jq" "${AZSD_RAW_DIR}/all-resources.json" \
        >"${AZSD_RAW_DIR}/all-resources.csv" 2>/dev/null || log_warn "csv export failed"

    emit_section "Resource groups"
    emit_table "${AZSD_RAW_DIR}/resource-groups.json" "Name|Location|Managed by|Tags" \
        '.[] | [.name, .location, (.managedBy // "-"), ((.tags // {}) | to_entries | map("\(.key)=\(.value)") | join(", "))]'

    emit_section "Resources by type"
    emit_group_count "${AZSD_RAW_DIR}/all-resources.json" "Resource type|Count" "type"

    emit_section "Resources by resource group"
    emit_group_count "${AZSD_RAW_DIR}/all-resources.json" "Resource group|Count" "resourceGroup"

    emit_section "Resources by location"
    emit_group_count "${AZSD_RAW_DIR}/all-resources.json" "Location|Count" "location"

    emit_section "Registered resource providers"
    emit "Registration is a trace of what has ever been deployed here, including services no longer present."
    emit ""
    emit_columns "${AZSD_RAW_DIR}/providers.json" "Namespace|Registration" "namespace|registrationState"

    emit_section "Resource locks"
    emit_columns "${AZSD_RAW_DIR}/locks.json" "Name|Level|Notes|Scope" "name|level|notes|id"

    log_info "${total} resources catalogued"
    return 0
}

function module_10_inventory_types() {
    echo "Microsoft.Resources/resourceGroups"
}
