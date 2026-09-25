#!/usr/bin/env bash
# Static checks for the marketplace: the catalog agrees with plugins/, each
# plugin's two manifests agree, the portable files validate against the Agent
# Plugins schemas, and `claude plugin validate` passes when Claude Code is
# installed. Read-only.

set -o errexit
set -o nounset
set -o pipefail

readonly PLUGIN_SCHEMA_URL="https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
readonly MCP_SCHEMA_URL="https://agent-plugins.org/schemas/1.0.0/mcp.schema.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
CATALOG="${REPO_ROOT}/.claude-plugin/marketplace.json"

FAILURES=()

function echo_stderr() {
    echo "${*}" >&2
}

function fail() {
    FAILURES+=("${*}")
    echo_stderr "  FAIL ${*}"
}

function is_cmd_available() {
    command -v "${1}" >/dev/null 2>&1
}

function check_dependencies() {
    local missing=()
    local cmd
    for cmd in jq uv; do
        is_cmd_available "${cmd}" || missing+=("${cmd}")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo_stderr "missing required commands: ${missing[*]}"
        return 1
    fi
}

function catalog_entries() {
    jq --raw-output \
        '.plugins[] | [.name, (if (.source | type) == "string" then .source else "" end)] | @tsv' \
        "${CATALOG}"
}

# Relative paths from the repository root, so a claude that runs in a container
# with the working directory mounted resolves them too.
function claude_validate() {
    (cd "${REPO_ROOT}" && claude plugin validate "${@}") >&2
}

function manifest_field() {
    local -r file="${1}" field="${2}"
    jq --raw-output --arg field "${field}" '.[$field] // ""' "${file}"
}

function check_catalog() {
    echo_stderr "catalog against plugins/"
    local entries
    if ! entries=$(catalog_entries); then
        fail "${CATALOG}: cannot read plugin entries"
        return 0
    fi

    local name source dir
    while IFS=$'\t' read -r name source; do
        [ -z "${name}" ] && continue
        if [ -z "${source}" ]; then
            echo_stderr "  skip ${name}: remote source, not in this repository"
            continue
        fi
        if [[ "${source}" != ./* ]]; then
            fail "${name}: source '${source}' does not start with ./"
            continue
        fi
        dir="${REPO_ROOT}/${source#./}"
        if [ ! -d "${dir}" ]; then
            fail "${name}: source directory ${source} does not exist"
        elif [ ! -f "${dir}/plugin.json" ]; then
            fail "${name}: ${source} has no portable plugin.json"
        fi
    done <<<"${entries}"

    local plugin_dir base
    for plugin_dir in "${REPO_ROOT}"/plugins/*/; do
        [ -d "${plugin_dir}" ] || continue
        base="$(basename "${plugin_dir}")"
        if ! jq --exit-status --arg src "./plugins/${base}" \
            'any(.plugins[]; .source == $src)' "${CATALOG}" >/dev/null; then
            fail "plugins/${base}: no catalog entry with source ./plugins/${base}"
        fi
    done
}

function check_plugin() {
    local -r entry_name="${1}" dir="${2}"
    local -r portable="${dir}/plugin.json" claude="${dir}/.claude-plugin/plugin.json"
    local rel="${dir#"${REPO_ROOT}/"}"
    local before="${#FAILURES[@]}"

    local p_name p_version
    if ! p_name=$(manifest_field "${portable}" name) ||
        ! p_version=$(manifest_field "${portable}" version); then
        fail "${rel}/plugin.json: not valid JSON"
        return 1
    fi
    [ "${p_name}" = "${entry_name}" ] ||
        fail "${rel}: portable name '${p_name}' differs from catalog entry '${entry_name}'"

    if [ -f "${claude}" ]; then
        local c_name c_version
        if ! c_name=$(manifest_field "${claude}" name) ||
            ! c_version=$(manifest_field "${claude}" version); then
            fail "${rel}/.claude-plugin/plugin.json: not valid JSON"
        else
            [ "${c_name}" = "${p_name}" ] ||
                fail "${rel}: name '${c_name}' in .claude-plugin/plugin.json differs from '${p_name}'"
            [ "${c_version}" = "${p_version}" ] ||
                fail "${rel}: version '${c_version}' in .claude-plugin/plugin.json differs from '${p_version}'"
        fi
    elif [ -f "${dir}/mcp.json" ]; then
        fail "${rel}: has mcp.json but no .claude-plugin/plugin.json to redirect Claude Code to it"
    fi

    uvx --quiet check-jsonschema --schemafile "${PLUGIN_SCHEMA_URL}" "${portable}" >&2 ||
        fail "${rel}/plugin.json: does not match the Agent Plugins plugin schema"
    if [ -f "${dir}/mcp.json" ]; then
        uvx --quiet check-jsonschema --schemafile "${MCP_SCHEMA_URL}" "${dir}/mcp.json" >&2 ||
            fail "${rel}/mcp.json: does not match the Agent Plugins MCP schema"
    fi

    if is_cmd_available claude; then
        claude_validate --strict "./${rel}" ||
            fail "${rel}: claude plugin validate --strict"
        if [ -d "${dir}/skills" ]; then
            claude_validate "./${rel}/skills" ||
                fail "${rel}/skills: claude plugin validate"
        fi
    fi

    [ "${#FAILURES[@]}" -eq "${before}" ]
}

function check_plugins() {
    local entries
    entries=$(catalog_entries) || return 0

    local total_count=0 passed_count=0
    local name source dir
    while IFS=$'\t' read -r name source; do
        [[ -z "${name}" || "${source}" != ./* ]] && continue
        dir="${REPO_ROOT}/${source#./}"
        [ -f "${dir}/plugin.json" ] || continue
        total_count=$((total_count + 1))
        echo_stderr "plugin ${name}"
        if check_plugin "${name}" "${dir}"; then
            passed_count=$((passed_count + 1))
        fi
    done <<<"${entries}"

    echo_stderr "plugins passed: ${passed_count} of ${total_count}"
}

function check_marketplace() {
    if ! is_cmd_available claude; then
        echo_stderr "warning: claude not on PATH, skipping claude plugin validate"
        return 0
    fi
    echo_stderr "marketplace"
    claude_validate --strict ./ ||
        fail "marketplace: claude plugin validate --strict"
}

function main() {
    check_dependencies || exit 1
    if ! jq --exit-status 'type == "object"' "${CATALOG}" >/dev/null 2>&1; then
        echo_stderr "cannot read ${CATALOG} as a JSON object"
        exit 1
    fi

    check_catalog
    check_marketplace
    check_plugins

    if [ "${#FAILURES[@]}" -gt 0 ]; then
        echo_stderr
        echo_stderr "${#FAILURES[@]} failure(s):"
        local failure
        for failure in "${FAILURES[@]}"; do
            echo_stderr "  ${failure}"
        done
        exit 1
    fi
    echo_stderr "all checks passed"
}

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
