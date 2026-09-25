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
#                         filenames, which stay keyed to the period so
#                         successive runs remain sortable.

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

# Sets the period globals from the CLI argument.
resolve_period() {
    local period_arg="${1}"
    if [[ "${period_arg}" == "mtd" ]]; then
        TIMEFRAME="MonthToDate"
        PERIOD_FROM=""
        PERIOD_TO=""
        PERIOD_LABEL="month-to-date ($(current_month))"
        PERIOD_SLUG="$(current_month)-mtd"
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

collect_rows() {
    local body_file="${1}" rows_file="${2}"
    shift 2
    local pair label sub
    local resp="${tmp_workspace}/response.json"
    : >"${rows_file}"
    for pair in "${@}"; do
        label="${pair%%=*}"
        sub="${pair##*=}"
        [[ "${label}" != "${pair}" ]] || die "malformed BILLING_SUBS entry: '${pair}' (expected label=subscription-id)"
        [[ "${sub}" =~ ^[0-9a-fA-F-]{36}$ ]] || die "not a subscription id in BILLING_SUBS entry '${pair}'"
        echo_stderr "querying ${label} ..."
        if cm_query "${ARM_TOKEN}" "${sub}" "${body_file}" "${resp}" \
            "${tmp_workspace}/${label}" echo_stderr_indented; then
            jq --compact-output --arg label "${label}" \
                '(.properties.rows // [])[] | {sub:$label, service:.[1], cost:.[0], currency:.[2]}' \
                "${resp}" >>"${rows_file}"
        else
            # An empty result is a fact about the period, not a failure to
            # report as one; everything else names its own cause.
            echo_stderr "  ${label}: $(cm_explain)"
        fi
        sleep 3
    done
}

write_csv() {
    local rows_file="${1}" csv_file="${2}"
    {
        echo "subscription,service,cost,currency"
        jq --raw-output --slurp '.[] | [.sub, .service, .cost, .currency] | @csv' "${rows_file}"
    } >"${csv_file}"
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
    local rows_file="${1}" md_file="${2}"
    shift 2
    # jq snippet (over an array of row objects) -> "r(c1)+r(c2)+..." for bc.
    local sum_expr='"r(" + ([.[].cost | tostring] | join(")+r(")) + ")"'
    local by_sub='group_by(.sub)[] | [ .[0].sub, (.[0].currency // ""), ('"${sum_expr}"') ] | @tsv'
    local by_service='group_by(.service)[] | [ .[0].service, (.[0].currency // ""), ('"${sum_expr}"') ] | @tsv'
    local pair label has cost service currency expr cur total value
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
        echo "## Total by subscription"
        echo
        echo "| Subscription | Cost |"
        echo "|---|---:|"
        emit_cost_table "${rows_file}" "${by_sub}"
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
    local subs=()
    read -r -a subs <<<"${BILLING_SUBS}"

    local body_file="${tmp_workspace}/body.json"
    local rows_file="${tmp_workspace}/rows.jsonl"

    # One token for the run: ARM tokens outlive a report, and re-fetching per
    # subscription would add its own throttling surface.
    ARM_TOKEN="$(cm_token)" || die "could not acquire an ARM access token (az login?)"
    [[ -n "${ARM_TOKEN}" ]] || die "empty ARM access token"

    write_body "${body_file}"
    collect_rows "${body_file}" "${rows_file}" "${subs[@]}"

    [[ -s "${rows_file}" ]] || die "no cost rows returned for any subscription in period ${PERIOD_LABEL}"

    local currencies
    currencies="$(jq --raw-output --slurp '[.[].currency] | unique | join(",")' "${rows_file}")"
    if [[ "${currencies}" == *,* ]]; then
        echo_stderr "warn: multiple currencies present (${currencies}); totals mix currencies, treat with care"
    fi

    mkdir --parents "${out_dir}"
    local csv_file="${out_dir}/billing-report-${PERIOD_SLUG}.csv"
    local md_file="${out_dir}/billing-report-${PERIOD_SLUG}.md"

    write_csv "${rows_file}" "${csv_file}"
    write_markdown "${rows_file}" "${md_file}" "${subs[@]}"

    echo_stderr "wrote: ${md_file}"
    echo_stderr "wrote: ${csv_file}"
    cat "${md_file}"
}

# Set in main(), read by query_sub(). Declared here so `set -u` never trips.
ARM_TOKEN=""

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    # Scratch dir, removed by the EXIT trap. Initialised here so
    # the trap never dereferences an unbound var under `set -u`.
    tmp_workspace="$(mktemp --directory)"
    trap cleanup EXIT
    main "${@}"
fi
