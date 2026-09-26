#!/usr/bin/env bash
#
# Core helpers shared by every module. Sourced by az-sub-discovery.bash; defines
# functions only, no work at load time.
#
# Module contract:
#   - define `function module_NN_<name>()`; NN is the run order
#   - first statement: report_begin "Human title"
#   - fetch with run_az_json / az_rest_json / arg_query (raw JSON lands in AZSD_RAW_DIR)
#   - render with emit / emit_section / emit_table / emit_columns / emit_table_from
#   - optionally define `function module_NN_<name>_types()` printing the resource
#     types the module covers, one per line; the summary reports uncovered types
#   - return 0 unless the module could not produce a report at all

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

AZSD_AZ_TIMEOUT="${AZSD_AZ_TIMEOUT:-120}"
AZSD_ARG_API_VERSION="2022-10-01"
# shellcheck disable=SC2034  # read by lib/27-cost.bash
AZSD_COST_API_VERSION="2023-11-01"

AZSD_MODULE=""
AZSD_RAW_DIR=""
AZSD_REPORT_FILE=""

AZSD_RUN_STARTED=""
AZSD_TOOL_VERSION="unknown"
AZSD_TENANT_ID="unknown"
AZSD_SUBSCRIPTION_NAME="unknown"
AZSD_CALLER_TYPE="unknown"
AZSD_CALLER_OID="unknown"

# ---------------------------------------------------------------------------
# logging (stderr only)

function echo_stderr() {
    echo "${*}" >&2
}

function log_level_to_num() {
    case "${1}" in
    "trace") echo 1 ;;
    "debug") echo 5 ;;
    "info") echo 9 ;;
    "warn") echo 13 ;;
    "error") echo 17 ;;
    "fatal") echo 21 ;;
    *) echo 9 ;;
    esac
}

function log() {
    local configured="${AZSD_LOG_LEVEL:-${OTEL_LOG_LEVEL:-info}}"
    configured="${configured,,}"
    local -r threshold=$(log_level_to_num "${configured}")
    local -r level="${1,,}"
    local -r message="${2}"
    local -r severity=$(log_level_to_num "${level}")
    if ((severity >= threshold)); then
        echo_stderr "[$(date -u +%H:%M:%S)] [${level}] [${AZSD_MODULE:-runner}] ${message}"
    fi
}

function log_debug() { log "debug" "${1:-}"; }
function log_info() { log "info" "${1:-}"; }
function log_warn() { log "warn" "${1:-}"; }
function log_error() { log "error" "${1:-}"; }

# ---------------------------------------------------------------------------
# predicates

function is_guid() {
    [[ "${1}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# ARM resource names and types: charset is constrained by the API, which is what
# makes them safe to place in file names and in OData/KQL text.
function is_arm_name() {
    [[ "${1}" =~ ^[A-Za-z0-9._()/-]+$ ]]
}

# ---------------------------------------------------------------------------
# az wrappers

function timeout_bin() {
    if command -v timeout >/dev/null 2>&1; then
        echo "timeout"
    else
        echo "gtimeout"
    fi
}

# az with the subscription pinned and JSON output, capped so a hung call fails
# instead of stalling the sweep.
function az_json() {
    "$(timeout_bin)" "${AZSD_AZ_TIMEOUT}" \
        az "${@}" --subscription "${AZSD_SUBSCRIPTION_ID}" --only-show-errors --output json
}

# Save `az ...` output to AZSD_RAW_DIR/<name>.json. On failure writes [] and a
# sibling .err so downstream jq still works and the reason is kept.
# Returns 1 on failure so a module can branch, but callers may ignore that.
function run_az_json() {
    local name="${1}"
    shift
    local out="${AZSD_RAW_DIR}/${name}.json"
    if az_json "${@}" >"${out}" 2>"${out}.err"; then
        rm -f "${out}.err"
        return 0
    fi
    log_warn "az ${*} failed; see ${out}.err"
    echo "[]" >"${out}"
    return 1
}

# Same for `az rest`. Usage: az_rest_json NAME METHOD URL [BODY_FILE]
function az_rest_json() {
    local name="${1}"
    local method="${2}"
    local url="${3}"
    local body_file="${4:-}"
    local out="${AZSD_RAW_DIR}/${name}.json"
    local args=(rest --method "${method}" --url "${url}" --only-show-errors --output json)
    if [ -n "${body_file}" ]; then
        args+=(--body "@${body_file}")
    fi
    if "$(timeout_bin)" "${AZSD_AZ_TIMEOUT}" az "${args[@]}" >"${out}" 2>"${out}.err"; then
        rm -f "${out}.err"
        return 0
    fi
    log_warn "az rest ${method} ${url} failed; see ${out}.err"
    echo "[]" >"${out}"
    return 1
}

# Resource Graph query from a .kql file in lib/, scoped to the subscription via
# the request body (no interpolation into the query). Result saved as the bare
# data array. Single page (top 1000); a $skipToken is logged, not followed.
function arg_query() {
    local name="${1}"
    local kql_file="${AZSD_LIB_DIR}/${2}"
    if [ ! -r "${kql_file}" ]; then
        log_warn "kql file not found: ${kql_file}"
        echo "[]" >"${AZSD_RAW_DIR}/${name}.json"
        return 1
    fi
    local body="${AZSD_RAW_DIR}/${name}.request.json"
    if ! jq --null-input --arg sub "${AZSD_SUBSCRIPTION_ID}" --rawfile q "${kql_file}" \
        '{subscriptions: [$sub], query: $q, options: {resultFormat: "objectArray", "$top": 1000}}' >"${body}"; then
        log_warn "failed to build resource graph request for ${name}"
        return 1
    fi
    local url="https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=${AZSD_ARG_API_VERSION}"
    if ! az_rest_json "${name}.response" POST "${url}" "${body}"; then
        echo "[]" >"${AZSD_RAW_DIR}/${name}.json"
        return 1
    fi
    if jq --exit-status '.["$skipToken"] // empty' "${AZSD_RAW_DIR}/${name}.response.json" >/dev/null 2>&1; then
        log_warn "resource graph ${name}: more than 1000 rows, result truncated"
    fi
    jq '.data // []' "${AZSD_RAW_DIR}/${name}.response.json" >"${AZSD_RAW_DIR}/${name}.json"
}

# ---------------------------------------------------------------------------
# provenance

# Who ran the sweep, against what, with which build. The caller is recorded as
# principal type and Entra object id, never a user principal name: reports get
# copied one by one into other repositories, and a UPN is an email address.
# The object id comes from the ARM token's own claims, so no Graph permission
# is needed. The token is decoded in a pipe and never written anywhere.
function resolve_provenance() {
    AZSD_RUN_STARTED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local manifest="${AZSD_SCRIPT_DIR:-}/../../../plugin.json"
    if [ -r "${manifest}" ]; then
        AZSD_TOOL_VERSION="$(jq --raw-output '.version // "unknown"' "${manifest}" 2>/dev/null || echo unknown)"
    fi

    local account
    if account="$(az account show --subscription "${AZSD_SUBSCRIPTION_ID}" --only-show-errors \
        --query "{name:name, tenant:tenantId, type:user.type}" --output json 2>/dev/null)"; then
        AZSD_SUBSCRIPTION_NAME="$(jq --raw-output '.name // "unknown"' <<<"${account}")"
        AZSD_TENANT_ID="$(jq --raw-output '.tenant // "unknown"' <<<"${account}")"
        AZSD_CALLER_TYPE="$(jq --raw-output '.type // "unknown"' <<<"${account}")"
    else
        log_warn "provenance: az account show failed; subscription name and tenant unknown"
    fi

    local claims
    if claims="$(az account get-access-token --subscription "${AZSD_SUBSCRIPTION_ID}" --only-show-errors \
        --resource "https://management.azure.com" --query accessToken --output tsv 2>/dev/null |
        jq --raw-input --from-file "${AZSD_LIB_DIR}/token-claims.jq" 2>/dev/null)"; then
        AZSD_CALLER_OID="$(jq --raw-output '.oid // "unknown"' <<<"${claims}")"
        case "$(jq --raw-output '.idtyp // ""' <<<"${claims}")" in
        app) AZSD_CALLER_TYPE="servicePrincipal" ;;
        user) AZSD_CALLER_TYPE="user" ;;
        esac
    else
        log_warn "provenance: could not read the caller's object id from the token"
    fi

    local run_dir="${AZSD_OUTPUT_DIR}/raw/_run"
    rm -rf -- "${run_dir}"
    mkdir -p "${run_dir}"
    if is_guid "${AZSD_CALLER_OID}"; then
        az_json role assignment list --assignee-object-id "${AZSD_CALLER_OID}" --include-inherited --all \
            --query "[].{role:roleDefinitionName, scope:scope}" >"${run_dir}/caller-roles.json" 2>"${run_dir}/caller-roles.json.err" &&
            rm -f "${run_dir}/caller-roles.json.err"
    fi
    return 0
}

# One line for every report header, so a report copied on its own still says
# where it came from.
function provenance_line() {
    # shellcheck disable=SC2016  # literal markdown backticks
    printf 'az-sub-orienteering %s · tenant `%s` · caller %s `%s`' \
        "${AZSD_TOOL_VERSION}" "${AZSD_TENANT_ID}" "${AZSD_CALLER_TYPE}" "${AZSD_CALLER_OID}"
}

# ---------------------------------------------------------------------------
# failed calls

# Print the .err file recording why FILE could not be fetched, if there is one.
# arg_query leaves its error beside the response file, not the data file.
function call_error_file() {
    local file="${1}"
    local candidate
    for candidate in "${file}.err" "${file%.json}.response.json.err"; do
        if [ -e "${candidate}" ]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 1
}

# One-line cause for a failed call, worded as a fact about the caller or the
# subscription, never about the resource. The CLI's own wording misleads in
# at least one case: a call to an unregistered resource provider answers "The
# specified subscription does not exist" about a subscription it can read.
function describe_failure() {
    local err="${1}"
    if [ ! -s "${err}" ]; then
        printf 'no response within %ss, or the call failed without an error message' "${AZSD_AZ_TIMEOUT}"
        return 0
    fi
    if grep --quiet --ignore-case --extended-regexp \
        'MissingSubscriptionRegistration|SubscriptionNotRegistered|Subscription Not Registered|not registered to use namespace|specified subscription .* does not exist' "${err}"; then
        printf 'resource provider not registered in this subscription, so the service has never been used here (the subscription itself exists)'
    elif grep --quiet --ignore-case --extended-regexp \
        'AuthorizationFailed|AuthorizationPermissionMismatch|Forbidden|\(403\)|does not have authorization|insufficient privileges' "${err}"; then
        printf "access denied: the caller's roles do not cover this call"
    elif grep --quiet --ignore-case --extended-regexp '\(429\)|TooManyRequests|throttl' "${err}"; then
        printf 'throttled by the API; the data may well exist'
    else
        printf 'error: %s' "$(grep --max-count 1 --extended-regexp '^(ERROR|Message):' "${err}" |
            sed -e 's/^[A-Za-z]*: *//' -e 's/[`|]/ /g' | cut -c1-200)"
    fi
}

# Count of FILE's items, or a could-not-read note. A failed call leaves "[]",
# which json_count alone would report as a confident zero.
function count_or_unread() {
    local file="${1}"
    local err
    if err="$(call_error_file "${file}")"; then
        printf '_could not read: %s_' "$(describe_failure "${err}")"
        return 0
    fi
    json_count "${file}"
}

# Emit a could-not-read note and succeed when FILE's call failed; fail otherwise.
function emit_if_unread() {
    local file="${1}"
    local err
    err="$(call_error_file "${file}")" || return 1
    emit "_(could not read: $(describe_failure "${err}"))_"
    return 0
}

# ---------------------------------------------------------------------------
# json helpers

function json_count() {
    local file="${1}"
    if [ ! -s "${file}" ]; then
        echo 0
        return 0
    fi
    jq --from-file "${AZSD_LIB_DIR}/count.jq" "${file}" 2>/dev/null || echo 0
}

# Older az builds wrap some lists as {value: [...]}; unwrap in place.
function normalize_list() {
    local file="${1}"
    local tmp="${file}.norm"
    if jq --from-file "${AZSD_LIB_DIR}/normalize-list.jq" "${file}" >"${tmp}"; then
        mv "${tmp}" "${file}"
    else
        rm -f "${tmp}"
        return 1
    fi
}

function inventory_file() {
    echo "${AZSD_OUTPUT_DIR}/raw/inventory/all-resources.json"
}

function inventory_count() {
    local rtype="${1}"
    local inv
    inv="$(inventory_file)"
    if [ ! -s "${inv}" ]; then
        echo 0
        return 0
    fi
    jq --arg t "${rtype}" '[.[] | select(.type | ascii_downcase == ($t | ascii_downcase))] | length' "${inv}" 2>/dev/null || echo 0
}

# Print "name<TAB>resourceGroup<TAB>id" for every inventory resource of a type.
function inventory_of_type() {
    local rtype="${1}"
    local inv
    inv="$(inventory_file)"
    [ -s "${inv}" ] || return 0
    jq --raw-output --arg t "${rtype}" \
        '.[] | select(.type | ascii_downcase == ($t | ascii_downcase)) | [.name, .resourceGroup, .id] | @tsv' "${inv}"
}

# Short-circuit for service modules: emit a one-liner and return 0 when the
# inventory has none of the given types.
function skip_if_absent() {
    local total=0
    local t n
    for t in "${@}"; do
        n="$(inventory_count "${t}")"
        total=$((total + n))
    done
    if [ "${total}" -eq 0 ]; then
        emit "_(no resources of type: ${*})_"
        log_info "none present, skipping"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# module lifecycle and report output

# Starts a module with an empty raw directory, so its contents always describe
# exactly one run. Without this, a file the module has stopped producing — after
# a fix, or because a resource type is gone — survives indefinitely and reads as
# current. A stale `.json.err` is the damaging case: those files are the evidence
# for which calls were refused, so an old one inflates a permissions audit.
function module_setup() {
    AZSD_MODULE="${1}"
    AZSD_RAW_DIR="${AZSD_OUTPUT_DIR}/raw/${AZSD_MODULE}"
    AZSD_REPORT_FILE="${AZSD_OUTPUT_DIR}/reports/${AZSD_MODULE}.md"

    # Refuse to delete anything that is not the path this function just derived:
    # a non-empty module name, and a directory that really sits under the run's
    # own raw/ directory.
    if [ -d "${AZSD_RAW_DIR}" ] &&
        [ -n "${AZSD_MODULE}" ] &&
        [ -n "${AZSD_OUTPUT_DIR}" ] &&
        [ "${AZSD_RAW_DIR}" = "${AZSD_OUTPUT_DIR}/raw/${AZSD_MODULE}" ]; then
        rm -rf -- "${AZSD_RAW_DIR}"
    fi
    mkdir -p "${AZSD_RAW_DIR}"
}

# Move FILE to history/<its Generated timestamp>/REL before it is rewritten, so
# a re-run never destroys the earlier result and the two can be diffed. A file
# without a Generated line (written before the header existed) is stamped with
# its modification time.
function archive_previous() {
    local file="${1}"
    local rel="${2}"
    [ -f "${file}" ] || return 0
    local stamp
    stamp="$(sed -n 's/^- \*\*Generated:\*\* //p' "${file}" | head -1)"
    [ -n "${stamp}" ] || stamp="$(date -u -r "${file}" +"%Y-%m-%dT%H:%M:%SZ")"
    stamp="${stamp//:/}"
    local dest="${AZSD_OUTPUT_DIR}/history/${stamp}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    mv -f -- "${file}" "${dest}"
}

function report_begin() {
    local title="${1}"
    archive_previous "${AZSD_REPORT_FILE}" "reports/${AZSD_MODULE}.md"
    {
        echo "# ${title}"
        echo
        echo "- **Module:** \`${AZSD_MODULE}\`"
        echo "- **Subscription:** \`${AZSD_SUBSCRIPTION_ID}\` (${AZSD_SUBSCRIPTION_NAME})"
        echo "- **Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "- **Provenance:** $(provenance_line)"
        echo "- **Raw JSON:** \`raw/${AZSD_MODULE}/\`"
    } >"${AZSD_REPORT_FILE}"
}

function emit() {
    echo "${*}" >>"${AZSD_REPORT_FILE}"
}

function emit_section() {
    emit ""
    emit "## ${*}"
    emit ""
}

function emit_subsection() {
    emit ""
    emit "### ${*}"
    emit ""
}

function emit_json_file() {
    local file="${1}"
    emit_if_unread "${file}" && return 0
    if [ "$(json_count "${file}")" = "0" ]; then
        emit "_(none)_"
        return 0
    fi
    emit '```json'
    jq '.' "${file}" >>"${AZSD_REPORT_FILE}"
    emit '```'
}

# Render rows (an array of arrays on stdin) as a markdown table.
function render_table() {
    local header="${1}"
    jq --raw-output --arg header "${header}" --from-file "${AZSD_LIB_DIR}/md-table.jq"
}

# emit_table FILE "Col|Col" 'ROW_FILTER' [jq args...]
# ROW_FILTER is a jq program literal from module source producing a stream of
# row arrays; shell values go in via --arg after it, never interpolated.
function emit_table() {
    local file="${1}"
    local header="${2}"
    local filter="${3}"
    shift 3
    emit_if_unread "${file}" && return 0
    if [ "$(json_count "${file}")" = "0" ]; then
        emit "_(none found)_"
        return 0
    fi
    if ! jq "${@}" "[ ${filter} ]" "${file}" | render_table "${header}" >>"${AZSD_REPORT_FILE}"; then
        log_warn "table render failed for ${file}"
        emit "_(render failed; see raw JSON)_"
    fi
}

# emit_table_from FILE "Col|Col" program.jq [jq args...]
# program.jq lives in lib/ and outputs an array of row arrays.
function emit_table_from() {
    local file="${1}"
    local header="${2}"
    local program="${AZSD_LIB_DIR}/${3}"
    shift 3
    emit_if_unread "${file}" && return 0
    if [ "$(json_count "${file}")" = "0" ]; then
        emit "_(none found)_"
        return 0
    fi
    if ! jq "${@}" --from-file "${program}" "${file}" | render_table "${header}" >>"${AZSD_REPORT_FILE}"; then
        log_warn "table render failed for ${file} via ${program}"
        emit "_(render failed; see raw JSON)_"
    fi
}

# emit_columns FILE "Col|Col" "path|nested.path|other"
# Projects dotted paths from each element; null renders as "-".
function emit_columns() {
    local file="${1}"
    local header="${2}"
    local columns="${3}"
    emit_table_from "${file}" "${header}" "project.jq" --arg columns "${columns}"
}

# emit_group_count FILE "Col|Count" "dotted.path"
function emit_group_count() {
    local file="${1}"
    local header="${2}"
    local path="${3}"
    emit_table_from "${file}" "${header}" "group-count.jq" --arg path "${path}"
}

# ---------------------------------------------------------------------------
# summary

function covered_types() {
    local fn
    while IFS= read -r fn; do
        [ -z "${fn}" ] && continue
        "${fn}" 2>/dev/null || true
    done < <(declare -F | awk '{print $3}' | grep -E '^module_[0-9]+_[a-z0-9_]+_types$') | tr '[:upper:]' '[:lower:]' | sort -u
}

# Records a completed unfiltered sweep, so a later filtered run can say how old
# the full picture is. Written only when nothing was filtered and nothing failed.
function record_full_sweep() {
    local failed_count="${1}"
    [ -z "${AZSD_ONLY:-}" ] && [ -z "${AZSD_SKIP:-}" ] || return 0
    [ "${failed_count}" -eq 0 ] || return 0
    printf '%s\t%s of %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "${AZSD_DONE_COUNT}" "${AZSD_TOTAL_COUNT}" >"${AZSD_OUTPUT_DIR}/.last-full-sweep"
}

# Every failed call on disk, grouped by module and cause. Without this a
# refused call is visible only as a note deep in one report, and the summary
# reads as though every module saw everything.
function summarise_failed_calls() {
    local raw="${AZSD_OUTPUT_DIR}/raw"
    local err module call cause
    while IFS= read -r err; do
        [ -z "${err}" ] && continue
        module="$(basename "$(dirname "${err}")")"
        [ "${module}" = "_run" ] && module="provenance"
        call="$(basename "${err}")"
        call="${call%.json.err}"
        call="${call%.response}"
        cause="$(describe_failure "${err}")"
        printf '%s\t%s\t%s\n' "${module}" "${cause}" "${call}"
    done < <(find "${raw}" -name '*.err' -type f 2>/dev/null | sort) |
        jq --raw-input --slurp --from-file "${AZSD_LIB_DIR}/failed-calls.jq"
}

function write_summary() {
    local failed=("${@}")
    local summary="${AZSD_OUTPUT_DIR}/summary.md"
    local inv
    inv="$(inventory_file)"

    local filter=""
    [ -n "${AZSD_ONLY:-}" ] && filter="--only ${AZSD_ONLY}"
    [ -n "${AZSD_SKIP:-}" ] && filter="${filter:+${filter} }--skip ${AZSD_SKIP}"

    record_full_sweep "${#failed[@]}"
    archive_previous "${summary}" "summary.md"

    local last_full=""
    [ -r "${AZSD_OUTPUT_DIR}/.last-full-sweep" ] &&
        last_full="$(cat "${AZSD_OUTPUT_DIR}/.last-full-sweep")"

    {
        echo "# Subscription discovery: ${AZSD_SUBSCRIPTION_ID}"
        echo
        echo "- **Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        if [ -n "${filter}" ]; then
            # A filtered run says so in the count itself. The reports list below
            # is every report on disk, most of them from earlier runs, so a bare
            # "2 of 2" above a list of eighteen reads as sixteen failures.
            echo "- **This run:** filtered (\`${filter}\`) — ${AZSD_DONE_COUNT} of ${AZSD_TOTAL_COUNT} selected modules"
            if [ -n "${last_full}" ]; then
                echo "- **Last full sweep:** ${last_full%%$'\t'*} (${last_full##*$'\t'})"
            else
                echo "- **Last full sweep:** none recorded in this output directory"
            fi
            echo "- **Reports below are not all from this run.** Each report carries its own"
            echo "  \`Generated\` timestamp; trust that over this page."
        else
            echo "- **Modules completed:** ${AZSD_DONE_COUNT} of ${AZSD_TOTAL_COUNT}"
        fi
        if [ "${#failed[@]}" -gt 0 ]; then
            echo "- **Failed modules:** ${failed[*]}"
        fi
        echo "- **Earlier versions:** \`history/<Generated>/\`, one folder per replaced report or summary"
        echo
        echo "## Provenance"
        echo
        echo "| Field | Value |"
        echo "| --- | --- |"
        echo "| Tool | az-sub-orienteering ${AZSD_TOOL_VERSION}, read-only |"
        echo "| Run started | ${AZSD_RUN_STARTED} |"
        echo "| Tenant | \`${AZSD_TENANT_ID}\` |"
        echo "| Subscription | \`${AZSD_SUBSCRIPTION_ID}\` (${AZSD_SUBSCRIPTION_NAME}) |"
        echo "| Caller | ${AZSD_CALLER_TYPE}, object id \`${AZSD_CALLER_OID}\` |"
        echo
        echo "Roles the caller holds, directly or inherited from a parent scope; roles"
        echo "held through group membership are not listed. Everything below is what"
        echo "this access could see: anything hidden from it is absent, not missing."
        echo
    } >"${summary}"

    local roles="${AZSD_OUTPUT_DIR}/raw/_run/caller-roles.json"
    if [ -e "${roles}" ] || [ -e "${roles}.err" ]; then
        local AZSD_REPORT_FILE="${summary}"
        emit_table "${roles}" "Role|Scope" \
            '.[] | [.role, (.scope | if . == "/" then "tenant root" elif test("/managementGroups/") then "management group " + (split("/") | last) elif test("^/subscriptions/[^/]+$") then "subscription" elif test("/resourceGroups/[^/]+$"; "i") then "resource group " + (split("/") | last) else "resource " + (split("/") | last) end)]'
    else
        echo "_(not read: the caller's object id is unknown)_" >>"${summary}"
    fi

    {
        echo
        echo "## Reports"
        echo
    } >>"${summary}"

    local report base generated
    while IFS= read -r report; do
        [ -z "${report}" ] && continue
        base="$(basename "${report}" .md)"
        generated="$(sed -n 's/^- \*\*Generated:\*\* //p' "${report}" | head -1)"
        echo "- [${base}](reports/${base}.md)${generated:+ — ${generated}}" >>"${summary}"
    done < <(find "${AZSD_OUTPUT_DIR}/reports" -maxdepth 1 -name '*.md' -type f | sort)

    {
        echo
        echo "## Calls that failed"
        echo
        echo "Each is a gap in what the reports show, never evidence that nothing is there."
        echo
    } >>"${summary}"
    local failed_rows
    failed_rows="$(summarise_failed_calls)"
    if [ "$(jq 'length' <<<"${failed_rows}")" = "0" ]; then
        echo "_(none: every call returned)_" >>"${summary}"
    else
        render_table "Module|Cause|Calls|Examples" <<<"${failed_rows}" >>"${summary}"
    fi

    {
        echo
        echo "## Resource types with no dedicated module"
        echo
        echo "Observed in the inventory but not inspected in depth by any module. Unexplored territory: look here next."
        echo
    } >>"${summary}"

    if [ ! -s "${inv}" ]; then
        echo "_(inventory missing)_" >>"${summary}"
    else
        local covered_file="${AZSD_OUTPUT_DIR}/raw/inventory/covered-types.txt"
        covered_types >"${covered_file}"
        jq --rawfile covered "${covered_file}" --from-file "${AZSD_LIB_DIR}/uncovered-types.jq" "${inv}" |
            render_table "Resource type|Count" >>"${summary}"
    fi

    {
        echo
        echo "## Outside this sweep"
        echo
        echo "A control-plane read. It does not reach, and no report here speaks to:"
        echo
        echo "- **Anything inside a virtual machine**: SQL Agent jobs, linked servers, SSIS"
        echo "  packages, SSRS, IIS sites, file shares, scheduled tasks, local accounts."
        echo "- **Azure DevOps**: repositories, pipelines, agents, service connections. It is"
        echo "  not an Azure resource provider, so nothing here reveals the delivery chain."
        echo "- **Key Vault contents and blob data**, unless the caller also holds data-plane"
        echo "  roles; see the failed calls above."
    } >>"${summary}"
}
