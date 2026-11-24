---
name: bash
description: >
  Conventions and defensive patterns for writing, reviewing, and modifying
  Bash scripts, shell libraries, and BATS tests. Defines a short floor every
  script owes, then a triage gate that names which further features the
  script has actually earned: error handling, quoting, portability, path and
  JSON safety, logging, signal handling, CLI structure, and testing. Use when
  authoring or changing a shell script, shell function, or BATS test file,
  even if the user doesn't explicitly mention "conventions" or "style guide".
compatibility: >
  Requires shellcheck and shfmt, plus bats-core for tests. Patterns assume
  GNU coreutils, with documented preflight probes for BSD and macOS.
---

# Bash Scripting

Most scripts need the Floor and nothing else. Everything beyond it is gated: each feature has exactly one trigger, and a feature whose trigger has not fired is a defect, not a nicety.

Work in this order: triage, then write to the Floor, then load only the references whose tags fired.

## Triage

Every script owes the Floor and nothing more by default. Walk this column before writing and name the tags that fire. Each trigger is an observable fact about what the script does, not a judgement about how important it is.

| If the script...                                            | Tag           | Pattern                            |
| ----------------------------------------------------------- | ------------- | ---------------------------------- |
| takes options                                               | `cli`         | `references/cli.md`                |
| mutates state outside its own output                        | `dry-run`     | `references/cli.md`                |
| loops over a work list                                      | `partial-run` | `references/cli.md`                |
| creates a temp file                                         | `cleanup`     | `references/signals.md`            |
| can be interrupted mid-run                                  | `signals`     | `references/signals.md`            |
| uses a GNU long flag                                        | `preflight`   | `references/portability.md`        |
| builds a jq, awk, sed or sql program from a shell value      | `json`        | `references/json.md`               |
| has more than a handful of functions, or will be tailed     | `logger`      | `references/logging.md`            |
| has a path a caller or test must redirect                   | `config`      | `references/config.md`             |
| is sourced by other code                                    | `library`     | `references/library.md`            |
| holds logic worth isolating from its side effects           | `tests`       | `references/testing.md`            |

State the result in one line before writing, absences included:

```text
Floor + cleanup + partial-run. No cli, no logger, no config, no library, no tests.
```

Naming the absences is the point. It makes the decision auditable, and it is the record that the missing machinery was considered and declined rather than forgotten.

### What is not a trigger

- **Line count.** A 200-line linear build script needs nothing beyond the Floor. A 20-line loop that deletes remote objects needs `dry-run`, `partial-run` and `cleanup`.
- **Anticipated growth.** Add the tag when the behaviour arrives, not in advance.
- **Symmetry with a sibling script.** The sibling has its own triggers.
- **The script feeling important.** Importance is not a behaviour.

A linear script that takes no arguments and mutates nothing needs no tags at all, and is not deficient for lacking them.

### As the script grows

Re-run triage on each change, but only for the triggers that change could have crossed. Adding a temp file fires `cleanup` and nothing else. Adding a second option fires `cli` if it was not already lit. Adding a call to `date --utc` fires `preflight`.

Tags accumulate, they do not escalate. Firing `dry-run` does not pull in `logger`; each is earned separately.

## The Floor

What every script owes, whatever its tags:

- the `.bash` extension and the `env bash` shebang
- strict mode
- a `main` function behind the source guard, once the file defines any function
- braced, quoted expansions
- clean `shellcheck` and `shfmt --indent 4`
- explicit checks on fallible calls
- diagnostics on stderr
- comments only where they explain why

### Script Files

- Prefer to name Bash scripts with the `.bash` extension, unless the project already uses the `.sh` extension.
- Always use the shebang `#!/usr/bin/env bash`.
- Use strict mode when the script is intended to be run directly:

```bash
set -o errexit
set -o nounset
set -o pipefail
```

A file that is sourced rather than executed sets no strict mode and defends itself differently; that is the `library` tag.

### Main Guard

A script that defines any function puts its top-level flow in `main` and ends with the guarded call, never a bare `main "${@}"` and never top-level commands between the functions:

```bash
if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
```

The guard is what lets the file be sourced without running: a BATS test can `load` it to test one function, a sibling script can borrow a helper, and a stray `source` in a shell does nothing. The `:-${0}` default keeps it nounset-safe when the script is piped to `bash -s` or passed with `bash -c`, both of which leave `BASH_SOURCE[0]` unset and still count as execution. `references/library.md` has the invocation table.

A linear script with no functions owes no `main`: there is nothing to source it for. The moment it grows a function, it owes both.

### Formatting and Linting

- Use 4 spaces for indentation.
- Follow `.editorconfig` for code formatting when present.
- Format with `shfmt --indent 4`. Lint with `shellcheck`. Both are required tools; run them before considering work complete:

```bash
shellcheck ./*.bash
shfmt --indent 4 --write ./*.bash
```

Install via `brew install shellcheck shfmt`, or see <https://github.com/koalaman/shellcheck#installing> and <https://github.com/mvdan/sh#shfmt>.

Silence a shellcheck finding with a targeted `# shellcheck disable=SCxxxx` on the line directly above it, never file-wide, and only when the finding is genuinely a false positive.

### Comments

Do NOT add unnecessary comments. Use comments only to explain **why** something exists, when that is not clear from the code itself. In practice the ones that earn their keep explain why _not_ the obvious thing:

```bash
# created once and truncated per iteration: a RETURN trap
# stays installed after the function returns and re-fires
# with the variable out of scope
: >"${states_file}"
```

### Syntax Conventions

Define functions with the `function` keyword:

```bash
function do_thing() {
```

This makes every definition greppable with `grep '^function '`. The bare `do_thing()` form collides with call sites, so it cannot be found reliably.

Inside function bodies, prefer the POSIX construct and reach for a Bash-only one when it earns its keep:

```bash
[ "${a}" = "${b}" ]              # default: POSIX test
[[ "${text}" =~ ^[0-9]+$ ]]      # earns it: regex match
[[ "${name}" == prefix* ]]       # earns it: pattern match
((count > 0))                    # earns it: arithmetic has no clean POSIX form
```

The file as a whole is unapologetically Bash. `local`, arrays, `BASH_SOURCE`, `FUNCNAME` and the `function` keyword are structural and need no justification. The preference applies where POSIX and Bash constructs do the same job.

### Variables

Always use double brackets and quotes for variable references:

```bash
"${EXAMPLE}"     # correct
```

All of the following are incorrect:

```bash
$EXAMPLE         # wrong
${EXAMPLE}       # wrong, unquoted
"$EXAMPLE"       # wrong, no braces
```

Declare, then assign, whenever the value comes from a command:

```bash
local resolved
resolved=$(realpath --quiet "${path}") || return 1
```

Writing `local resolved=$(realpath --quiet "${path}")` instead is masking: the exit status belongs to `local`, which always succeeds, so the assignment always looks successful and `errexit`, `if !` and `||` all see success. Shellcheck reports this as SC2155.

Use `local -r` for a parameter the function must not reassign, and `readonly` for file-level constants.

Heredocs invert the quoting rule, so choose the delimiter deliberately: `<<'EOF'` expands nothing and emits `${EXAMPLE}` literally, `<<EOF` expands everything including any `$` the body did not intend as a variable. Quote the delimiter for usage text, embedded programs, and anything holding literal `$`; leave it bare only where the body is a template you are filling in.

### Error Handling

`errexit` is advisory, not a safety net. It does not fire inside command substitutions, test conditions, or `&&` and `||` chains, nor in functions called from those positions, and a sourced library may be running without it entirely. Check every fallible call explicitly:

```bash
local config
if ! config=$(json_read_file "${config_file}"); then
    echo_stderr "failed to read ${config_file}"
    return 1
fi
```

- Return 0 for success and non-zero for failure. Reserve distinct non-zero codes for failures a caller must tell apart.
- Always fail with the reason on stderr, never with a bare non-zero exit.
- When the user can fix several problems in one pass, collect them all before failing. Report every missing dependency, not just the first one found.

Error messages must go to stderr. The whole requirement at the Floor is one function:

```bash
function echo_stderr() {
    echo "${*}" >&2
}
```

Filtering by severity, timestamps and calling-function names are the `logger` tag, not the Floor.

### Functions

- Standard output is reserved for a function's return value. Diagnostics, progress, and errors go to stderr.
- Name predicates `is_*`. They print nothing and communicate only through exit status, so callers read as `if ! is_readable_file "${path}"; then`.
- Validate arguments at the top of the function, using the project's existing predicates.

`references/helpers.md` carries reusable predicates: `is_cmd_available`, `is_readable_file`, `is_non_empty_dir`, `is_valid_json`, and `is_json_object`.

### Reading Input

Always read with `IFS= read -r`. Without `IFS=`, leading and trailing whitespace is stripped from each line; without `-r`, backslashes are consumed as escapes:

```bash
while IFS= read -r line; do
    process "${line}"
done <"${file}"
```

Iterate over multi-line output with a here-string, not a pipe. A pipe puts the loop body in a subshell, so any variable it sets is lost when the loop ends:

```bash
while IFS= read -r item; do
    [ -z "${item}" ] && continue
    process "${item}"
done <<<"${items}"
```

A function that reads text takes it from arguments or stdin, so it composes both ways:

```bash
local input
if [ "${#}" -gt 0 ]; then
    input="${*}"
else
    input=$(cat)
fi
```

Prefer parameter expansion over spawning `sed`, `tr` or `cut` for trimming, case folding, and prefix or suffix removal. `references/helpers.md` carries the trim helper and the expansions that replace a subprocess.

### Paths

Resolve a path before trusting it, rather than sanitising it. `realpath` collapses `..` and symlinks and fails on input that does not name a file, so resolution plus quoting covers what character-stripping attempts:

```bash
local resolved
resolved=$(realpath --quiet "${path}" 2>/dev/null) || return 1
[ -f "${resolved}" ] && [ -r "${resolved}" ]
```

For a path that need not exist yet, such as a file the script is about to create, add `--canonicalize-missing`.

A script that needs its own directory resolves it like this:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
```

`dirname "${0}"` is not a substitute. It reports the caller when the file is sourced, and neither form resolves symlinks or a relative invocation without the `cd` and `pwd` round trip.

Note that `realpath` with long flags is a GNU dependency, which fires `preflight`.

## Reviewing Existing Scripts

Run shellcheck first. It catches items 1 and 2 mechanically. The rest need reading.

Always, regardless of tags:

1. `local x=$(cmd)` masking exit status
2. unquoted or unbraced expansions
3. `errexit` relied on inside functions, conditions, or command substitutions
4. paths used without resolution
5. diagnostics or logs on stdout
6. a script that defines functions and runs its flow outside `main`, or calls `main` without the source guard

Then triage the script as written and check only what its tags owe:

| Tag           | Check                                                             |
| ------------- | ----------------------------------------------------------------- |
| `json`        | shell values interpolated into jq or other embedded queries       |
| `preflight`   | GNU-only flags with no preflight check                            |
| `cleanup`     | `RETURN` traps, or temp state with no `EXIT` trap                 |
| `signals`     | a signal handler that exits 0                                     |
| `dry-run`     | mutation reachable without an explicit `--apply`                  |
| `partial-run` | a loop that reports success without saying how far it got         |
| `cli`         | an unrecognised option ignored rather than failing                |
| `library`     | strict mode set in a sourced file, or a missing source guard      |
| `tests`       | no failure-path or adversarial tests                              |

Finally, the reverse check: machinery present whose trigger never fired. A leveled logger, reload handler, dry-run flag, or config indirection in a script that is linear, takes no arguments, and mutates nothing is a finding in its own right. Report it as one.
