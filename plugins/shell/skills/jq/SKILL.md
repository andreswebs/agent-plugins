---
name: jq
description: >
  Use the jq CLI tool and jq language to query, transform, filter, and
  construct JSON data. Use this skill when working with JSON or JSONL/JSON Lines
  processing in the command line, such as extracting fields from API responses,
  reshaping data structures, filtering arrays, merging JSON files, or building JSON
  from shell variables, even if the user doesn't explicitly mention "jq".
---

# jq

jq is a CLI tool and functional language for JSON processing. It reads JSON from stdin or files, applies a filter expression, and writes results to stdout.

## When to Use

- Extract or reshape fields from JSON
- Filter, sort, group, or aggregate array elements
- Merge or diff JSON files
- Convert between JSON, JSONL, CSV, TSV
- Build JSON from shell variables or raw text
- Process streaming or large JSON
- Validate or pretty-print JSON

## Quick Reference

See [references/cli.md](references/cli.md) for all CLI options, exit codes, and usage patterns.
See [references/jq-lang.md](references/jq-lang.md) for the complete language reference including all builtins.

## Rules

- Always use long-form CLI flags (e.g. `--raw-output` not `-r`, `--compact-output` not `-c`, `--null-input` not `-n`). This applies to all jq commands you generate.

## Core Concepts

Every jq expression is a filter that receives input and produces zero or more outputs. Filters compose with pipe `|`. Comma `,` concatenates output streams.

Identity: `.` returns input unchanged.

Access: `.foo`, `.["key"]`, `.[0]`, `.[-1]`, `.[2:5]`, `.[]`, `..`

Construction: `[expr]` builds arrays, `{key: expr}` builds objects.

Variables: `expr as $name | body`

## Essential CLI Flags

```
jq '.' file.json                        # pretty-print
jq --raw-output '.name' file.json       # raw string output (no quotes)
jq --compact-output '.' file.json       # compact single-line output
jq --exit-status '.key' file.json       # exit 1 if output is false/null
jq --null-input 'expr'                  # null input (don't read stdin)
jq --slurp '.' file.json                # slurp all inputs into array
jq --raw-input '.'                      # read lines as raw strings
jq --arg name "$VAR" '...'              # pass shell string as $name
jq --argjson n 42 '...'                 # pass parsed JSON as $n
jq --slurpfile d data.json              # bind file contents to $d
```

## Common Patterns

Extract a field:

```
jq --raw-output '.name' data.json
```

Filter array:

```
jq '[.[] | select(.active == true)]' data.json
```

Transform structure:

```
jq '{id: .user_id, email: .contact.email}' data.json
```

Map over array:

```
jq '[.items[] | {name, price: (.cost * 1.1)}]' data.json
```

Group and aggregate:

```
jq 'group_by(.category) | map({key: .[0].category, count: length})' data.json
```

Sort:

```
jq 'sort_by(.date) | reverse' data.json
```

Merge objects:

```
jq --slurp '.[0] * .[1]' base.json overrides.json
```

Merge array of objects:

```
jq --slurp 'add' file1.json file2.json
```

Build JSON from shell variables:

```
jq --null-input --arg name "$NAME" --arg email "$EMAIL" '{name: $name, email: $email}'
```

Conditional:

```
jq 'if .status == "active" then .name else empty end' data.json
```

Unique values:

```
jq '[.[].category] | unique' data.json
```

Count by field:

```
jq 'group_by(.status) | map({status: .[0].status, count: length})' data.json
```

Flatten nested arrays:

```
jq '[.items[].tags[]]' data.json
```

Object to key-value pairs:

```
jq 'to_entries | map("\(.key)=\(.value)") | .[]' data.json
```

Key-value pairs to object:

```
jq 'from_entries' data.json
```

Update nested field:

```
jq '.config.timeout = 30' data.json
```

Delete field:

```
jq 'del(.metadata)' data.json
```

Alternative/default value:

```
jq '.name // "unknown"' data.json
```

String interpolation:

```
jq --raw-output '"User: \(.name) (\(.email))"' data.json
```

## JSONL Processing

JSONL (one JSON per line) is jq's natural input format. No special flags needed for reading.

```
# filter JSONL
jq 'select(.level == "error")' logs.jsonl

# convert array to JSONL
jq --compact-output '.[]' array.json

# convert JSONL to array
jq --slurp '.' input.jsonl

# aggregate JSONL
jq --slurp 'length' events.jsonl
jq --slurp 'map(.amount) | add' transactions.jsonl
```

## CSV/TSV Output

```
# array of arrays to CSV
jq --raw-output '.[] | @csv' data.json

# array of objects to CSV with header
jq --raw-output '(.[0] | keys_unsorted) as $k | $k, (.[] | [.[$k[]]]) | @csv' data.json

# TSV output
jq --raw-output '.[] | [.name, .age] | @tsv' data.json
```

## Shell Integration

```
# conditional check
if jq --exit-status '.enabled' config.json > /dev/null 2>&1; then
  echo "enabled"
fi

# capture value
value=$(jq --raw-output '.key' file.json)

# iterate
jq --raw-output '.items[]' file.json | while read -r item; do
  echo "Processing: $item"
done

# safe iteration (handles newlines in values)
jq --raw-output0 '.items[]' file.json | xargs -0 -n1 process
```

## Regex

```
jq 'select(.name | test("pattern"))'          # filter by regex
jq '.name | capture("(?<first>\\w+)")'        # named capture
jq '.text | gsub("old"; "new")'               # replace all
jq '[.[] | select(.url | test("https?://"))]'  # match URLs
```

Flags: `i` case-insensitive, `x` extended, `m` multiline, `g` global.

## Error Handling

```
.foo?                          # suppress errors (produce empty on error)
try .foo catch "default"       # catch with fallback
try (expr) catch .             # catch, error message in .
```

## Reduce

Fold a stream into a single value:

```
reduce .[] as $x (0; . + $x)
```

## Pitfalls

- Function arguments use `;` not `,`. `foo(1; 2)` is two args; `foo(1, 2)` is one arg generating two values.
- Numbers are IEEE 754 doubles. Integers above 2^53 lose precision.
- String `index`/`rindex` return byte offsets, not codepoint offsets.
- `=` and `|=` behave differently with `empty`: `.a = empty` produces no output; `.a |= empty` deletes the path.
- `nan` prints as `null` in JSON output. Use `isnan` to detect.
- Use `--arg` for strings, `--argjson` for parsed JSON. Mixing them up causes subtle bugs.
