#!/usr/bin/env bash
# Governance: policy posture and tagging, the two places intent is written down.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_23_governance() {
    report_begin "Governance: Azure Policy and tags"

    run_az_json policy-assignments policy assignment list --disable-scope-strict-match || true
    run_az_json policy-exemptions policy exemption list --disable-scope-strict-match || true
    run_az_json policy-noncompliant policy state list --filter "ComplianceState eq 'NonCompliant'" --top 1000 || true
    run_az_json policy-summary policy state summarize --top 50 || true

    emit_section "Policy assignments (direct and inherited)"
    emit_table "${AZSD_RAW_DIR}/policy-assignments.json" "Name|Display name|Scope|Enforcement|Identity" \
        '.[] | [.name, (.displayName // "-"), .scope, (.enforcementMode // "Default"), (.identity.type // "None")]'

    emit_section "Assignments not enforced (DoNotEnforce)"
    emit_table "${AZSD_RAW_DIR}/policy-assignments.json" "Name|Display name|Scope" \
        '.[] | select((.enforcementMode // "Default") == "DoNotEnforce") | [.name, (.displayName // "-"), .scope]'

    emit_section "Policy exemptions"
    emit_columns "${AZSD_RAW_DIR}/policy-exemptions.json" "Name|Scope|Category|Expires|Description" "name|scope|exemptionCategory|expiresOn|description"

    emit_section "Non-compliance by policy"
    emit_group_count "${AZSD_RAW_DIR}/policy-noncompliant.json" "Policy definition|Non-compliant resources" "policyDefinitionName"

    emit_section "Non-compliance by resource type"
    emit_group_count "${AZSD_RAW_DIR}/policy-noncompliant.json" "Resource type|Non-compliant records" "resourceType"

    emit_section "Non-compliant resources (first 1000 records)"
    emit_table "${AZSD_RAW_DIR}/policy-noncompliant.json" "Resource|Type|RG|Policy|Effect" \
        '.[] | [((.resourceId // "-") | split("/") | last), (.resourceType // "-"), (.resourceGroup // "-"), (.policyDefinitionName // "-"), (.policyDefinitionAction // "-")]'

    # tags, from the inventory rather than a second listing
    local inv
    inv="$(inventory_file)"
    local flat="${AZSD_RAW_DIR}/tags-flat.json"
    if jq --arg scope resource --from-file "${AZSD_LIB_DIR}/tags-flatten.jq" "${inv}" >"${flat}.resources" &&
        jq --arg scope resource-group --from-file "${AZSD_LIB_DIR}/tags-flatten.jq" \
            "${AZSD_OUTPUT_DIR}/raw/inventory/resource-groups.json" >"${flat}.groups"; then
        jq --slurp 'add' "${flat}.resources" "${flat}.groups" >"${flat}"
        rm -f "${flat}.resources" "${flat}.groups"
    else
        log_warn "tag flatten failed"
        echo "[]" >"${flat}"
    fi

    emit_section "Tag keys in use"
    emit_table "${flat}" "Key|Carriers|Distinct values|Sample values" \
        'group_by(.key)[] | [.[0].key, length, ([.[].value] | unique | length), ([.[].value] | unique | .[:5] | join(", "))]'

    emit_section "Untagged resources"
    emit_table "${inv}" "Name|Type|RG" \
        '.[] | select((.tags // {}) == {}) | [.name, .type, .resourceGroup]'

    return 0
}
