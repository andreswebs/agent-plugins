# Portability Preflight

**Trigger:** the script uses a GNU long flag.

Be explicit with command-line arguments. Always use the long form of command flags when available:

```bash
grep --recursive --include="*.bash" "pattern" .   # correct
grep -r --include="*.bash" "pattern" .            # avoid
```

Long flags are also, for the most part, a GNU extension. The BSD and macOS builds of `realpath`, `sed`, `xargs`, `date` and others reject them. A script written this way therefore depends on GNU coreutils and must say so by failing fast: preflight the commands it calls, the minimum Bash version it needs, and each individual flag it relies on, before doing any work.

A command being present says nothing about its flags. The smallest form of the check is a single probe:

```bash
if ! date --help 2>&1 | grep --quiet -- --utc; then
    echo_stderr "GNU date required (brew install coreutils)"
    exit 1
fi
```

That example is not hypothetical: a logger calling `date --utc` on every line fails on every line under BSD `date`, which is what macOS resolves unless `gnubin` precedes it on `PATH`.

## The Full Preflight

Run this before any real work, so the script fails on a clear message rather than midway through with a cryptic one.

```bash
function mytool_check_dependencies() {
    if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
        echo_stderr "bash version 4.3 or higher is required"
        return 1
    fi

    local deps=(
        "grep"
        "realpath"
        "jq"
    )

    local missing_commands=()

    for cmd in "${deps[@]}"; do
        if ! is_cmd_available "${cmd}"; then
            missing_commands+=("${cmd}")
        fi
    done

    if [ "${#missing_commands[@]}" -gt 0 ]; then
        echo_stderr "the following required commands are missing:"
        for missing_cmd in "${missing_commands[@]}"; do
            echo_stderr "  - ${missing_cmd}"
        done
        return 1
    fi

    local realpath_help
    if ! realpath_help=$(realpath --help 2>&1); then
        echo_stderr "failed to run 'realpath --help'"
        return 1
    fi

    local required_flags=("--canonicalize-missing" "--quiet")
    for flag in "${required_flags[@]}"; do
        if ! grep --quiet -- "${flag}" <<<"${realpath_help}"; then
            echo_stderr "installed realpath does not support ${flag} (required); update 'coreutils'"
            return 1
        fi
    done

    return 0
}
```

Substitute `log_fatal` for `echo_stderr` if the script also carries the `logger` tag.

Three things are being checked, and each fails differently in the wild:

- **Bash version.** Associative arrays need 4.0, `declare -n` needs 4.3. macOS ships Bash 3.2, so a script relying on either dies with a syntax error rather than a useful message. The arithmetic form compares major and minor without string parsing.
- **Commands.** Collect every missing one before failing, so the user installs them in one pass.
- **Flags.** Presence of a command says nothing about its flags. Probing `--help` output distinguishes GNU coreutils from the BSD build that ships on macOS, which is what a script using long flags actually depends on.

macOS with GNU coreutils installed via Homebrew still resolves `realpath` to the BSD one unless `gnubin` is ahead on `PATH`, so this probe catches a real and common configuration, not a theoretical one.

## Scaling the Check

A script using one GNU flag owes one probe, not the function above. Grow it as the dependency list grows:

| The script relies on...                          | Check                                     |
| ------------------------------------------------ | ----------------------------------------- |
| one long flag on one command                     | the single `--help` probe                 |
| several commands, any of them possibly absent    | the `missing_commands` collection loop     |
| associative arrays or `declare -n`               | the `BASH_VERSINFO` arithmetic comparison |
| several flags across several commands            | the full function                         |
