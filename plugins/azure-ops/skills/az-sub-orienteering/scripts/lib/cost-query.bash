#!/usr/bin/env bash
# Cost Management query transport, shared by the sweep's `cost` module and the
# standalone billing report.
#
# It exists because both callers need the same three awkward things, and got
# them wrong in the same way independently: a request body, a POST that can read
# its own response headers, and a back-off taken from the service rather than
# invented.
#
# Deliberately free of AZSD_* globals and of the sweep's report helpers, so the
# billing script stays runnable on its own. Callers decide where files land.
#
# Requires: az (for the token), curl, jq.
#
# `az rest` cannot surface response headers, and the headers are the only place
# the service says which limit it refused on and how long to wait, so this uses
# curl with a bearer token from az.

CM_API_VERSION="${CM_API_VERSION:-2023-11-01}"
CM_MAX_ATTEMPTS="${CM_MAX_ATTEMPTS:-6}"
CM_RETRY_AFTER_FALLBACK="${CM_RETRY_AFTER_FALLBACK:-30}"
CM_RETRY_AFTER_CAP="${CM_RETRY_AFTER_CAP:-120}"

# Identifies this client to Cost Management. Callers that send nothing share one
# "DefaultQuota" bucket with every other unidentified caller in the tenant, so a
# 429 is usually somebody else's traffic. A distinct value is *reported* to earn
# a separate allowance; that could not be confirmed without deliberately
# draining a shared bucket on a live tenant. Harmless either way — the fix that
# does the work is honouring the advertised interval below.
CM_CLIENT_TYPE="${CM_CLIENT_TYPE:-p41-az-sub-orienteering}"

# Set by cm_query for the caller to act on and, more importantly, to report:
#   ok        the query returned data
#   throttled every attempt was refused with 429
#   denied    403/401 — a permissions fact about the caller
#   empty     the query succeeded and the subscription genuinely has no cost
#   error     anything else; CM_LAST_DETAIL carries the response body
CM_LAST_OUTCOME=""
CM_LAST_STATUS=""
CM_LAST_DETAIL=""

cm_token() {
    az account get-access-token --resource "https://management.azure.com" \
        --query accessToken --output tsv
}

# The API rejects the named timeframe "TheLastMonth" ("currently not supported"),
# so a previous month has to be asked for as an explicit Custom range. These
# helpers build one. GNU date first, BSD date as the fallback.
cm_last_day_of_month() {
    local ym="${1}"
    if date --date="${ym}-01 +1 month -1 day" +%Y-%m-%d >/dev/null 2>&1; then
        date --date="${ym}-01 +1 month -1 day" +%Y-%m-%d
    else
        date -j -v1d -v+1m -v-1d -f "%Y-%m-%d" "${ym}-01" +%Y-%m-%d
    fi
}

cm_previous_month() {
    if date --date="$(date --utc +%Y-%m-01) -1 day" +%Y-%m >/dev/null 2>&1; then
        date --date="$(date --utc +%Y-%m-01) -1 day" +%Y-%m
    else
        date -u -j -v-1m +%Y-%m
    fi
}

# cm_month_bounds YYYY-MM -> "<from>\t<to>" as ISO instants.
cm_month_bounds() {
    local ym="${1}"
    printf '%sT00:00:00Z\t%sT23:59:59Z' "${ym}-01" "$(cm_last_day_of_month "${ym}")"
}

# cm_body TIMEFRAME DIMENSION [FROM TO] -> request JSON on stdout.
# FROM and TO are ISO instants, required when TIMEFRAME is "Custom".
cm_body() {
    local timeframe="${1}" dimension="${2}" from="${3:-}" to="${4:-}"
    jq --null-input \
        --arg tf "${timeframe}" --arg dim "${dimension}" \
        --arg from "${from}" --arg to "${to}" '
        {
            type: "ActualCost",
            timeframe: $tf,
            dataset: {
                granularity: "None",
                aggregation: {totalCost: {name: "PreTaxCost", function: "Sum"}},
                grouping: [{type: "Dimension", name: $dim}]
            }
        }
        | if $tf == "Custom"
          then .timePeriod = {from: $from, to: $to}
          else . end'
}

# Seconds to wait after a 429, from whichever bucket the service refused on.
# Only 429 responses carry these headers, so a 200 tells you nothing about which
# bucket a call landed in.
cm_retry_after() {
    local hdr_file="${1}"
    local seconds=""
    if [ -r "${hdr_file}" ]; then
        seconds="$(grep --ignore-case --only-matching --extended-regexp \
            '^x-ms-ratelimit-microsoft\.costmanagement-(clienttype|qpu)-retry-after:[[:space:]]*[0-9]+' \
            "${hdr_file}" 2>/dev/null |
            grep --only-matching --extended-regexp '[0-9]+$' |
            sort --numeric-sort --reverse | head --lines=1)"
        [ -n "${seconds}" ] || seconds="$(grep --ignore-case --only-matching --extended-regexp \
            '^retry-after:[[:space:]]*[0-9]+' "${hdr_file}" 2>/dev/null |
            grep --only-matching --extended-regexp '[0-9]+$' | head --lines=1)"
    fi
    [ -n "${seconds}" ] || seconds="${CM_RETRY_AFTER_FALLBACK}"
    [ "${seconds}" -le "${CM_RETRY_AFTER_CAP}" ] || seconds="${CM_RETRY_AFTER_CAP}"
    printf '%s' "${seconds}"
}

# Which rate-limit bucket the service refused on, for the log line. Knowing it is
# the difference between "slow down" and "someone else is using the allowance".
cm_throttle_bucket() {
    local hdr_file="${1}"
    local bucket
    bucket="$(grep --ignore-case --only-matching --extended-regexp \
        '^x-ms-ratelimit-remaining-microsoft\.costmanagement-[a-z]+-requests:[^;]*' \
        "${hdr_file}" 2>/dev/null | head --lines=1)"
    [ -n "${bucket}" ] && printf '%s' "${bucket#*costmanagement-}" && return 0
    printf 'unknown bucket'
}

# cm_query TOKEN SUBSCRIPTION_ID BODY_FILE OUT_FILE WORK_PREFIX [LOG_FN]
#
# Writes the full response JSON to OUT_FILE on success, so callers can apply
# their own renderers to `.properties`. Retries 429 for as long as the service
# asks, up to CM_MAX_ATTEMPTS. Returns 0 only on a successful query with rows;
# CM_LAST_OUTCOME always says what happened.
cm_query() {
    local token="${1}" sub="${2}" body_file="${3}" out_file="${4}" work="${5}"
    local log_fn="${6:-:}"
    local hdr_file="${work}.headers" resp_file="${work}.response"
    local attempt=1 status delay rows

    CM_LAST_OUTCOME=""
    CM_LAST_STATUS=""
    CM_LAST_DETAIL=""

    while true; do
        status="$(curl --silent --show-error \
            --dump-header "${hdr_file}" --output "${resp_file}" --write-out '%{http_code}' \
            --request POST \
            --header "Authorization: Bearer ${token}" \
            --header "Content-Type: application/json" \
            --header "ClientType: ${CM_CLIENT_TYPE}" \
            --data "@${body_file}" \
            "https://management.azure.com/subscriptions/${sub}/providers/Microsoft.CostManagement/query?api-version=${CM_API_VERSION}" \
            2>"${work}.curlerr")" || {
            CM_LAST_OUTCOME="error"
            CM_LAST_DETAIL="curl failed: $(tr --delete '\n' <"${work}.curlerr" 2>/dev/null)"
            return 1
        }
        CM_LAST_STATUS="${status}"

        case "${status}" in
        200)
            cp "${resp_file}" "${out_file}"
            rows="$(jq '(.properties.rows // []) | length' "${out_file}" 2>/dev/null || echo 0)"
            if [ "${rows}" -eq 0 ]; then
                CM_LAST_OUTCOME="empty"
                return 1
            fi
            CM_LAST_OUTCOME="ok"
            return 0
            ;;
        429)
            if [ "${attempt}" -lt "${CM_MAX_ATTEMPTS}" ]; then
                delay="$(cm_retry_after "${hdr_file}")"
                "${log_fn}" "rate limited on $(cm_throttle_bucket "${hdr_file}"); retry ${attempt}/${CM_MAX_ATTEMPTS} in ${delay}s (service-advertised)"
                sleep "${delay}"
                attempt=$((attempt + 1))
                continue
            fi
            CM_LAST_OUTCOME="throttled"
            CM_LAST_DETAIL="still rate limited after ${CM_MAX_ATTEMPTS} attempts"
            return 1
            ;;
        401 | 403)
            CM_LAST_OUTCOME="denied"
            CM_LAST_DETAIL="HTTP ${status}: $(tr --delete '\n' <"${resp_file}" 2>/dev/null | cut --characters=1-300)"
            return 1
            ;;
        *)
            CM_LAST_OUTCOME="error"
            CM_LAST_DETAIL="HTTP ${status}: $(tr --delete '\n' <"${resp_file}" 2>/dev/null | cut --characters=1-300)"
            return 1
            ;;
        esac
    done
}

# One sentence explaining an unsuccessful query, for a report. Never guesses:
# each outcome has exactly one cause, and "no data" is not one of them unless
# the service actually said so.
cm_explain() {
    case "${CM_LAST_OUTCOME}" in
    empty) printf 'No cost recorded for this period. The query succeeded and returned zero rows.' ;;
    throttled) printf 'Not retrieved: the Cost Management API rate-limited every attempt. This is a throttling fact, not a permissions or billing-channel one — the cost may well exist.' ;;
    denied) printf 'Not retrieved: access denied (HTTP %s). The caller lacks Cost Management Reader at this scope.' "${CM_LAST_STATUS}" ;;
    error) printf 'Not retrieved: %s' "${CM_LAST_DETAIL}" ;;
    *) printf 'Not retrieved.' ;;
    esac
}
