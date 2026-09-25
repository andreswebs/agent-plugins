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

function report_begin() {
    local title="${1}"
    {
        echo "# ${title}"
        echo
        echo "- **Module:** \`${AZSD_MODULE}\`"
        echo "- **Subscription:** \`${AZSD_SUBSCRIPTION_ID}\`"
        echo "- **Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
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

function write_summary() {
    local failed=("${@}")
    local summary="${AZSD_OUTPUT_DIR}/summary.md"
    local inv
    inv="$(inventory_file)"

    local filter=""
    [ -n "${AZSD_ONLY:-}" ] && filter="--only ${AZSD_ONLY}"
    [ -n "${AZSD_SKIP:-}" ] && filter="${filter:+${filter} }--skip ${AZSD_SKIP}"

    record_full_sweep "${#failed[@]}"

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
        echo
        echo "## Reports"
        echo
    } >"${summary}"

    local report base generated
    while IFS= read -r report; do
        [ -z "${report}" ] && continue
        base="$(basename "${report}" .md)"
        generated="$(sed -n 's/^- \*\*Generated:\*\* //p' "${report}" | head -1)"
        echo "- [${base}](reports/${base}.md)${generated:+ — ${generated}}" >>"${summary}"
    done < <(find "${AZSD_OUTPUT_DIR}/reports" -maxdepth 1 -name '*.md' -type f | sort)

    {
        echo
        echo "## Resource types with no dedicated module"
        echo
        echo "Observed in the inventory but not inspected in depth by any module. Unexplored territory: look here next."
        echo
    } >>"${summary}"

    if [ ! -s "${inv}" ]; then
        echo "_(inventory missing)_" >>"${summary}"
        return 0
    fi

    local covered_file="${AZSD_OUTPUT_DIR}/raw/inventory/covered-types.txt"
    covered_types >"${covered_file}"
    jq --rawfile covered "${covered_file}" --from-file "${AZSD_LIB_DIR}/uncovered-types.jq" "${inv}" |
        render_table "Resource type|Count" >>"${summary}"
}
