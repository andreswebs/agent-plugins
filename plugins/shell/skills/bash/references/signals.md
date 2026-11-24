# Temporary State and Signals

Two independent triggers live here. Take only the one that fired.

- **`cleanup`:** the script creates a temp file. Owes an `EXIT` trap, however small the script is.
- **`signals`:** the run is long enough to interrupt, or holds a resource. Owes handlers that exit non-zero.

## Temporary State

Anything created that must not outlive the script is removed by an `EXIT` trap, registered on the line after the thing is created so no early-return path can skip it:

```bash
local work_dir
work_dir=$(mktemp -d) || return 1
trap 'rm -rf "${work_dir}"' EXIT
```

`EXIT` fires on normal exit and on any trapped signal whose handler exits, so it does not need pairing with `SIGINT` and `SIGTERM` handlers of its own. It does not fire on `SIGKILL`.

`EXIT` is the only trap to use for this. Scratch needed per iteration of a loop is one file created before the loop and truncated inside it, not one file per iteration:

```bash
local states_file
states_file=$(mktemp) || return 1
trap 'rm -f "${states_file}"' EXIT

for assignment in "${assignments[@]}"; do
    : >"${states_file}"
    fetch_compliance "${assignment}" >"${states_file}" || continue
    process_states "${states_file}"
done
```

`trap 'rm -f "${states_file}"' RETURN` inside a function looks like the per-scope equivalent and is not. Bash leaves the `RETURN` trap installed after the function returns, so it re-fires on an unrelated later return where `states_file` is out of scope, and under `nounset` the script dies with `states_file: unbound variable` at a line that has nothing to do with the temp file. It fires after the work has reported success, so the run looks finished and still fails.

Use `mktemp` rather than a constructed path under `/tmp`: a predictable name is both a collision and a symlink-attack surface.

## Signal Handlers

Handlers for a long-running script. `reload` re-reads configuration in place, which lets an operator apply a config change without restarting; it is only worth having when the script also carries the `config` tag.

```bash
function shutdown() {
    local -r signal="${1}"

    log_warn "received ${signal} after ${applied_count} of ${total_count} changes applied"

    case "${signal}" in
    SIGINT) exit 130 ;;
    SIGTERM) exit 143 ;;
    *) exit 1 ;;
    esac
}

function reload() {
    log_info "reloading configuration"
    if ! mytool_load_config; then
        log_error "failed to reload configuration"
    fi
}

trap 'shutdown SIGINT' SIGINT
trap 'shutdown SIGTERM' SIGTERM
trap reload SIGHUP SIGUSR1
```

The handler exits 128 plus the signal number, which is what a shell reports for an uncaught signal. `exit 0` here is only correct for a daemon whose whole job was to keep running; anything that mutates state must not report success for a half-applied run.

A non-zero exit tells the operator the run did not finish, but only the message tells them how far it got, which is what they need in order to choose between resuming and rolling back. That message is the `partial-run` pattern in `references/cli.md`, which is why a script that loops over a work list and can be interrupted needs both tags.
