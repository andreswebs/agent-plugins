#!/usr/bin/env bash
# Azure Advisor: the platform's own ranked opinion, free and already computed.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_28_advisor() {
    report_begin "Azure Advisor recommendations"

    run_az_json recommendations advisor recommendation list || true

    emit_section "By category and impact"
    emit_table "${AZSD_RAW_DIR}/recommendations.json" "Category|Impact|Count" \
        'group_by(.category, .impact)[] | [.[0].category, .[0].impact, length]'

    emit_section "By recommendation"
    emit_table "${AZSD_RAW_DIR}/recommendations.json" "Category|Impact|Problem|Affected resources" \
        'group_by(.shortDescription.problem)[] | [.[0].category, .[0].impact, .[0].shortDescription.problem, length] | select(.[3] > 0)'

    emit_section "High impact, by resource"
    emit_table "${AZSD_RAW_DIR}/recommendations.json" "Category|Problem|Resource|Type" \
        '.[] | select(.impact == "High") | [.category, .shortDescription.problem, ((.resourceMetadata.resourceId // .id // "-") | split("/providers/Microsoft.Advisor")[0] | split("/") | last), (.impactedField // "-")]'

    return 0
}
