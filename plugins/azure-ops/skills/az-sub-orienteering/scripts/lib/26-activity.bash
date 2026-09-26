#!/usr/bin/env bash
# Activity log: who changes what. The norm against which anomalies read.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_26_activity() {
    report_begin "Activity log, last 30 days"

    run_az_json events monitor activity-log list --offset 30d --max-events 5000 || true

    emit_section "Volume"
    emit "- **Events fetched:** $(count_or_unread "${AZSD_RAW_DIR}/events.json") (capped at 5000)"

    emit_section "Events by caller"
    emit_group_count "${AZSD_RAW_DIR}/events.json" "Caller|Events" "caller"

    emit_section "Events by category"
    emit_group_count "${AZSD_RAW_DIR}/events.json" "Category|Events" "category.value"

    emit_section "Top operations"
    emit_table "${AZSD_RAW_DIR}/events.json" "Operation|Events" \
        'group_by(.operationName.value // "-") | map([(.[0].operationName.value // "-"), length]) | sort_by(-.[1]) | .[:30][]'

    emit_section "Failed operations"
    emit_table "${AZSD_RAW_DIR}/events.json" "Time|Caller|Operation|Resource|Status" \
        '[.[] | select((.status.value // "") | IN("Failed", "Forbidden", "Unauthorized"))] | sort_by(.eventTimestamp) | reverse | .[:50][] | [.eventTimestamp, (.caller // "-"), (.operationName.value // "-"), ((.resourceId // "-") | split("/") | last), (.status.value // "-")]'

    emit_section "Writes and deletes, most recent 100"
    emit_table "${AZSD_RAW_DIR}/events.json" "Time|Caller|Operation|Resource" \
        '[.[] | select((.operationName.value // "") | test("/(write|delete|action)$")) | select((.status.value // "") == "Succeeded")] | sort_by(.eventTimestamp) | reverse | .[:100][] | [.eventTimestamp, (.caller // "-"), (.operationName.value // "-"), ((.resourceId // "-") | split("/") | .[-2:] | join("/"))]'

    emit_section "Role assignment changes"
    emit_table "${AZSD_RAW_DIR}/events.json" "Time|Caller|Operation|Scope" \
        '[.[] | select((.operationName.value // "") | test("Microsoft.Authorization/roleAssignments/(write|delete)"))] | sort_by(.eventTimestamp) | reverse | .[] | [.eventTimestamp, (.caller // "-"), (.operationName.value // "-"), (.resourceId // "-")]'

    return 0
}
