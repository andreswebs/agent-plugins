#!/usr/bin/env bash
# Cost: billing as an architecture map. Retail rates; directional only.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

# Transport, retry and outcome reporting are shared with the standalone billing
# report — see lib/cost-query.bash.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=cost-query.bash
source "${AZSD_LIB_DIR}/cost-query.bash"

# Runs one query and records the outcome for the report. Writes the response to
# the module's raw dir under NAME.json so the existing renderer still applies.
# Sets COST_OUTCOME_<name> via cost_note for the section to print.
function cost_query() {
    local name="${1}" timeframe="${2}" dimension="${3}" from="${4:-}" to="${5:-}"
    local body="${AZSD_RAW_DIR}/${name}.request.json"
    local out="${AZSD_RAW_DIR}/${name}.json"

    if ! cm_body "${timeframe}" "${dimension}" "${from}" "${to}" >"${body}"; then
        COST_LAST_NOTE="Not retrieved: could not build the request body."
        return 1
    fi
    if cm_query "${COST_TOKEN}" "${AZSD_SUBSCRIPTION_ID}" "${body}" "${out}" \
        "${AZSD_RAW_DIR}/${name}" log_warn; then
        COST_LAST_NOTE=""
        return 0
    fi
    COST_LAST_NOTE="$(cm_explain)"
    # Leave a .err for the outcomes that are facts about access, matching the
    # convention the rest of the sweep uses. A throttle is not one of those, and
    # neither is a genuine zero.
    if [ "${CM_LAST_OUTCOME}" = "denied" ]; then
        printf '%s\n' "${CM_LAST_DETAIL}" >"${out}.err"
    fi
    [ -s "${out}" ] || echo "[]" >"${out}"
    return 1
}

function module_27_cost() {
    report_begin "Cost, current and previous month"

    emit "Retail (pay-as-you-go) rates from the Cost Management query API; reservations, savings plans and partner pricing are not reflected."

    if ! COST_TOKEN="$(cm_token 2>/dev/null)" || [ -z "${COST_TOKEN}" ]; then
        emit ""
        emit "_(no cost data: could not acquire an access token for the management API)_"
        return 0
    fi

    local prev_month bounds
    prev_month="$(cm_previous_month)"
    bounds="$(cm_month_bounds "${prev_month}")"

    local period tf dim label heading from to
    for period in month-to-date last-month; do
        case "${period}" in
        month-to-date)
            tf="MonthToDate"
            from=""
            to=""
            heading="Month to date"
            ;;
        last-month)
            # Not "TheLastMonth": the API rejects that named timeframe.
            tf="Custom"
            from="${bounds%%$'\t'*}"
            to="${bounds##*$'\t'}"
            heading="${prev_month}"
            ;;
        esac

        # Three dimensions, each its own query: Cost Management groups by
        # dimension, and these three cannot be derived from one another.
        for dim in service:ServiceName rg:ResourceGroupName location:ResourceLocation; do
            label="${dim%%:*}"
            case "${label}" in
            service) emit_section "${heading}: by service" ;;
            rg) emit_section "${heading}: by resource group" ;;
            location) emit_section "${heading}: by location" ;;
            esac
            if cost_query "by-${label}-${period}" "${tf}" "${dim##*:}" "${from}" "${to}"; then
                emit_table_from "${AZSD_RAW_DIR}/by-${label}-${period}.json" \
                    "Name|Cost|Currency" "cost-rows.jq"
            else
                emit "_(${COST_LAST_NOTE})_"
            fi
            emit ""
        done
    done

    return 0
}
