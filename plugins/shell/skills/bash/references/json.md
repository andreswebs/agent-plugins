# JSON and Embedded Queries

**Trigger:** the script builds a jq, awk, sed or sql program from a shell value, or any other text a downstream tool parses as source.

Use `jq` for any JSON handling, and load the `jq` skill for the language itself and its full flag set. The Bash-side rules follow.

## Bind, Never Interpolate

Bind values into a jq program. An interpolated shell value is parsed as jq source, so a quote or a `$` in the data rewrites the program:

```bash
jq ".id == ${id}" file.json                          # wrong
jq --argjson id "${id}" '.id == $id' file.json       # right: JSON value
jq --arg name "${name}" '.name == $name' file.json   # right: string value
```

jq is one instance of a general shape: any program text a script assembles from shell values is injectable, whatever language parses it. The rule is the same everywhere, so reach first for the interpreter's own binding mechanism and keep the program itself in single quotes:

```bash
awk -v want="${name}" '$1 == want' file      # right: awk binds with -v
awk "\$1 == \"${name}\"" file                # wrong: value becomes awk source
```

Where a language offers no binding mechanism, interpolation is unavoidable and carries two obligations instead: validate the value against an explicit shape before it goes in, and record where the value came from. This is the case for `sed` scripts, Azure OData `--filter`, JMESPath in `--query`, KQL, and SQL passed to a CLI that exposes no parameters.

```bash
# assignment names come from the ARM API and are charset-constrained;
# OData has no binding mechanism
[[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
```

## Constructing JSON

Construct JSON with `--null-input` and bound arguments, not by concatenating braces into a string:

```bash
jq --null-input --compact-output \
    --arg path "${file_path}" \
    --argjson size "${size}" \
    '{path: $path, size: $size}'
```

Turn arbitrary text, such as captured command output, into a JSON string with `--raw-input --slurp`:

```bash
printf '%s' "${text}" | jq --raw-input --slurp '.'
```

## Reading JSON

Use jq as a predicate with `--exit-status`, discarding its stdout:

```bash
if echo "${input}" | jq --exit-status 'type == "object"' >/dev/null 2>&1; then
```

For output another program consumes, pass `--raw-output` for strings and `--compact-output --monochrome-output` for JSON. jq adds colour escapes whenever it believes it is writing to a terminal.

Capture jq output with declare-then-assign, as with any other command, so a malformed document fails the caller instead of yielding an empty string.

`references/helpers.md` carries `is_valid_json` and `is_json_object` as ready-made predicates.
