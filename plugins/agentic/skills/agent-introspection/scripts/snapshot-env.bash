#!/usr/bin/env bash
# Read-only probe of a live Hermes environment. Prints facts, changes nothing.
# Every probe is guarded: a missing tool or path prints "-" and the run
# continues, so the same script works on any install.

set -o errexit
set -o nounset
set -o pipefail

HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
readonly HERMES_HOME

readonly TOOLS=(
    apt-get dpkg nix nix-env brew gh git python3 uv pip pipx
    rg fd jq sqlite3 curl wget docker ffmpeg node npm bun go yt-dlp
    markdownlint-cli2 shellcheck
)

function echo_stderr() {
    echo "${*}" >&2
}

function section() {
    printf '\n===== %s =====\n' "${*}"
}

function run() {
    # a probe with no answer is data, not an error: never abort the snapshot
    "${@}" 2>/dev/null || echo "-"
}

function is_cmd_available() {
    command -v "${1}" >/dev/null 2>&1
}

function probe_paths() {
    section "Paths and identity"
    printf 'date          %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'HERMES_HOME   %s\n' "${HERMES_HOME}"
    printf 'HOME          %s\n' "${HOME:-"-"}"
    printf 'user          %s\n' "$(run id)"
    printf 'cwd           %s\n' "${PWD}"
    printf 'HERMES_PYTHON %s\n' "${HERMES_PYTHON:-"-"}"
    printf 'HERMES_NODE   %s\n' "${HERMES_NODE:-"-"}"
    printf 'PATH python3  %s\n' "$(run command -v python3)"
    env | grep -E '^HERMES_' | sort || echo "-"
}

function probe_system() {
    section "System"
    # userspace distro, not the kernel: they routinely disagree on a Nix host
    run cat /etc/os-release
    printf 'kernel        %s %s\n' "$(run uname -r)" "$(run uname -m)"
    printf 'cores         %s\n' "$(run nproc)"
    run free -h
    run df -h / "${HOME}"
}

function probe_version() {
    section "Hermes build"
    printf 'HERMES_REVISION    %s\n' "${HERMES_REVISION:-"-"}"
    printf 'hermes --version   %s\n' "$(run hermes --version)"
    if [ -n "${HERMES_PYTHON:-}" ]; then
        printf 'runtime modules:\n'
        "${HERMES_PYTHON}" -c '
import importlib
for name in ("agent.prompt_builder", "agent.skill_utils", "cron.scheduler",
             "gateway.platforms.telegram"):
    try:
        print("  %-28s %s" % (name, importlib.import_module(name).__file__))
    except Exception as exc:
        print("  %-28s - (%s)" % (name, exc))
' 2>/dev/null || echo "  -"
    fi
}

function probe_tools() {
    section "Tooling"
    local tool
    for tool in "${TOOLS[@]}"; do
        printf '%-18s %s\n' "${tool}" "$(run command -v "${tool}")"
    done
}

function probe_state() {
    section "Databases and state"
    run du -h "${HERMES_HOME}"/*.db "${HERMES_HOME}"/cron/*.db
    section "Config keys (values omitted)"
    run grep -E '^[A-Za-z_][A-Za-z0-9_]*:' "${HERMES_HOME}/config.yaml"
    section "Secret names in .env (values never printed)"
    run grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "${HERMES_HOME}/.env"
}

function probe_library() {
    section "Skills (local)"
    run find "${HERMES_HOME}/skills" -name SKILL.md |
        sed -e "s|^${HERMES_HOME}/skills/||" -e "s|/SKILL.md\$||" | sort
    section "Plugins (local)"
    run ls -l "${HERMES_HOME}/plugins"
    section "Bundled (read-only)"
    printf 'skills:  %s\n' "${HERMES_BUNDLED_SKILLS:-"-"}"
    run ls "${HERMES_BUNDLED_SKILLS:-/nonexistent}"
    printf 'plugins: %s\n' "${HERMES_BUNDLED_PLUGINS:-"-"}"
    run ls "${HERMES_BUNDLED_PLUGINS:-/nonexistent}"
    section "Cron jobs"
    if is_cmd_available jq; then
        run jq -r '.jobs[] | "\(.id)  \(.name)  \(.schedule.expr)  [\(.last_status)]"' \
            "${HERMES_HOME}/cron/jobs.json"
    else
        run cat "${HERMES_HOME}/cron/jobs.json"
    fi
}

function probe_git() {
    section "Identity repo boundary"
    run git -C "${HERMES_HOME}" status -sb
    run git -C "${HERMES_HOME}" log --oneline -5
    run cat "${HERMES_HOME}/.gitignore"
}

function main() {
    if [ ! -d "${HERMES_HOME}" ]; then
        echo_stderr "HERMES_HOME does not exist: ${HERMES_HOME}"
        return 1
    fi
    probe_paths
    probe_system
    probe_version
    probe_tools
    probe_state
    probe_library
    probe_git
}

main "${@}"
