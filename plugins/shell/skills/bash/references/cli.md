# CLI Structure, Dry Runs, Partial Runs

Three independent triggers live here. Take only the ones that fired.

- **`cli`:** the script takes options. Owes `parse_arguments` / `main` / `usage`.
- **`dry-run`:** the script mutates state outside its own output. Owes a dry-run default and an `--apply` flag.
- **`partial-run`:** the script loops over a work list. Owes per-item accounting.

A script taking one positional argument fires none of these: it validates the argument and moves on.

## Argument Parsing

Three functions with one job each: `usage` describes the interface, `parse_arguments` resolves an action, `main` dispatches it. Nothing does real work while parsing.

```bash
function usage() {
    echo_stderr "mytool - one-line description"
    echo_stderr
    echo_stderr "Usage:"
    echo_stderr "  mytool"
    echo_stderr "  mytool init-config [--overwrite | -w]"
    echo_stderr "  mytool --help | -h"
    echo_stderr "  mytool --version | -v"
    echo_stderr
    echo_stderr "Commands:"
    echo_stderr "  init-config"
    echo_stderr "    Initialize configuration files"
    echo_stderr
    echo_stderr "Options:"
    echo_stderr "  --help, -h"
    echo_stderr "    Show this help"
    echo_stderr
    echo_stderr "  --version, -v"
    echo_stderr "    Show version information"
    echo_stderr
    echo_stderr "  --overwrite, -w"
    echo_stderr "    Overwrite existing configuration files (use with init-config)"
    echo_stderr
}

function parse_arguments() {
    action="root"

    while [ "${#}" -gt 0 ]; do
        key="${1}"
        case "${key}" in
        --version | -v)
            mytool_version >&2
            exit 0
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        init-config)
            action="init-config"
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    while [ "${#}" -gt 0 ]; do
        key="${1}"
        case "${key}" in
        --overwrite | -w)
            if [ "${action}" = "init-config" ]; then
                action="init-config-overwrite"
            fi
            break
            ;;
        -?*)
            echo_stderr "$(basename "${0}"): invalid option: ${key}"
            exit 1
            ;;
        *)
            echo_stderr "$(basename "${0}"): invalid argument: ${key}"
            exit 1
            ;;
        esac
    done
}

function main() {
    local action
    parse_arguments "${@}"
    case "${action}" in
    "init-config") mytool_config_init ;;
    "init-config-overwrite") mytool_config_init "overwrite" ;;
    "root") mytool_main ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
```

### Notes

**Two passes, not one.** The first loop resolves the command, the second its options. This keeps `--overwrite` from being accepted before the command it modifies, without a state machine inside a single loop.

**`-?*` before `*`.** The `-?*` arm catches anything that looks like an unknown option and fails; without it, a mistyped `--overwirte` falls through to `*` and is reported as an argument, or worse, silently ignored. An unrecognised option always exits non-zero.

**`action` is declared in `main`, assigned in `parse_arguments`.** The parser writes to a variable it does not declare, which keeps the scope with the caller that consumes it and avoids a global. Shellcheck may warn about the apparently unassigned reference; that is the one place a targeted disable is reasonable.

**The dispatcher is `main`, never `run`.** A BATS test that `load`s the file brings every function it defines into the test, and one named `run` replaces BATS's own `run`: each `run some_function` then invokes the script's dispatcher and fails on its first argument as an invalid option. `main` is also the name the Floor's source guard already calls.

**`usage` and `--version` write to stderr.** Stdout stays reserved for whatever the tool actually produces, so `mytool | consumer` never receives help text. Both still exit 0, since asking for help is not an error.

**`shift` then `break`** after matching a command, so the remaining arguments are what the second loop sees.

For a tool with many subcommands, keep the same shape and dispatch to a `cmd_<name>` function per command rather than growing the `case` in `main`.

## Dry Run

A script that mutates anything outside its own output defaults to a dry run, with applying gated behind an explicit `--apply`:

```bash
APPLY="false"

case "${key}" in
--apply) APPLY="true" ;;
esac
```

The default protects the expensive mistake and the flag is the record that someone chose it.

A dry run enumerates and counts what it would change, item by item, rather than announcing intent. A cost or blast-radius estimate is only as good as that list; in one case the enumerated count corrected a prior estimate by six times.

```bash
if [ "${APPLY}" != "true" ]; then
    echo_stderr "would delete ${item}"
    continue
fi
```

Enumerating from the same loop that applies is what keeps the two in agreement. A dry run computed by a separate code path drifts from the real one, and the drift is invisible until it matters.

## Partial-Run Reporting

A loop over a work list reports how far it got, because "failed" and "failed after changing 40 of 60 things" call for different responses. The work list need not mutate anything: a read-only probe whose sections are its work list owes the same accounting, since "4 of 11 sections completed" is what tells the operator which half of the inventory to distrust.

```bash
local total_count="${#items[@]}"
local applied_count=0
local failed_items=()

for item in "${items[@]}"; do
    if ! apply_change "${item}"; then
        failed_items+=("${item}")
        continue
    fi
    applied_count=$((applied_count + 1))
done

echo_stderr "applied ${applied_count} of ${total_count}"

if [ "${#failed_items[@]}" -gt 0 ]; then
    echo_stderr "failed:"
    for failed_item in "${failed_items[@]}"; do
        echo_stderr "  - ${failed_item}"
    done
    return 1
fi
```

Three obligations:

- **Continue or abort is a deliberate choice.** `continue` suits independent items; a dependent sequence breaks out on the first failure. Either way the count is reported.
- **Name the failures, not just the number.** A count tells the operator something went wrong; the list tells them what to retry.
- **Exit non-zero if any item failed.** A run that changed some things and reports success is the failure mode this pattern exists to prevent.

`applied_count` and `total_count` are also what a signal handler reports on interrupt, so a script with both this tag and `signals` keeps them where the handler can see them. See `references/signals.md`.
