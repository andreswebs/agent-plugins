# Configuration Paths

**Trigger:** the script has a path a caller or test must redirect.

A path the script always owns can stay a `readonly` constant. Give a redirectable path an environment override over an XDG default. The minimal form is two lines at the top of the file:

```bash
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
CONFIG_FILE="${MYTOOL_CONFIG_FILE:-${XDG_CONFIG_HOME}/mytool/config.json}"
```

Giving the redirectable paths this treatment is what makes the script testable: a test points the variables at a temporary directory instead of patching the script.

## Accessor Form

For anything sourced, or with more than one path, use one accessor per path, each resolving the override and canonicalising the result. Replace the `MYTOOL_` prefix with the project's own.

```bash
function mytool_get_config_home() {
    local default_config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
    local config_home="${MYTOOL_CONFIG_HOME:-${default_config_home}/mytool}"
    if ! config_home=$(realpath --canonicalize-missing --quiet "${config_home}"); then
        echo_stderr "failed to parse path: ${config_home}"
        return 1
    fi
    echo "${config_home}"
}

function mytool_get_config_location() {
    local config_home
    config_home=$(mytool_get_config_home) || return 1
    local config_file="${MYTOOL_CONFIG_FILE:-${config_home}/config.json}"
    if ! config_file=$(realpath --canonicalize-missing --quiet "${config_file}"); then
        echo_stderr "failed to parse path: ${config_file}"
        return 1
    fi
    echo "${config_file}"
}
```

`--canonicalize-missing` is what allows these to run before the files exist, on a first run or in a test that has only created the parent directory. It is a GNU flag, so this form fires `preflight`.

Data files go under `${XDG_DATA_HOME:-${HOME}/.local/share}` and cache under `${XDG_CACHE_HOME:-${HOME}/.cache}`, resolved the same way.

Accessors rather than bare variables mean the override is honoured at every call site, including from a sourced library that never saw the top-level assignments.

## Exporting for Subprocesses

A subprocess inherits exported variables, and only exported functions:

```bash
export MYTOOL_CONFIG="${config_json}"
export -f tool_do_thing
```

`export -f` is needed when a function is called from a subshell, `xargs`, or `bash -c`, which is how plugin-style architectures make handler functions reachable. Passing loaded configuration as an exported JSON string avoids every subprocess re-reading and re-validating the file.

Both are global state: prefer arguments where a plain argument will do.
