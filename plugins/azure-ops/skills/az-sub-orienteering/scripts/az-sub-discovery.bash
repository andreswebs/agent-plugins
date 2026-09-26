#!/usr/bin/env bash
#
# az-sub-discovery - orienteering sweep of one Azure subscription.
#
# Read-only. Runs every discovery module found in lib/*.bash (functions named
# module_NN_<name>), saves raw JSON and a markdown report per module, then an
# index with the resource types no module covered.

set -o errexit
set -o nounset
set -o pipefail

AZSD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly AZSD_SCRIPT_DIR

AZSD_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZSD_OUTPUT_DIR="${AZSD_OUTPUT_DIR:-}"
AZSD_LIB_DIR="${AZSD_LIB_DIR:-${AZSD_SCRIPT_DIR}/lib}"
AZSD_ONLY=""
AZSD_SKIP=""
AZSD_FAIL_FAST="false"
AZSD_ACTION="run"

AZSD_TOTAL_COUNT=0
AZSD_DONE_COUNT=0

function echo_stderr() {
    echo "${*}" >&2
}

function usage() {
    echo_stderr "az-sub-discovery - read-only orienteering sweep of an Azure subscription"
    echo_stderr
    echo_stderr "Usage:"
    echo_stderr "  az-sub-discovery.bash [options]"
    echo_stderr "  az-sub-discovery.bash --list"
    echo_stderr "  az-sub-discovery.bash --help | -h"
    echo_stderr
    echo_stderr "Options:"
    echo_stderr "  --subscription, -s ID"
    echo_stderr "    Subscription to sweep. Default: AZURE_SUBSCRIPTION_ID, else the az CLI default"
    echo_stderr
    echo_stderr "  --output-dir, -o DIR"
    echo_stderr "    Where raw/ and reports/ are written."
    echo_stderr "    Default: AZSD_OUTPUT_DIR, else ./.local/tmp/az-sub-discovery/<subscription-id>"
    echo_stderr
    echo_stderr "  --only MOD[,MOD...]"
    echo_stderr "    Run only these modules (names as printed by --list). inventory is always run"
    echo_stderr
    echo_stderr "  --skip MOD[,MOD...]"
    echo_stderr "    Skip these modules"
    echo_stderr
    echo_stderr "  --fail-fast"
    echo_stderr "    Abort on the first failing module. Default: continue, report failures at the end"
    echo_stderr
    echo_stderr "  --lib-dir DIR"
    echo_stderr "    Module directory. Default: AZSD_LIB_DIR, else lib/ next to this script"
    echo_stderr
    echo_stderr "  --list"
    echo_stderr "    Print the modules that would run, in order, and exit"
    echo_stderr
    echo_stderr "Environment:"
    echo_stderr "  AZSD_AZ_TIMEOUT   seconds allowed per az call (default 120)"
    echo_stderr "  AZSD_LOG_LEVEL    trace|debug|info|warn|error (default info)"
    echo_stderr
}

function parse_arguments() {
    while [ "${#}" -gt 0 ]; do
        local key="${1}"
        case "${key}" in
        --help | -h)
            usage
            exit 0
            ;;
        --list)
            AZSD_ACTION="list"
            shift
            ;;
        --subscription | -s)
            [ "${#}" -ge 2 ] || die_usage "${key} requires a value"
            AZSD_SUBSCRIPTION_ID="${2}"
            shift 2
            ;;
        --output-dir | -o)
            [ "${#}" -ge 2 ] || die_usage "${key} requires a value"
            AZSD_OUTPUT_DIR="${2}"
            shift 2
            ;;
        --only)
            [ "${#}" -ge 2 ] || die_usage "${key} requires a value"
            AZSD_ONLY="${2}"
            shift 2
            ;;
        --skip)
            [ "${#}" -ge 2 ] || die_usage "${key} requires a value"
            AZSD_SKIP="${2}"
            shift 2
            ;;
        --lib-dir)
            [ "${#}" -ge 2 ] || die_usage "${key} requires a value"
            AZSD_LIB_DIR="${2}"
            shift 2
            ;;
        --fail-fast)
            AZSD_FAIL_FAST="true"
            shift
            ;;
        -?*)
            die_usage "invalid option: ${key}"
            ;;
        *)
            die_usage "invalid argument: ${key}"
            ;;
        esac
    done
}

function die_usage() {
    echo_stderr "$(basename "${0}"): ${*}"
    echo_stderr "try --help"
    exit 2
}

function check_dependencies() {
    if ((BASH_VERSINFO[0] < 4)); then
        echo_stderr "bash 4.0 or higher is required (macOS ships 3.2; brew install bash)"
        return 1
    fi

    local missing=()
    local cmd
    for cmd in az jq realpath; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        missing+=("timeout (GNU coreutils)")
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        echo_stderr "missing required commands:"
        local m
        for m in "${missing[@]}"; do
            echo_stderr "  - ${m}"
        done
        return 1
    fi

    if ! realpath --help 2>&1 | grep -q -- --canonicalize-missing; then
        echo_stderr "GNU realpath required (brew install coreutils, put gnubin first on PATH)"
        return 1
    fi
    return 0
}

function load_library() {
    if [ ! -d "${AZSD_LIB_DIR}" ]; then
        echo_stderr "lib dir not found: ${AZSD_LIB_DIR}"
        return 1
    fi

    local files=()
    local f
    while IFS= read -r f; do
        [ -z "${f}" ] && continue
        files+=("${f}")
    done < <(find "${AZSD_LIB_DIR}" -maxdepth 1 -name '*.bash' -type f | sort)

    if [ "${#files[@]}" -eq 0 ]; then
        echo_stderr "no *.bash modules in ${AZSD_LIB_DIR}"
        return 1
    fi

    for f in "${files[@]}"; do
        # shellcheck disable=SC1090
        if ! source "${f}"; then
            echo_stderr "failed to source ${f}"
            return 1
        fi
    done
    return 0
}

# Modules are any function named module_NN_<name>; NN fixes the run order.
function discover_modules() {
    declare -F | awk '{print $3}' | grep -E '^module_[0-9]+_[a-z0-9_]+$' | grep -v -E '_types$' | sort
}

function module_short_name() {
    local fn="${1}"
    fn="${fn#module_}"
    echo "${fn#*_}"
}

function is_in_csv() {
    local needle="${1}"
    local csv="${2}"
    [ -z "${csv}" ] && return 1
    [[ ",${csv}," == *",${needle},"* ]]
}

function select_modules() {
    local fn name
    while IFS= read -r fn; do
        [ -z "${fn}" ] && continue
        name="$(module_short_name "${fn}")"
        if is_in_csv "${name}" "${AZSD_SKIP}"; then
            continue
        fi
        # inventory feeds every other module, so --only never drops it
        if [ -n "${AZSD_ONLY}" ] && [ "${name}" != "inventory" ] && ! is_in_csv "${name}" "${AZSD_ONLY}"; then
            continue
        fi
        echo "${fn}"
    done < <(discover_modules)
}

function resolve_subscription() {
    if [ -z "${AZSD_SUBSCRIPTION_ID}" ]; then
        if ! AZSD_SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null); then
            log_error "no subscription given and 'az account show' failed; run az login or pass --subscription"
            return 1
        fi
    fi
    if ! is_guid "${AZSD_SUBSCRIPTION_ID}"; then
        log_error "subscription id is not a GUID: ${AZSD_SUBSCRIPTION_ID}"
        return 1
    fi
    return 0
}

function resolve_output_dir() {
    local dir="${AZSD_OUTPUT_DIR:-${PWD}/.local/tmp/az-sub-discovery/${AZSD_SUBSCRIPTION_ID}}"
    if ! AZSD_OUTPUT_DIR=$(realpath --canonicalize-missing --quiet "${dir}"); then
        log_error "cannot resolve output dir: ${dir}"
        return 1
    fi
    mkdir -p "${AZSD_OUTPUT_DIR}/raw" "${AZSD_OUTPUT_DIR}/reports"
}

function shutdown() {
    local -r signal="${1}"
    log_warn "received ${signal} after ${AZSD_DONE_COUNT} of ${AZSD_TOTAL_COUNT} modules"
    case "${signal}" in
    SIGINT) exit 130 ;;
    SIGTERM) exit 143 ;;
    *) exit 1 ;;
    esac
}

function run_modules() {
    local modules=()
    local fn
    while IFS= read -r fn; do
        [ -z "${fn}" ] && continue
        modules+=("${fn}")
    done < <(select_modules)

    AZSD_TOTAL_COUNT="${#modules[@]}"
    if [ "${AZSD_TOTAL_COUNT}" -eq 0 ]; then
        log_error "no modules selected"
        return 1
    fi

    local failed=()
    local name
    for fn in "${modules[@]}"; do
        name="$(module_short_name "${fn}")"
        module_setup "${name}"
        log_info "==> ${name}"
        if ! "${fn}"; then
            failed+=("${name}")
            log_error "module ${name} failed"
            if [ "${AZSD_FAIL_FAST}" = "true" ]; then
                break
            fi
            continue
        fi
        AZSD_DONE_COUNT=$((AZSD_DONE_COUNT + 1))
    done

    write_summary "${failed[@]+"${failed[@]}"}"

    log_info "completed ${AZSD_DONE_COUNT} of ${AZSD_TOTAL_COUNT} modules; summary at ${AZSD_OUTPUT_DIR}/summary.md"
    if [ "${#failed[@]}" -gt 0 ]; then
        log_error "failed modules:"
        for name in "${failed[@]}"; do
            log_error "  - ${name}"
        done
        return 1
    fi
    return 0
}

function list_modules() {
    local fn
    while IFS= read -r fn; do
        [ -z "${fn}" ] && continue
        echo "$(module_short_name "${fn}")  (${fn})"
    done < <(select_modules)
}

function main() {
    parse_arguments "${@}"
    check_dependencies || exit 1
    load_library || exit 1

    if [ "${AZSD_ACTION}" = "list" ]; then
        list_modules
        exit 0
    fi

    resolve_subscription || exit 1
    resolve_output_dir || exit 1
    resolve_provenance

    trap 'shutdown SIGINT' SIGINT
    trap 'shutdown SIGTERM' SIGTERM

    log_info "subscription ${AZSD_SUBSCRIPTION_ID}"
    log_info "output ${AZSD_OUTPUT_DIR}"
    run_modules
}

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
