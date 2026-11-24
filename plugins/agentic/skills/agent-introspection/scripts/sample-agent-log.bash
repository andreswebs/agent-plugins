#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly UINT32_BOUND=4294967296
readonly DEFAULT_COUNT=10
readonly RANDOM_SOURCE="/dev/urandom"

function echo_stderr() {
    echo "${*}" >&2
}

function usage() {
    cat <<'EOF'
Usage: sample-agent-log.bash (--file PATH | --dir PATH) [--count N] [--min-size BYTES]

Draws a uniform random sample of records from a Claude Code JSONL session
transcript, using the operating system randomness source rather than ${RANDOM}.

  --file PATH       sample this transcript
  --dir PATH        pick one transcript at random from this directory, then sample it
  --count N         records to draw (default 10)
  --min-size BYTES  with --dir, only consider transcripts at least this large
  --help            print this message

Sampled records are written to stdout as JSONL. The provenance of the draw
(file, size, record count, chosen indices) is written to stderr.
EOF
}

function is_cmd_available() {
    command -v "${1}" >/dev/null 2>&1
}

function preflight() {
    local -a missing=()

    is_cmd_available od || missing+=("od")
    is_cmd_available realpath || missing+=("realpath")
    is_cmd_available awk || missing+=("awk")

    if ((${#missing[@]} > 0)); then
        echo_stderr "missing required commands: ${missing[*]}"
        return 1
    fi

    # long flags below are GNU-only; BSD od accepts neither --read-bytes nor --format
    if ! od --read-bytes=1 --format=u1 </dev/null >/dev/null 2>&1; then
        echo_stderr "od does not accept GNU long flags; install coreutils and put it first on PATH"
        return 1
    fi

    if [ ! -r "${RANDOM_SOURCE}" ]; then
        echo_stderr "randomness source ${RANDOM_SOURCE} is not readable"
        return 1
    fi
}

function random_uint32() {
    local value
    value=$(od --address-radix=n --read-bytes=4 --format=u4 "${RANDOM_SOURCE}") || return 1
    value="${value//[[:space:]]/}"
    [ -n "${value}" ] || return 1
    echo "${value}"
}

# Rejection sampling: a bare modulo of a uint32 biases the low residues
# whenever bound does not divide 2^32, which is every realistic bound here.
function random_below() {
    local -r bound="${1}"
    local -r limit=$((UINT32_BOUND - (UINT32_BOUND % bound)))
    local draw

    while true; do
        draw=$(random_uint32) || return 1
        if ((draw < limit)); then
            echo $((draw % bound))
            return 0
        fi
    done
}

function resolve_readable_file() {
    local resolved
    resolved=$(realpath --quiet "${1}" 2>/dev/null) || return 1
    [ -f "${resolved}" ] && [ -r "${resolved}" ] || return 1
    echo "${resolved}"
}

function pick_random_transcript() {
    local -r dir="${1}"
    local -r min_size="${2}"
    local -a candidates=()
    local path index

    while IFS= read -r path; do
        [ -z "${path}" ] && continue
        candidates+=("${path}")
    done < <(find "${dir}" -maxdepth 1 -type f -name '*.jsonl' -size +"${min_size}"c -print 2>/dev/null | sort)

    if ((${#candidates[@]} == 0)); then
        echo_stderr "no .jsonl transcripts of at least ${min_size} bytes in ${dir}"
        return 1
    fi

    index=$(random_below "${#candidates[@]}") || return 1
    echo_stderr "picked 1 of ${#candidates[@]} candidate transcripts"
    echo "${candidates[${index}]}"
}

function draw_distinct_indices() {
    local -r total="${1}"
    local -r count="${2}"
    local -a chosen=()
    local -A seen=()
    local index

    if ((count >= total)); then
        seq 1 "${total}"
        return 0
    fi

    while ((${#chosen[@]} < count)); do
        index=$(random_below "${total}") || return 1
        index=$((index + 1))
        if [ -z "${seen[${index}]:-}" ]; then
            seen["${index}"]=1
            chosen+=("${index}")
        fi
    done

    printf '%s\n' "${chosen[@]}" | sort --numeric-sort
}

function emit_records() {
    local -r file="${1}"
    local -r indices="${2}"

    awk -v wanted="${indices}" '
        BEGIN {
            n = split(wanted, list, "\n")
            for (i = 1; i <= n; i++) {
                if (list[i] != "") {
                    keep[list[i] + 0] = 1
                }
            }
        }
        keep[NR]
    ' "${file}"
}

function main() {
    local file="" dir="" count="${DEFAULT_COUNT}" min_size=0
    local target total indices

    while (("${#}" > 0)); do
        case "${1}" in
        --file)
            file="${2:-}"
            shift 2
            ;;
        --dir)
            dir="${2:-}"
            shift 2
            ;;
        --count)
            count="${2:-}"
            shift 2
            ;;
        --min-size)
            min_size="${2:-}"
            shift 2
            ;;
        --help)
            usage
            return 0
            ;;
        *)
            echo_stderr "unrecognised option: ${1}"
            usage >&2
            return 2
            ;;
        esac
    done

    preflight || return 1

    if [ -n "${file}" ] && [ -n "${dir}" ]; then
        echo_stderr "--file and --dir are mutually exclusive"
        return 2
    fi

    if [ -z "${file}" ] && [ -z "${dir}" ]; then
        echo_stderr "one of --file or --dir is required"
        usage >&2
        return 2
    fi

    if ! [[ "${count}" =~ ^[0-9]+$ ]] || ((count == 0)); then
        echo_stderr "--count must be a positive integer, got: ${count}"
        return 2
    fi

    if ! [[ "${min_size}" =~ ^[0-9]+$ ]]; then
        echo_stderr "--min-size must be a non-negative integer, got: ${min_size}"
        return 2
    fi

    if [ -n "${dir}" ]; then
        if [ ! -d "${dir}" ]; then
            echo_stderr "not a directory: ${dir}"
            return 1
        fi
        target=$(pick_random_transcript "${dir}" "${min_size}") || return 1
    else
        if ! target=$(resolve_readable_file "${file}"); then
            echo_stderr "not a readable file: ${file}"
            return 1
        fi
    fi

    total=$(wc -l <"${target}") || return 1
    total="${total//[[:space:]]/}"

    if ((total == 0)); then
        echo_stderr "transcript has no records: ${target}"
        return 1
    fi

    indices=$(draw_distinct_indices "${total}" "${count}") || return 1

    echo_stderr "transcript: ${target}"
    echo_stderr "bytes: $(wc -c <"${target}" | tr -d '[:space:]')  records: ${total}"
    echo_stderr "randomness: ${RANDOM_SOURCE} (rejection-sampled uint32)"
    echo_stderr "indices: $(echo "${indices}" | tr '\n' ' ')"

    emit_records "${target}" "${indices}"
}

main "${@}"
