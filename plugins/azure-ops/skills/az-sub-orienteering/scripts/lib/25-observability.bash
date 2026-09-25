#!/usr/bin/env bash
# Observability: where logs go, whether they go anywhere, and who gets paged.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_25_observability() {
    report_begin "Observability: log sinks, diagnostic coverage, alerting"

    run_az_json workspaces monitor log-analytics workspace list || true
    run_az_json app-insights resource list --resource-type "Microsoft.Insights/components" || true
    run_az_json activity-log-export monitor diagnostic-settings subscription list || true
    run_az_json action-groups monitor action-group list || true
    run_az_json metric-alerts monitor metrics alert list || true
    run_az_json activity-alerts monitor activity-log alert list || true
    run_az_json log-alerts resource list --resource-type "Microsoft.Insights/scheduledQueryRules" || true
    normalize_list "${AZSD_RAW_DIR}/activity-log-export.json" || true

    emit_section "Log Analytics workspaces"
    emit_table "${AZSD_RAW_DIR}/workspaces.json" "Name|RG|SKU|Retention days|Daily cap GB|Public ingestion|Public query" \
        '.[] | [.name, .resourceGroup, (.sku.name // "-"), (.retentionInDays // "-"), (.workspaceCapping.dailyQuotaGb // "-"), (.publicNetworkAccessForIngestion // "-"), (.publicNetworkAccessForQuery // "-")]'

    emit_section "Application Insights"
    emit_columns "${AZSD_RAW_DIR}/app-insights.json" "Name|RG|Kind|Location" "name|resourceGroup|kind|location"

    emit_section "Activity log export (subscription diagnostic settings)"
    emit "Absent means the 90-day platform retention is the only copy of the control-plane audit trail."
    emit ""
    emit_table "${AZSD_RAW_DIR}/activity-log-export.json" "Name|Workspace|Storage|Event Hub|Categories" \
        '.[] | [.name, ((.workspaceId // "-") | split("/") | last), ((.storageAccountId // "-") | split("/") | last), ((.eventHubAuthorizationRuleId // "-") | split("/") | last), ((.logs // []) | map(select(.enabled) | .category) | join(","))]'

    emit_section "Action groups"
    emit_table "${AZSD_RAW_DIR}/action-groups.json" "Name|RG|Enabled|Emails|SMS|Webhooks|Other receivers" \
        '.[] | [.name, .resourceGroup, .enabled, ((.emailReceivers // []) | map(.emailAddress) | join(", ")), ((.smsReceivers // []) | length), ((.webhookReceivers // []) | length), (((.armRoleReceivers // []) + (.azureFunctionReceivers // []) + (.logicAppReceivers // []) + (.automationRunbookReceivers // [])) | length)]'

    emit_section "Alert rules"
    emit "- **Metric alerts:** $(json_count "${AZSD_RAW_DIR}/metric-alerts.json")"
    emit "- **Activity log alerts:** $(json_count "${AZSD_RAW_DIR}/activity-alerts.json")"
    emit "- **Log search alerts:** $(json_count "${AZSD_RAW_DIR}/log-alerts.json")"
    emit ""
    emit_table "${AZSD_RAW_DIR}/metric-alerts.json" "Metric alert|RG|Enabled|Severity|Scopes" \
        '.[] | [.name, .resourceGroup, .enabled, .severity, ((.scopes // []) | map(split("/") | last) | join(", "))]'
    emit ""
    emit_table "${AZSD_RAW_DIR}/activity-alerts.json" "Activity alert|RG|Enabled|Conditions" \
        '.[] | [.name, .resourceGroup, .enabled, ((.condition.allOf // []) | map("\(.field)=\(.equals)") | join("; "))]'

    emit_diagnostic_coverage
    return 0
}

# One az call per resource of a listed type; the list lives in
# lib/diagnostic-types.txt so it can grow without touching code.
function emit_diagnostic_coverage() {
    local types_file="${AZSD_LIB_DIR}/diagnostic-types.txt"
    local diag_dir="${AZSD_RAW_DIR}/diag"
    mkdir -p "${diag_dir}"

    emit_section "Diagnostic settings coverage"
    if [ ! -r "${types_file}" ]; then
        emit "_(lib/diagnostic-types.txt missing)_"
        return 0
    fi

    local rows="${AZSD_RAW_DIR}/diag-coverage.jsonl"
    : >"${rows}"

    local rtype total covered rid safe out count
    while IFS= read -r rtype; do
        [[ -z "${rtype}" || "${rtype}" == \#* ]] && continue
        total=0
        covered=0
        while IFS=$'\t' read -r _name _rg rid; do
            [ -z "${rid}" ] && continue
            total=$((total + 1))
            safe="${rid//\//_}"
            out="${diag_dir}/${safe}.json"
            if az_json monitor diagnostic-settings list --resource "${rid}" >"${out}" 2>"${out}.err"; then
                rm -f "${out}.err"
                normalize_list "${out}" || true
                count="$(json_count "${out}")"
                if [ "${count}" != "0" ]; then
                    covered=$((covered + 1))
                fi
            else
                log_debug "diagnostic-settings list failed for ${rid}"
                echo "[]" >"${out}"
            fi
        done < <(inventory_of_type "${rtype}")
        if [ "${total}" -gt 0 ]; then
            jq --null-input --compact-output --arg t "${rtype}" --argjson total "${total}" --argjson covered "${covered}" \
                '[$t, $total, $covered, ($total - $covered)]' >>"${rows}"
            log_info "diagnostics ${rtype}: ${covered}/${total}"
        fi
    done <"${types_file}"

    if [ ! -s "${rows}" ]; then
        emit "_(no resources of a listed type)_"
        return 0
    fi
    jq --slurp '.' "${rows}" | render_table "Resource type|Total|With settings|Without" >>"${AZSD_REPORT_FILE}"

    emit_section "Configured diagnostic settings"
    local aggregate="${AZSD_RAW_DIR}/diag-all.json"
    if ! find "${diag_dir}" -maxdepth 1 -name '*.json' -type f -print0 |
        xargs -0 jq --slurp 'map(select(type == "array")) | add // []' >"${aggregate}" 2>/dev/null; then
        echo "[]" >"${aggregate}"
    fi
    emit_table "${aggregate}" "Resource|Setting|Workspace|Storage|Event Hub|Log categories|Metrics" \
        '.[] | [((.id // "-") | split("/providers/Microsoft.Insights/")[0] | split("/") | last), .name, ((.workspaceId // "-") | split("/") | last), ((.storageAccountId // "-") | split("/") | last), ((.eventHubAuthorizationRuleId // "-") | split("/") | last), ((.logs // []) | map(select(.enabled)) | length), ((.metrics // []) | map(select(.enabled)) | length)]'
}

function module_25_observability_types() {
    cat <<'EOF'
Microsoft.OperationalInsights/workspaces
Microsoft.Insights/components
Microsoft.Insights/actionGroups
Microsoft.Insights/metricAlerts
Microsoft.Insights/activityLogAlerts
Microsoft.Insights/scheduledQueryRules
Microsoft.Insights/dataCollectionRules
Microsoft.Insights/dataCollectionEndpoints
Microsoft.Insights/workbooks
Microsoft.OperationsManagement/solutions
Microsoft.Portal/dashboards
Microsoft.AlertsManagement/smartDetectorAlertRules
EOF
}
