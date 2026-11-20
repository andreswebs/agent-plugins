#!/usr/bin/env bash
#
# az-billing-report.bash - cost per subscription and per service across several
# subscriptions, via the Cost Management Query API, using only az and jq.
#
# IMPORTANT: numbers are retail / pay-as-you-go rates. They are directional for
# chargeback and trends and do NOT reconcile to a partner (CSP) or EA invoice;
# reservations and savings plans show as zero.
#
# Usage:
#   az-billing-report.bash             # current month-to-date
#   az-billing-report.bash 2026-05     # a full calendar month (Custom timeframe)
#
# Requires:
#   - az, logged in to the tenant (Cost Management Reader or Reader on each subscription)
#   - jq, bc, curl, GNU coreutils (date, sort, awk, tail, tr, mkdir, mktemp)
#
# Subscriptions come from BILLING_SUBS: a space-separated list of
# label=subscription-id pairs, e.g.
#
#   export BILLING_SUBS="management=<subscription-id> platform-prod=<subscription-id>"
#
# Optional:
#   BILLING_OUT_DIR       directory for the output files
#                         (default: ./.local/tmp/az-sub-discovery/billing)
#   BILLING_REPORT_TITLE  leading half of the report H1, for when the default
#                         wording is not what the audience should read
#                         (default: "Azure cost report"). The period is always
#                         appended, so the heading reads "<title>: <period>" and
#                         a report can never be circulated without saying which
#                         period it covers. Does not affect the output
#                         filenames.
#   BILLING_REPORT_NAME   base name of the output files, without extension;
#                         ".md" and ".csv" are appended. Default:
#                         "billing-report-<YYYY-MM-DD>-mtd" for month-to-date,
#                         dated on the UTC day of generation, so each run keeps
#                         its own snapshot; "billing-report-<YYYY-MM>" for a
#                         calendar month, whose content does not change once
#                         the month has closed.
#
# When either output file already exists the run stops before querying
# anything. Set BILLING_REPORT_NAME, or move the old files aside, to run again.
#
# A subscription whose cost could not be read (refused, throttled, no token) is
# listed in the report under "Not retrieved" and in the CSV with its outcome in
# the status column; every total excludes it and says so. One whose query
# succeeded with no rows is listed under "No cost recorded".
#
# Exit status:
#   0  every subscription was read
#   1  nothing could be reported (no rows at all), or a usage error
#   2  the report was written, but some subscriptions were not retrieved

set -o errexit
set -o nounset
set -o pipefail

# Request building, the throttle-aware POST and the outcome vocabulary are
# shared with the sweep's `cost` module, which needs exactly the same three
# things. See lib/cost-query.bash for why this cannot go through `az rest`.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0}}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/cost-query.bash
source "${SCRIPT_DIR}/lib/cost-query.bash"

# Costs are summed in bc (exact decimal) rather than jq/awk (binary floats that
# drift on long decimals). r() rounds half-away-from-zero to 2 decimals and is
# applied per line item, so displayed rows reconcile with their totals
# (round-then-sum): grand total == sum of per-sub totals == sum of per-service.
readonly EXIT_PARTIAL=2

readonly BC_PREAMBLE='scale=2; define r(x){ if (x < 0) return (x - 0.005) / 1; return (x + 0.005) / 1 }'

bc_eval() {
    bc <<<"${BC_PREAMBLE}; ${1}"
}

echo_stderr() {
    echo "${*}" >&2
}

# Progress lines emitted from inside a query, indented under the "querying X"
# line that precedes them.
echo_stderr_indented() {
    echo "  ${*}" >&2
}

die() {
    echo_stderr "error: ${*}"
    exit 1
}

require_deps() {
    local missing=()
    local cmd
    for cmd in az jq bc curl; do
        command -v "${cmd}" >/dev/null || missing+=("${cmd}")
    done
    [[ "${#missing[@]}" -eq 0 ]] || die "missing required commands: ${missing[*]}"
}

last_day_of_month() {
    local ym="${1}"
    # GNU date first, BSD date as fallback.
    if date --date="${ym}-01 +1 month -1 day" +%Y-%m-%d >/dev/null 2>&1; then
        date --date="${ym}-01 +1 month -1 day" +%Y-%m-%d
    else
        date -j -v1d -v+1m -v-1d -f "%Y-%m-%d" "${ym}-01" +%Y-%m-%d
    fi
}

current_month() {
    date --utc +%Y-%m 2>/dev/null || date -u +%Y-%m
}

current_day() {
    date --utc +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d
}

# Sets the period globals from the CLI argument.
resolve_period() {
    local period_arg="${1}"
    if [[ "${period_arg}" == "mtd" ]]; then
        TIMEFRAME="MonthToDate"
        PERIOD_FROM=""
        PERIOD_TO=""
        # The heading carries the day for the same reason the filename does:
        # a month-to-date figure is a snapshot, and the day is its identity.
        PERIOD_LABEL="month-to-date to $(current_day)"
        PERIOD_SLUG="$(current_day)-mtd"
    elif [[ "${period_arg}" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
        TIMEFRAME="Custom"
        PERIOD_FROM="${period_arg}-01T00:00:00Z"
        PERIOD_TO="$(last_day_of_month "${period_arg}")T23:59:59Z"
        PERIOD_LABEL="${period_arg}"
        PERIOD_SLUG="${period_arg}"
    else
        die "usage: ${0##*/} [mtd | YYYY-MM]"
    fi
}

write_body() {
    local body_file="${1}"
    cm_body "${TIMEFRAME}" "ServiceName" "${PERIOD_FROM}" "${PERIOD_TO}" >"${body_file}"
}

# Appends {sub, outcome, explanation} for a subscription that contributed no
# rows, so the report can say what is missing instead of silently omitting it.
record_status() {
    local status_file="${1}" label="${2}" outcome="${3}" explanation="${4}"
    jq --null-input --compact-output \
        --arg sub "${label}" --arg outcome "${outcome}" --arg explanation "${explanation}" \
        '{sub: $sub, outcome: $outcome, explanation: $explanation}' >>"${status_file}"
}

collect_rows() {
    local body_file="${1}" rows_file="${2}" status_file="${3}"
    shift 3
    local pair label sub token explanation
    local resp="${tmp_workspace}/response.json"
    : >"${rows_file}"
    : >"${status_file}"
    for pair in "${@}"; do
        label="${pair%%=*}"
        sub="${pair##*=}"
        [[ "${label}" != "${pair}" ]] || die "malformed BILLING_SUBS entry: '${pair}' (expected label=subscription-id)"
        [[ "${sub}" =~ ^[0-9a-fA-F-]{36}$ ]] || die "not a subscription id in BILLING_SUBS entry '${pair}'"
        echo_stderr "querying ${label} ..."
        # A token per subscription, because each may be linked to a different
        # account in the same login.
        if ! token="$(cm_token "${sub}")" || [[ -z "${token}" ]]; then
            explanation="Not retrieved: could not acquire an access token (az login for the account that owns it?)"
            echo_stderr "  ${label}: ${explanation}"
            record_status "${status_file}" "${label}" "no_token" "${explanation}"
            continue
        fi
        if cm_query "${token}" "${sub}" "${body_file}" "${resp}" \
            "${tmp_workspace}/${label}" echo_stderr_indented; then
            jq --compact-output --arg label "${label}" \
                '(.properties.rows // [])[] | {sub:$label, service:.[1], cost:.[0], currency:.[2]}' \
                "${resp}" >>"${rows_file}"
        else
            # An empty result is a fact about the period, not a failure to
            # report as one; everything else names its own cause.
            explanation="$(cm_explain)"
            echo_stderr "  ${label}: ${explanation}"
            record_status "${status_file}" "${label}" "${CM_LAST_OUTCOME:-error}" "${explanation}"
        fi
        sleep 3
    done
}

# Subscriptions without rows get one row each with empty cost cells, so a
# spreadsheet built from the CSV shows the gap rather than a smaller total.
write_csv() {
    local rows_file="${1}" status_file="${2}" csv_file="${3}"
    {
        echo "subscription,service,cost,currency,status"
        jq --raw-output --slurp '.[] | [.sub, .service, .cost, .currency, "ok"] | @csv' "${rows_file}"
        jq --raw-output --slurp '.[] | [.sub, null, null, null, .outcome] | @csv' "${status_file}"
    } >"${csv_file}"
}

# Comma-separated labels of the subscriptions that were not retrieved; an
# empty result is a fact, not a gap, so it is left out.
not_retrieved_labels() {
    local status_file="${1}"
    jq --raw-output --slurp '[.[] | select(.outcome != "empty") | .sub] | join(", ")' "${status_file}"
}

not_retrieved_count() {
    local status_file="${1}"
    jq --raw-output --slurp '[.[] | select(.outcome != "empty")] | length' "${status_file}"
}

# Renders "| name | 0.00 CUR |" rows sorted by cost descending. The jq program
# emits "name<TAB>currency<TAB>bc-expr" lines, where bc-expr sums per-line-item
# r(...) values; bc evaluates it so each table reconciles with its own total.
emit_cost_table() {
    local rows_file="${1}" jq_prog="${2}"
    local name currency expr value
    while IFS=$'\t' read -r name currency expr; do
        # Format with awk, not bash printf: gawk uses "." for %f regardless of
        # locale, while bash printf honors LC_NUMERIC (comma locales break it).
        value="$(bc_eval "${expr}" | awk '{ printf "%.2f", $1 }')"
        printf '%s\t%s\t%s\n' "${value}" "${name}" "${currency}"
    done < <(jq --raw-output --slurp "${jq_prog}" "${rows_file}") |
        sort --field-separator=$'\t' --key=1 --numeric-sort --reverse |
        awk --field-separator='\t' '{ printf "| %s | %s %s |\n", $2, $1, $3 }'
}

write_markdown() {
    local rows_file="${1}" status_file="${2}" md_file="${3}"
    shift 3
    # jq snippet (over an array of row objects) -> "r(c1)+r(c2)+..." for bc.
    local sum_expr='"r(" + ([.[].cost | tostring] | join(")+r(")) + ")"'
    local by_sub='group_by(.sub)[] | [ .[0].sub, (.[0].currency // ""), ('"${sum_expr}"') ] | @tsv'
    local by_service='group_by(.service)[] | [ .[0].service, (.[0].currency // ""), ('"${sum_expr}"') ] | @tsv'
    local pair label has cost service currency expr cur total value
    local missing_count missing_labels excludes=""
    missing_count="$(not_retrieved_count "${status_file}")"
    missing_labels="$(not_retrieved_labels "${status_file}")"
    if [[ "${missing_count}" -gt 0 ]]; then
        excludes="Excludes ${missing_count} subscription(s) not retrieved: ${missing_labels}."
    fi
    {
        echo "# ${BILLING_REPORT_TITLE:-Azure cost report}: ${PERIOD_LABEL}"
        echo
        echo "<!-- markdownlint-disable MD036 -->"
        echo
        echo "Source: Cost Management Query API (ActualCost)."
        echo
        echo "**Retail rates. Does not reconcile to a partner or EA invoice.**"
        echo
        echo "Generated $(date --utc +%FT%TZ 2>/dev/null || date -u +%FT%TZ)."
        echo
        # Ahead of the totals, so nobody reads them as complete first.
        if [[ "${missing_count}" -gt 0 ]]; then
            echo "## Not retrieved"
            echo
            echo "The cost of these subscriptions could not be read; every total below excludes them."
            echo
            jq --raw-output --slurp \
                '.[] | select(.outcome != "empty") | "- **\(.sub)**: \(.explanation)"' "${status_file}"
            echo
        fi
        if jq --exit-status --slurp 'any(.[]; .outcome == "empty")' "${status_file}" >/dev/null; then
            echo "## No cost recorded"
            echo
            echo "The query succeeded and returned zero rows for the period:"
            echo
            jq --raw-output --slurp '.[] | select(.outcome == "empty") | "- \(.sub)"' "${status_file}"
            echo
        fi
        echo "## Total by subscription"
        echo
        echo "| Subscription | Cost |"
        echo "|---|---:|"
        emit_cost_table "${rows_file}" "${by_sub}"
        if [[ -n "${excludes}" ]]; then
            echo
            echo "${excludes}"
        fi
        echo
        echo "## By service per subscription"
        for pair in "${@}"; do
            label="${pair%%=*}"
            has="$(jq --raw-output --slurp --arg s "${label}" 'any(.[]; .sub==$s)' "${rows_file}")"
            [[ "${has}" == "true" ]] || continue
            echo
            echo "### ${label}"
            echo
            echo "| Service | Cost |"
            echo "|---|---:|"
            while IFS=$'\t' read -r cost service currency; do
                value="$(bc_eval "r(${cost})" | awk '{ printf "%.2f", $1 }')"
                printf '| %s | %s %s |\n' "${service}" "${value}" "${currency}"
            done < <(jq --raw-output --slurp --arg s "${label}" \
                '[.[] | select(.sub==$s)] | sort_by(.cost) | reverse | .[] | [.cost, .service, .currency] | @tsv' "${rows_file}")
            expr="$(jq --raw-output --slurp --arg s "${label}" '[.[] | select(.sub==$s)] | '"${sum_expr}" "${rows_file}")"
            cur="$(jq --raw-output --slurp --arg s "${label}" '[.[] | select(.sub==$s)][0].currency // ""' "${rows_file}")"
            total="$(bc_eval "${expr}" | awk '{ printf "%.2f", $1 }')"
            printf '| **Total** | **%s %s** |\n' "${total}" "${cur}"
        done
        echo
        echo "## Top services (all subscriptions)"
        echo
        echo "| Service | Cost |"
        echo "|---|---:|"
        emit_cost_table "${rows_file}" "${by_service}"
        echo
        echo "## Grand total"
        echo
        expr="$(jq --raw-output --slurp "${sum_expr}" "${rows_file}")"
        cur="$(jq --raw-output --slurp '.[0].currency // ""' "${rows_file}")"
        total="$(bc_eval "${expr}" | awk '{ printf "%.2f", $1 }')"
        printf '**%s %s**\n' "${total}" "${cur}"
        if [[ -n "${excludes}" ]]; then
            echo
            echo "${excludes}"
        fi
    } >"${md_file}"
}

cleanup() {
    if [[ -n "${tmp_workspace:-}" && -d "${tmp_workspace}" ]]; then
        rm -rf -- "${tmp_workspace}"
    fi
}

main() {
    require_deps
    [[ -n "${BILLING_SUBS:-}" ]] || die "BILLING_SUBS is not set (space-separated label=subscription-id pairs)"

    resolve_period "${1:-mtd}"

    local out_dir="${BILLING_OUT_DIR:-${PWD}/.local/tmp/az-sub-discovery/billing}"
    local report_name="${BILLING_REPORT_NAME:-billing-report-${PERIOD_SLUG}}"
    [[ -n "${report_name}" && "${report_name}" != */* ]] ||
        die "BILLING_REPORT_NAME must be a file name without a directory: '${report_name}'"
    local csv_file="${out_dir}/${report_name}.csv"
    local md_file="${out_dir}/${report_name}.md"
    # Checked before any query, so a name clash costs nothing against the
    # Cost Management throttle.
    local existing
    for existing in "${md_file}" "${csv_file}"; do
        [[ ! -e "${existing}" ]] ||
            die "${existing} already exists; set BILLING_REPORT_NAME or move it aside"
    done

    local subs=()
    read -r -a subs <<<"${BILLING_SUBS}"

    local body_file="${tmp_workspace}/body.json"
    local rows_file="${tmp_workspace}/rows.jsonl"
    local status_file="${tmp_workspace}/status.jsonl"

    write_body "${body_file}"
    collect_rows "${body_file}" "${rows_file}" "${status_file}" "${subs[@]}"

    local missing_count missing_labels
    missing_count="$(not_retrieved_count "${status_file}")"
    missing_labels="$(not_retrieved_labels "${status_file}")"

    if [[ ! -s "${rows_file}" ]]; then
        [[ "${missing_count}" -eq 0 ]] ||
            echo_stderr "warn: ${missing_count} of ${#subs[@]} subscriptions not retrieved: ${missing_labels}"
        die "no cost rows returned for any subscription in period ${PERIOD_LABEL}"
    fi

    local currencies
    currencies="$(jq --raw-output --slurp '[.[].currency] | unique | join(",")' "${rows_file}")"
    if [[ "${currencies}" == *,* ]]; then
        echo_stderr "warn: multiple currencies present (${currencies}); totals mix currencies, treat with care"
    fi

    mkdir --parents "${out_dir}"

    write_csv "${rows_file}" "${status_file}" "${csv_file}"
    write_markdown "${rows_file}" "${status_file}" "${md_file}" "${subs[@]}"

    cat "${md_file}"

    # Last on stderr, so a caller that pipes or tails the output still sees
    # what is missing and where the files went.
    if [[ "${missing_count}" -gt 0 ]]; then
        echo_stderr "warn: ${missing_count} of ${#subs[@]} subscriptions not retrieved: ${missing_labels}; the report totals exclude them"
    fi
    if [[ -n "${BILLING_OUT_DIR:-}" ]]; then
        echo_stderr "output directory from BILLING_OUT_DIR: ${out_dir}"
    fi
    echo_stderr "wrote: ${md_file}"
    echo_stderr "wrote: ${csv_file}"

    [[ "${missing_count}" -eq 0 ]] || exit "${EXIT_PARTIAL}"
}

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    # Scratch dir, removed by the EXIT trap. Initialised here so
    # the trap never dereferences an unbound var under `set -u`.
    tmp_workspace="$(mktemp --directory)"
    trap cleanup EXIT
    main "${@}"
fi
