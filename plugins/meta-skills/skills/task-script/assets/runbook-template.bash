#!/usr/bin/env bash
#
# <task-slug>.bash - <the task in one line>
#
# Runbook. Run from the project root. Dry run by default: every step checks
# its end state and reports what it would do. Pass --apply to make changes.
#
#   1. <end state of step 1>                         [reversible]
#   2. <end state of step 2>                         [risky: <what it touches>]
#
# Review: shellcheck this file, run it plainly, then run it with --apply.
# Re-running is safe: finished steps report skip.
#
# <triage line from the /bash skill, absences included>

set -o errexit
set -o nounset
set -o pipefail

readonly ROOT="${PWD}"
readonly REQUIRED_COMMANDS=(git)

APPLY="false"
COUNT_SKIP=0
COUNT_WOULD=0
COUNT_DONE=0

function echo_stderr() {
    echo "${*}" >&2
}

function report() {
    printf '%-5s %s\n' "${1}" "${2}" >&2
}

function usage() {
    echo_stderr "<task-slug>.bash - <the task in one line>"
    echo_stderr
    echo_stderr "Usage:"
    echo_stderr "  <task-slug>.bash [--apply]"
    echo_stderr "  <task-slug>.bash --help | -h"
    echo_stderr
    echo_stderr "Options:"
    echo_stderr "  --apply"
    echo_stderr "    Make the changes. Without it, the runbook is a dry run."
}

function parse_arguments() {
    while [ "${#}" -gt 0 ]; do
        case "${1}" in
        --apply)
            APPLY="true"
            shift
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        -?*)
            echo_stderr "$(basename "${0}"): invalid option: ${1}"
            exit 1
            ;;
        *)
            echo_stderr "$(basename "${0}"): invalid argument: ${1}"
            exit 1
            ;;
        esac
    done
}

# Facts the agent could only learn from a shell are checked here, all of them
# before failing, so the user fixes everything in one pass.
function preflight() {
    local problems=()
    local cmd
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        command -v "${cmd}" >/dev/null 2>&1 || problems+=("missing command: ${cmd}")
    done
    [ -e "${ROOT}/<project marker>" ] || problems+=("run from the project root")
    [ -n "${EXAMPLE_TOKEN:-}" ] || problems+=("set EXAMPLE_TOKEN in the environment")
    if [ "${#problems[@]}" -gt 0 ]; then
        printf 'preflight: %s\n' "${problems[@]}" >&2
        return 1
    fi
}

function file_matches() {
    local -r path="${1}" producer="${2}"
    [ -f "${path}" ] && [ "$("${producer}")" = "$(cat "${path}")" ]
}

function write_from() {
    local -r path="${1}" producer="${2}"
    mkdir -p "$(dirname "${path}")" || return 1
    "${producer}" >"${path}" || return 1
}

# Check, then act. The check is a predicate that prints nothing. The act is
# called from a condition, where errexit does not fire, so every fallible call
# inside it carries its own `|| return 1`.
function run_step() {
    local -r label="${1}" check="${2}" act="${3}"
    if "${check}"; then
        COUNT_SKIP=$((COUNT_SKIP + 1))
        report "skip" "${label}"
        return 0
    fi
    if [ "${APPLY}" != "true" ]; then
        COUNT_WOULD=$((COUNT_WOULD + 1))
        report "would" "${label}"
        return 0
    fi
    if ! "${act}"; then
        report "FAIL" "${label}"
        return 1
    fi
    if ! "${check}"; then
        report "FAIL" "${label} (end state not reached)"
        return 1
    fi
    COUNT_DONE=$((COUNT_DONE + 1))
    report "done" "${label}"
}

# Step 1: <end state>. Reversible.
function step_1_check() {
    [ -d "${ROOT}/<dir>" ]
}

function step_1_act() {
    mkdir -p "${ROOT}/<dir>" || return 1
}

# Step 2: <file> holds the content below. Reversible.
function step_2_content() {
    cat <<'CONTENT'
<file content, verbatim>
CONTENT
}

function step_2_check() {
    file_matches "${ROOT}/<dir>/<file>" step_2_content
}

function step_2_act() {
    write_from "${ROOT}/<dir>/<file>" step_2_content
}

function run_steps() {
    run_step "1. <end state of step 1>" step_1_check step_1_act || return 1
    run_step "2. <end state of step 2>" step_2_check step_2_act || return 1
}

function main() {
    parse_arguments "${@}"
    preflight
    local status=0
    run_steps || status=1
    echo_stderr
    echo_stderr "skip ${COUNT_SKIP}, would ${COUNT_WOULD}, done ${COUNT_DONE}"
    if [ "${status}" -ne 0 ]; then
        echo_stderr "stopped at the FAIL above; fix the runbook and re-run"
    elif [ "${APPLY}" != "true" ] && [ "${COUNT_WOULD}" -gt 0 ]; then
        echo_stderr "dry run: re-run with --apply to make these changes"
    fi
    return "${status}"
}

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
