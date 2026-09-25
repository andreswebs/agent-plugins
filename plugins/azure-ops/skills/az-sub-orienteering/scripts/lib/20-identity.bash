#!/usr/bin/env bash
# Identity perimeter: who and what can act on the management plane.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_20_identity() {
    report_begin "Identity perimeter: RBAC and managed identities"

    local scope="/subscriptions/${AZSD_SUBSCRIPTION_ID}"
    run_az_json role-assignments role assignment list --scope "${scope}" --include-inherited || true
    run_az_json custom-roles role definition list --custom-role-only true --scope "${scope}" || true
    run_az_json uamis identity list || true

    emit_section "Counts"
    emit "- **Role assignments (direct + inherited):** $(json_count "${AZSD_RAW_DIR}/role-assignments.json")"
    emit "- **Custom role definitions visible at this scope:** $(json_count "${AZSD_RAW_DIR}/custom-roles.json")"
    emit "- **User-assigned managed identities:** $(json_count "${AZSD_RAW_DIR}/uamis.json")"

    emit_section "Assignments by principal type"
    emit_group_count "${AZSD_RAW_DIR}/role-assignments.json" "Principal type|Count" "principalType"

    emit_section "Assignments by role"
    emit_group_count "${AZSD_RAW_DIR}/role-assignments.json" "Role|Count" "roleDefinitionName"

    emit_section "Privileged assignments"
    emit "Owner, Contributor, User Access Administrator, RBAC Administrator, Security Admin, Key Vault Administrator, Storage Blob Data Owner."
    emit ""
    emit_table_from "${AZSD_RAW_DIR}/role-assignments.json" "Principal|Type|Role|Scope|Origin" "role-assignments.jq" \
        --arg sub "${AZSD_SUBSCRIPTION_ID}" --arg mode "privileged"

    emit_section "Assignments to unresolvable principals"
    emit "A principal the directory no longer knows: deleted user, app, or a principal from another tenant."
    emit ""
    emit_table "${AZSD_RAW_DIR}/role-assignments.json" "Principal ID|Type|Role|Scope" \
        '.[] | select((.principalName // "") == "" or (.principalType // "Unknown") == "Unknown") | [.principalId, (.principalType // "-"), .roleDefinitionName, .scope]'

    emit_section "Assignments at resource-group or resource scope"
    # shellcheck disable=SC2016  # jq program, $sub is bound with --arg
    emit_table "${AZSD_RAW_DIR}/role-assignments.json" "Principal|Type|Role|Scope" \
        '.[] | select(.scope | ascii_downcase | startswith($sub + "/")) | [(.principalName // .principalId), (.principalType // "-"), .roleDefinitionName, .scope]' \
        --arg sub "${scope,,}"

    emit_section "All assignments"
    emit_table_from "${AZSD_RAW_DIR}/role-assignments.json" "Principal|Type|Role|Scope|Origin" "role-assignments.jq" \
        --arg sub "${AZSD_SUBSCRIPTION_ID}" --arg mode "all"

    emit_section "Custom role definitions"
    emit_table "${AZSD_RAW_DIR}/custom-roles.json" "Name|Assignable scopes|Actions|Data actions" \
        '.[] | [.roleName, ((.assignableScopes // []) | join("<br>")), ((.permissions[0].actions // []) | join("<br>")), ((.permissions[0].dataActions // []) | join("<br>"))]'

    emit_section "User-assigned managed identities"
    emit_columns "${AZSD_RAW_DIR}/uamis.json" "Name|RG|Client ID|Principal ID" "name|resourceGroup|clientId|principalId"

    emit_section "Resources with a managed identity"
    emit_table "$(inventory_file)" "Name|Type|RG|Identity type|User-assigned" \
        '.[] | select(.identity != null and (.identity.type // "None") != "None") | [.name, .type, .resourceGroup, .identity.type, ((.identity.userAssignedIdentities // {}) | keys | map(split("/") | last) | join(", "))]'

    return 0
}

function module_20_identity_types() {
    echo "Microsoft.ManagedIdentity/userAssignedIdentities"
}
