#!/usr/bin/env bats
# az-billing-report.bash against canned Cost Management responses. The fakes in
# bin/ replace az, curl and sleep on PATH, so the real cm_query and report code
# run end to end without touching Azure.

bats_require_minimum_version 1.5.0

readonly SUB_OK="00000000-0000-0000-0000-000000000001"
readonly SUB_CSP="00000000-0000-0000-0000-000000000002"
readonly SUB_EMPTY="00000000-0000-0000-0000-000000000003"
readonly SUB_OTHER="00000000-0000-0000-0000-000000000004"
readonly SUB_NOTOKEN="00000000-0000-0000-0000-000000000005"

function setup() {
    export FAKE_CM_DIR="${BATS_TEST_TMPDIR}/cm"
    mkdir -p "${FAKE_CM_DIR}"
    export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
    export BILLING_OUT_DIR="${BATS_TEST_TMPDIR}/out"
    export BILLING_REPORT_NAME="report"
    MD="${BILLING_OUT_DIR}/report.md"
    CSV="${BILLING_OUT_DIR}/report.csv"

    fixture "${SUB_OK}" 200 '{"properties":{"columns":[{"name":"PreTaxCost"},{"name":"ServiceName"},{"name":"Currency"}],"rows":[[12.345,"Virtual Machines","EUR"],[1.5,"Storage","EUR"]]}}'
    fixture "${SUB_CSP}" 400 '{"error":{"code":"SubscriptionCostDisabled","message":"Customer does not have the privilege to see the cost"}}'
    fixture "${SUB_EMPTY}" 200 '{"properties":{"columns":[{"name":"PreTaxCost"},{"name":"ServiceName"},{"name":"Currency"}],"rows":[]}}'
    fixture "${SUB_OTHER}" 400 '{"error":{"code":"BadRequest","message":"Invalid query"}}'
    touch "${FAKE_CM_DIR}/${SUB_NOTOKEN}.notoken"
}

function fixture() {
    local -r sub="${1}" status="${2}" body="${3}"
    printf '%s' "${status}" >"${FAKE_CM_DIR}/${sub}.status"
    printf '%s' "${body}" >"${FAKE_CM_DIR}/${sub}.body"
}

function report() {
    local -r subs="${1}"
    BILLING_SUBS="${subs}" "${BATS_TEST_DIRNAME}/../az-billing-report.bash"
}

@test "every subscription read: exit 0, no gap sections, status ok in the CSV" {
    local subs="prod=${SUB_OK}"
    run report "${subs}"
    [ "${status}" -eq 0 ]
    run ! grep --quiet '## Not retrieved' "${MD}"
    run ! grep --quiet '## No cost recorded' "${MD}"
    run ! grep --quiet 'Excludes' "${MD}"
    grep --quiet --fixed-strings '**13.85 EUR**' "${MD}"
    [ "$(head --lines=1 "${CSV}")" = "subscription,service,cost,currency,status" ]
    grep --quiet --fixed-strings '"prod","Virtual Machines",12.345,"EUR","ok"' "${CSV}"
}

@test "CSP subscription refused: listed as not retrieved with the CSP cause, exit 2" {
    local subs="prod=${SUB_OK} csp=${SUB_CSP}"
    run report "${subs}"
    [ "${status}" -eq 2 ]
    grep --quiet '^## Not retrieved$' "${MD}"
    grep --quiet --fixed-strings -- '- **csp**: Not retrieved: cost visibility is disabled' "${MD}"
    grep --quiet 'CSP (partner-billed)' "${MD}"
    grep --quiet --fixed-strings '**13.85 EUR**' "${MD}"
    [ "$(grep --count --fixed-strings 'Excludes 1 subscription(s) not retrieved: csp.' "${MD}")" -eq 2 ]
    run ! grep --quiet '^### csp$' "${MD}"
    grep --quiet --fixed-strings '"csp",,,,"cost_disabled"' "${CSV}"
}

@test "not-retrieved section comes before the totals" {
    local subs="prod=${SUB_OK} csp=${SUB_CSP}"
    run report "${subs}"
    local gap totals
    gap="$(grep --line-number '^## Not retrieved$' "${MD}" | cut --delimiter=: --fields=1)"
    totals="$(grep --line-number '^## Total by subscription$' "${MD}" | cut --delimiter=: --fields=1)"
    [ "${gap}" -lt "${totals}" ]
}

@test "zero rows: listed as no cost recorded, not as a gap, exit 0" {
    local subs="prod=${SUB_OK} idle=${SUB_EMPTY}"
    run report "${subs}"
    [ "${status}" -eq 0 ]
    grep --quiet '^## No cost recorded$' "${MD}"
    grep --quiet '^- idle$' "${MD}"
    run ! grep --quiet '## Not retrieved' "${MD}"
    run ! grep --quiet 'Excludes' "${MD}"
    grep --quiet --fixed-strings '"idle",,,,"empty"' "${CSV}"
}

@test "other 400: generic error outcome carrying the response" {
    local subs="prod=${SUB_OK} other=${SUB_OTHER}"
    run report "${subs}"
    [ "${status}" -eq 2 ]
    grep --quiet --fixed-strings -- '- **other**: Not retrieved: HTTP 400:' "${MD}"
    run ! grep --quiet 'CSP' "${MD}"
    grep --quiet --fixed-strings '"other",,,,"error"' "${CSV}"
}

@test "no token: recorded as no_token, exit 2" {
    local subs="prod=${SUB_OK} orphan=${SUB_NOTOKEN}"
    run report "${subs}"
    [ "${status}" -eq 2 ]
    grep --quiet --fixed-strings -- '- **orphan**: Not retrieved: could not acquire an access token' "${MD}"
    grep --quiet --fixed-strings '"orphan",,,,"no_token"' "${CSV}"
}

@test "partial run: stderr ends with the summary and the written paths" {
    local subs="prod=${SUB_OK} csp=${SUB_CSP}"
    run --separate-stderr report "${subs}"
    [ "${status}" -eq 2 ]
    local n="${#stderr_lines[@]}"
    [[ "${stderr_lines[n - 4]}" == "warn: 1 of 2 subscriptions not retrieved: csp; the report totals exclude them" ]]
    [[ "${stderr_lines[n - 3]}" == "output directory from BILLING_OUT_DIR: ${BILLING_OUT_DIR}" ]]
    [[ "${stderr_lines[n - 2]}" == "wrote: ${MD}" ]]
    [[ "${stderr_lines[n - 1]}" == "wrote: ${CSV}" ]]
}

@test "every subscription refused: exit 1, no files, refusals named on stderr" {
    local subs="csp=${SUB_CSP} other=${SUB_OTHER}"
    run --separate-stderr report "${subs}"
    [ "${status}" -eq 1 ]
    [ ! -e "${MD}" ]
    [ ! -e "${CSV}" ]
    [[ "${stderr}" == *"warn: 2 of 2 subscriptions not retrieved: csp, other"* ]]
    [[ "${stderr}" == *"error: no cost rows returned for any subscription"* ]]
}
