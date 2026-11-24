# Sourced Libraries

**Trigger:** the file is sourced by other code.

A library owes four things beyond the Floor:

- **No strict mode.** It runs in the caller's shell, and flipping options underneath a caller changes behaviour the caller did not ask for.
- **Explicit checks instead.** Since `errexit` may not be set at all, every fallible call is checked, as under Error Handling in the Floor.
- **A source guard**, so direct execution does not run library code.
- **No work at load time.** A library that acts when sourced cannot be unit tested by `load`, which also makes `tests` worth firing.

## Source Guards

Bash exposes `BASH_SOURCE[0]` (the file the current code came from) and `${0}` (how the shell was invoked). Comparing them tells a file whether it was sourced or executed. Two caveats shape how to write the check:

- Under `set -o nounset`, referencing `BASH_SOURCE[0]` when it is **unset** aborts the script with `BASH_SOURCE[0]: unbound variable`. It is unset whenever the code did not come from a named file, i.e. when piped to `bash -s` or passed via `bash -c`.
- Piping a script over stdin is a common, legitimate way to run one, for example to run a local script on a remote host without copying it:

  ```bash
  ssh "${REMOTE_HOST}" 'bash -s' < ./script.bash
  ```

  Here `BASH_SOURCE[0]` is unset and `${0}` is `bash`, so a bare `${BASH_SOURCE[0]}` both crashes under nounset and, if it did not, would fail to recognise this as an execution.

Default `BASH_SOURCE[0]` to `${0}` so the guard is nounset-safe and treats piped stdin as execution.

For files intended to be sourced as libraries (not executed directly), add a guard at the top to prevent direct execution:

```bash
[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0
```

If the file was sourced, `BASH_SOURCE[0]` differs from `${0}` and loading continues. If executed directly, `return 0` exits before running any library code.

## Dual-Purpose Files

For files that work both as a library (when sourced) and as an executable (run directly or piped via `bash -s`), invert the check and gate the main logic:

```bash
if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
```

The `:-${0}` default applies only when `BASH_SOURCE[0]` is unset, which never happens when a file is sourced (sourcing always populates it with the file path). The sourced-versus-executed intent is therefore preserved exactly; the default only adds coverage for the stdin and `bash -c` case, treating it as execution. Behaviour by invocation:

| Invocation                                     | `BASH_SOURCE[0]`          | `${0}`                           | `main` runs? |
| ---------------------------------------------- | ------------------------- | -------------------------------- | ------------ |
| `bash script.bash` or `./script.bash`          | `script.bash`             | `script.bash`                    | yes          |
| `source script.bash` or `. script.bash`        | `script.bash`             | calling shell (`bash` / `-bash`) | no           |
| `bash -s < script.bash` (piped, e.g. over SSH) | unset, defaults to `${0}` | `bash`                           | yes          |

A dual-purpose file may set strict mode inside `main` rather than at file scope, so an execution gets it and a caller that sourced the file does not.
