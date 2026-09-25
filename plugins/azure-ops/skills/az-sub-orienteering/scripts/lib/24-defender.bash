#!/usr/bin/env bash
# Microsoft Defender for Cloud: plan coverage, provisioning, contacts, open findings.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_24_defender() {
    report_begin "Microsoft Defender for Cloud"

    run_az_json pricings security pricing list || true
    run_az_json auto-provisioning security auto-provisioning-setting list || true
    run_az_json contacts security contact list || true
    run_az_json settings security setting list || true
    run_az_json assessments security assessment list || true

    local f
    for f in pricings auto-provisioning contacts settings assessments; do
        normalize_list "${AZSD_RAW_DIR}/${f}.json" || true
    done

    if grep --quiet --no-messages "Subscription Not Registered" "${AZSD_RAW_DIR}"/*.err 2>/dev/null; then
        emit_section "Microsoft.Security provider is not registered"
        emit "Every Defender query returned \`Subscription Not Registered\`: Defender for Cloud has never been enabled here, so no plan is evaluated and no assessment exists."
    fi

    emit_section "Plans"
    emit_table "${AZSD_RAW_DIR}/pricings.json" "Plan|Tier|Sub-plan|Enabled since" \
        '.[] | [.name, (.pricingTier // .properties.pricingTier // "-"), (.subPlan // .properties.subPlan // "-"), (.enablementTime // .properties.enablementTime // "-")]'

    emit_section "Auto-provisioning"
    emit_table "${AZSD_RAW_DIR}/auto-provisioning.json" "Setting|Auto provision" \
        '.[] | [.name, (.autoProvision // .properties.autoProvision // "-")]'

    emit_section "Security contacts"
    emit_table "${AZSD_RAW_DIR}/contacts.json" "Name|Emails|Notify on alerts|Notify roles" \
        '.[] | [.name, (.emails // .email // .properties.emails // "-"), ((.alertNotifications // .properties.alertNotifications // {}) | tojson), (((.notificationsByRole // .properties.notificationsByRole // {}).roles // []) | join(","))]'

    emit_section "Settings"
    emit_table "${AZSD_RAW_DIR}/settings.json" "Setting|Kind|Enabled" \
        '.[] | [.name, (.kind // "-"), (.enabled // .properties.enabled // "-")]'

    emit_section "Assessments by status"
    emit_table "${AZSD_RAW_DIR}/assessments.json" "Status|Count" \
        'group_by(.status.code // "Unknown")[] | [(.[0].status.code // "Unknown"), length]'

    emit_section "Unhealthy assessments by recommendation"
    emit_table "${AZSD_RAW_DIR}/assessments.json" "Recommendation|Severity|Affected resources" \
        '[.[] | select(.status.code == "Unhealthy")] | group_by(.displayName)[] | [.[0].displayName, (.[0].status.severity // .[0].metadata.severity // "-"), length]'

    return 0
}
