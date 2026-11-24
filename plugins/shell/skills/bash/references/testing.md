# Testing and Project Checks

**Trigger:** the file is sourced by other code, or holds logic worth isolating from its side effects.

A test exists to produce evidence the script behaves as claimed on the paths that matter, above all the failure paths. Reading the code is not evidence.

BATS is the mechanism for a sourced library, and for any script holding logic worth isolating. Everything else is verified by invoking it: record the exit status and stderr for each failure path, at minimum unknown option, missing required argument, unreadable or absent input, the external command failing, and interrupt mid-run.

Record that status without a pipe, or read `"${PIPESTATUS[0]}"`. `./script --bad 2>&1 | tail -2; echo "${?}"` reports `tail`'s status, which is almost always `0`, and a passing check that proves nothing is worse than no check.

For a thin wrapper over an external CLI such as `az` or `kubectl`, do not mock that CLI to manufacture a suite: you would be testing the mock. If logic inside the wrapper becomes worth testing on its own, extract it into a sourced library and use BATS on that.

Give every function failure cases alongside its success cases: missing arguments, empty strings, unreadable or absent files, wrong types, broken symlinks, and adversarial input such as paths containing `$(...)`, backticks, `;`, `|`, or glob characters.

## Layout

```text
mytool-core.bash
mytool.bash
test/
├── bats/                       # bats-core, as a git submodule
├── bats-helpers/               # bats-support, bats-assert, bats-file
├── fixtures/                   # test data and configs
├── helpers/                    # scripts the tests invoke
├── <function_name>.test.bats   # one file per function under test
├── cli.test.bats               # the CLI as a user drives it
├── e2e.test.bats               # the whole thing against a real client
├── test.bash
├── shfmt.bash
└── shellcheck.bash
```

One test file per function keeps failures addressable and lets a single function's tests run alone. Helpers are git submodules so the test suite is reproducible without a package manager.

## Unit Tests

`load` the library to get its functions directly, then the assertion helpers:

```bash
#!/usr/bin/env bats

load '../mytool-core.bash'

load 'bats-helpers/bats-support/load'
load 'bats-helpers/bats-assert/load'

@test "is_readable_file: readable existing file" {
    local test_file="${BATS_TEST_TMPDIR}/readable_test_file.txt"
    echo "test content" >"${test_file}"

    run is_readable_file "${test_file}"
    assert_success
}

@test "is_readable_file: broken symlink" {
    local non_existent_target="${BATS_TEST_TMPDIR}/non_existent_target.txt"
    local symlink_file="${BATS_TEST_TMPDIR}/broken_symlink.txt"

    ln -s "${non_existent_target}" "${symlink_file}"

    run is_readable_file "${symlink_file}"
    assert_failure
}
```

`load` of the library only works because the library is safe to source: it has a source guard and sets no strict mode. A library that runs work at load time cannot be unit tested this way.

`run` captures status and output instead of letting a non-zero exit abort the test, which is what makes `assert_failure` possible.

Use the temporary directories BATS provides when manipulating the filesystem, never a hardcoded temp path: `BATS_TEST_TMPDIR` is unique per test, `BATS_FILE_TMPDIR` is shared across a file, and `BATS_SUITE_TMPDIR` is shared across the suite. All are torn down automatically.

## Adversarial Cases

Every function that takes a path, a name, or JSON gets a case per failure mode, driven from a table:

```bash
@test "is_readable_file: rejects paths with unsafe characters" {
    # shellcheck disable=SC2016
    local unsafe_paths=(
        '$(rm -rf /tmp/root-was-wiped)'
        '`touch /tmp/hacked`'
        '|cat /tmp/fixture'
        ';echo dangerous'
        '&&echo injected'
        '||echo fallback'
        '*dangerous*'
        '?unsafe?'
        '[injection]'
        '{expansion}'
    )

    for unsafe_path in "${unsafe_paths[@]}"; do
        run is_readable_file "${unsafe_path}"
        assert_failure
    done
}
```

These pass because the function quotes and resolves rather than sanitises. The test documents that guarantee, so a later refactor that reintroduces an unquoted expansion fails here.

`# shellcheck disable=SC2016` is correct on a single-quoted string that is deliberately not expanding, and belongs on that line only.

## Testing a CLI

Define a wrapper in `setup_file` and export it, so every test invokes the binary the same way with the same environment:

```bash
setup_file() {
    # shellcheck disable=SC2329
    function mytool() {
        MYTOOL_CORE_LIB_FILE="${BATS_TEST_DIRNAME}/../mytool-core.bash" \
            "${BATS_TEST_DIRNAME}/../mytool.bash" "${@}"
    }

    export -f mytool

    export MYTOOL_LOG_LEVEL="debug"
}
```

`export -f` is required: `run` executes in a subshell, which inherits exported functions only. `# shellcheck disable=SC2329` documents that the function is used, just not from a call site shellcheck can see.

`BATS_TEST_DIRNAME` locates the repo relative to the test file, so the suite runs from any working directory.

## Per-Test Setup

When only some tests need fixture state, branch on the description rather than paying for the setup everywhere:

```bash
setup() {
    if [[ "${BATS_TEST_DESCRIPTION}" == "cli: mytool --version" ]]; then
        MYTOOL_DATA_HOME="${BATS_TEST_TMPDIR}/mytool-test-data"
        mkdir -p "${MYTOOL_DATA_HOME}"
        echo '{"Version":"test_version"}' >"${MYTOOL_DATA_HOME}/version.json"
        export MYTOOL_DATA_HOME
    fi
}
```

This works because every path is resolved through an environment variable: the test redirects the tool at a temporary directory instead of touching the real config, and `BATS_TEST_TMPDIR` is torn down automatically.

## Assertions

```bash
assert_success                      # exit status 0
assert_failure                      # any non-zero status
assert_failure 2                    # a specific status
assert_output --partial 'expected'  # substring of combined output
assert_output 'exact'               # whole output
refute_output --partial 'secret'
assert_file_exists "${path}"        # bats-file
```

Prefer `--partial` for anything containing a timestamp, path, or version, so the test asserts behaviour rather than pinning incidental formatting.

## End-to-End Tests

Drive the tool through a real client rather than asserting on hand-written protocol output:

```bash
setup_file() {
    # shellcheck disable=SC2329
    function call_tool() {
        "${BATS_TEST_DIRNAME}/helpers/call-tool.bash" "${@}"
    }
    export -f call_tool
}

@test "call tool: smoketest" {
    run call_tool mytool:smoketest
    assert_success
    assert_output --partial '"text": "ok"'
}
```

Generate unpredictable values so an assertion cannot pass on stale state:

```bash
TOKEN=$(head -c 32 /dev/urandom | base64)
run call_tool mytool:echo_token --args '{"token":"'"${TOKEN}"'"}'
assert_output --partial '"token": "'"${TOKEN}"'"'
```

## Check Scripts

One entry point that runs everything, in the order that fails cheapest first:

```bash
#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

function echo_stderr() {
    echo "${*}" >&2
}

function step() {
    echo_stderr ""
    echo_stderr "==> ${1}"
}

step "shfmt (format check)"
"${REPO_ROOT}/test/shfmt.bash"

step "shellcheck (lint)"
"${REPO_ROOT}/test/shellcheck.bash"

step "bats (tests)"
"${REPO_ROOT}/test/test.bash"

echo_stderr ""
echo_stderr "All checks passed."
```

The formatter runs in check mode by default and writes only when asked, so the same script serves CI and local fixing:

```bash
#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

WRITE="${WRITE:-false}"

if ! command -v "shfmt" &>/dev/null; then
    echo "shfmt not installed" >&2
    exit 1
fi

check_list=(
    "${SCRIPT_DIR}"/../*.bash
    "${SCRIPT_DIR}"/*.bash
    "${SCRIPT_DIR}"/*.bats
    "${SCRIPT_DIR}"/helpers/*.bash
)

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    if [ "${WRITE}" != "true" ]; then
        shfmt --indent 4 --diff "${check_list[@]}"
    else
        shfmt --indent 4 --write "${check_list[@]}"
    fi
fi
```

Run with `WRITE=true ./test/shfmt.bash` to fix in place.

The linter discovers files rather than listing them, and excludes vendored code so a submodule's style is not the project's problem:

```bash
find "${SCRIPT_DIR}/.." -type f -name '*.bash' ! -path '*/bats*/*' -print0 |
    xargs --null shellcheck
```

`-print0` with `xargs --null` is what makes this safe for paths containing spaces.

Each check script guards on `command -v` before running, so a missing tool reports itself instead of failing as a command-not-found deep in a pipeline.
