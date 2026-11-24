# Leveled Logging

**Trigger:** the script has more than a handful of functions, or runs long enough that an operator will tail it. Below that, the Floor's `echo_stderr` is the whole requirement.

Copy this family into the project's library. It writes every line to stderr, filters by severity taken from the environment, and stamps each line with a timestamp, the script name, and the function that logged it.

Replace the `MYTOOL_` prefix with the project's own.

```bash
function echo_stderr() {
    echo "${*}" >&2
}

function log_level_to_num() {
    local -r level="${1}"
    # See: https://opentelemetry.io/docs/specs/otel/logs/data-model/#field-severitynumber
    case "${level}" in
    "trace") echo 1 ;;
    "debug") echo 5 ;;
    "info") echo 9 ;;
    "warn") echo 13 ;;
    "error") echo 17 ;;
    "fatal") echo 21 ;;
    *) echo 9 ;; # unknown -> info
    esac
}

function log() {
    local OTEL_LOG_LEVEL="${OTEL_LOG_LEVEL:-info}"
    local MYTOOL_LOG_LEVEL="${MYTOOL_LOG_LEVEL:-${OTEL_LOG_LEVEL}}"
    MYTOOL_LOG_LEVEL=$(printf '%s' "${MYTOOL_LOG_LEVEL}" | tr '[:upper:]' '[:lower:]')

    local -r LOG_SEVERITY_NUMBER=$(log_level_to_num "${MYTOOL_LOG_LEVEL}")

    local -r level="${1}"
    local -r message="${2}"
    local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local -r script_loc="${0##*/}"
    local -r function="${FUNCNAME[2]}"

    local l
    l=$(printf '%s' "${level}" | tr '[:upper:]' '[:lower:]')
    local s_num
    s_num=$(log_level_to_num "${l}")

    if ((s_num >= LOG_SEVERITY_NUMBER)); then
        echo_stderr "[${timestamp}] [${l}] [${script_loc}] [${function}] ${message}"
    fi
}

function log_trace() {
    local -r message="${1:-}"
    log "TRACE" "${message}"
}

function log_debug() {
    local -r message="${1:-}"
    log "DEBUG" "${message}"
}

function log_info() {
    local -r message="${1:-}"
    log "INFO" "${message}"
}

function log_warn() {
    local -r message="${1:-}"
    log "WARN" "${message}"
}

function log_error() {
    local -r message="${1:-}"
    log "ERROR" "${message}"
}

function log_fatal() {
    local -r message="${1:-}"
    log "FATAL" "${message}"
}
```

## Notes

`FUNCNAME[2]` is the caller of `log_info` and friends, not the wrapper itself: index 0 is `log`, index 1 is the `log_<level>` wrapper, and index 2 is the code that actually wanted to log. Adding or removing a wrapper layer shifts this index.

Severity numbers come from the OpenTelemetry log data model, so levels compare numerically rather than by string, and an unknown level degrades to `info` instead of silencing output.

Reading `OTEL_LOG_LEVEL` as the fallback lets a script inherit whatever level the surrounding tooling already set, with the project-specific variable taking precedence.

`log_fatal` reports; it does not exit. The caller decides whether a fatal condition returns non-zero or terminates the process, which keeps the family usable from a sourced library.

Only stderr is written, so a function's stdout stays clean for its return value even at trace level.
