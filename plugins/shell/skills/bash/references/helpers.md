# Floor Helpers

Reusable predicates and text handling. These support the Floor rather than a tag: any script may need them, none is obliged to. Replace the `MYTOOL_` prefix with the project's own where one appears.

## Predicates

Each returns 0 or non-zero and prints nothing, so it composes into an `if !` guard.

```bash
function is_cmd_available() {
    local cmd="${1}"
    command -v "${cmd}" &>/dev/null
}

function is_readable_file() {
    local file_path="${1}"

    local resolved_path
    if ! resolved_path=$(realpath --quiet "${file_path}" 2>/dev/null); then
        return 1
    fi
    [ -f "${resolved_path}" ] && [ -r "${resolved_path}" ]
}

function is_non_empty_dir() {
    [ -d "${1}" ] && [ -r "${1}" ] && [ -n "$(ls -A "${1}" 2>/dev/null)" ]
}

function is_valid_json() {
    local input="${1}"

    if [ -z "${input}" ]; then
        return 1
    fi

    # JSON has no NaN or Infinity; jq accepts them, so reject explicitly
    if echo "${input}" | grep --quiet '\bNaN\b\|\bInfinity\b\|\b-Infinity\b'; then
        return 1
    fi

    if ! echo "${input}" | jq empty >/dev/null 2>&1; then
        return 1
    fi

    # a stream of several values parses fine but is not one document
    local value_count
    if ! value_count=$(echo "${input}" | jq --slurp '. | length' 2>/dev/null); then
        return 1
    fi

    [ "${value_count}" = "1" ]
}

function is_json_object() {
    local input="${1}"

    if [ -z "${input}" ]; then
        return 1
    fi

    echo "${input}" | jq --exit-status 'type == "object"' >/dev/null 2>&1
}
```

`is_readable_file` resolves before testing, which is what makes it safe against input that looks like shell or glob syntax: `realpath` either produces a real path or fails, and a quoted result is never re-parsed. It also collapses `..` traversal and follows symlinks, so a broken symlink and a directory both fail as they should.

`is_readable_file` uses `realpath --quiet`, and the JSON predicates use `grep --quiet`. Both are GNU long flags, so a script adopting them fires `preflight`.

## Text Handling Without Subprocesses

Trimming with parameter expansion, no `sed` or `tr` process:

```bash
# shellcheck disable=SC2120
function text_trim() {
    local input

    if [ "${#}" -gt 0 ]; then
        input="${*}"
    else
        input=$(cat)
    fi

    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"

    printf '%s' "${input}"
}
```

Other expansions that replace a subprocess: `${var,,}` and `${var^^}` for case folding, `${var#prefix}` and `${var%suffix}` for stripping, `${var//find/replace}` for substitution, `${#var}` for length, and `${0##*/}` for the basename.

`printf '%s'` rather than `echo` avoids `echo` interpreting a leading `-` as a flag or expanding escapes in the value.
