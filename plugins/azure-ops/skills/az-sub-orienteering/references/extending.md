# Extending the sweep

Everything pluggable lives in `scripts/lib/`. The runner sources every `*.bash`
there in name order and discovers modules by function name; nothing is
registered.

## Adding a module

Create `scripts/lib/NN-<name>.bash`:

```bash
#!/usr/bin/env bash
# One line on what question this module answers.

[[ "${BASH_SOURCE[0]:-${0}}" != "${0}" ]] || return 0

function module_NN_<name>() {
    report_begin "Human title"

    if skip_if_absent "Microsoft.Foo/bars"; then
        return 0
    fi

    run_az_json bars foo bar list || true

    emit_section "Bars"
    emit_columns "${AZSD_RAW_DIR}/bars.json" "Name|RG|SKU" "name|resourceGroup|sku.name"
    return 0
}

function module_NN_<name>_types() {
    echo "Microsoft.Foo/bars"
}
```

- `NN` fixes run order. `10` is the inventory every other module reads;
  `20`-`28` are cross-cutting; `30`+ are per-service.
- The `_types` companion lists the resource types the module covers, so the
  summary can report what is uncovered. Omit it for cross-cutting modules.
- Return 0 unless the module produced no report at all. Individual failed calls
  are logged by `run_az_json` and leave `[]` plus a `.json.err`.
- Sourced file: no `set -o`, no work at load time, source guard on line one.

## Helpers available to a module

| Helper                                    | Purpose                                                            |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `run_az_json NAME az-args...`             | Save `az ...` JSON to `raw/<module>/NAME.json`, subscription pinned |
| `az_rest_json NAME METHOD URL [BODY]`     | Same for `az rest`                                                 |
| `arg_query NAME file.kql`                 | Resource Graph query from `lib/file.kql`, saves the `data` array   |
| `inventory_count TYPE`                    | Count of that type in the inventory                                |
| `inventory_of_type TYPE`                  | `name<TAB>rg<TAB>id` per resource, for loops                       |
| `skip_if_absent TYPE...`                  | Emit a one-liner and return 0 when none present                    |
| `normalize_list FILE`                     | Unwrap `{value: [...]}` in place                                   |
| `json_count FILE`                         | Item count, 0 for missing                                          |
| `emit`, `emit_section`, `emit_subsection` | Append to the report                                               |
| `emit_columns FILE HEADER PATHS`          | Table from dotted paths; HEADER and PATHS are pipe-separated       |
| `emit_group_count FILE HEADER PATH`       | Count-by table                                                     |
| `emit_table FILE HEADER 'jq rows' [args]` | Table from a jq row stream; shell values via `--arg` after it      |
| `emit_table_from FILE HEADER file.jq [args]` | Table from a `lib/*.jq` program that outputs an array of rows   |
| `log_info`, `log_warn`, `log_debug`       | stderr, prefixed with the module name                              |

## Adding a Resource Graph query

Drop `lib/<name>.kql`. The subscription scope comes from the request body, so
the query text carries no ids. Results are one page of 1000; the runner warns
on truncation. Project the columns you will render and read them with
`emit_columns`.

## Adding a jq renderer

Drop `lib/<name>.jq`. Convention: input is the raw file, output is an array of
row arrays, shell values arrive as `--arg` bindings. `md-table.jq` stringifies
cells, so rows may hold numbers, booleans and nulls (null renders as `-`).

Check syntax with `jq --null-input --from-file lib/<name>.jq`; a "Cannot
iterate over null" error at that point is runtime, not syntax, and is fine.

## Growing the diagnostic-settings check

`lib/diagnostic-types.txt` lists the resource types the observability module
probes, one per line. Add a type there; no code changes.

## Before finishing

```sh
shellcheck scripts/az-sub-discovery.bash scripts/lib/*.bash
shfmt --indent 4 --diff scripts/az-sub-discovery.bash scripts/lib/*.bash
scripts/az-sub-discovery.bash --list
```

`--list` must show the new module in its intended position and nothing named
`*_types`.
