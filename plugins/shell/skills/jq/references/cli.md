# jq CLI Reference

Version: 1.8

## Synopsis

```
jq [OPTIONS] FILTER [FILE...]
jq [OPTIONS] --args FILTER [STRINGS...]
jq [OPTIONS] --jsonargs FILTER [JSON_VALUES...]
```

If no files are given, jq reads from stdin. The filter is a jq expression applied to each input.

## Exit Codes

```
0    success (or truthy output with -e)
1    last output was false or null (with -e)
2    usage error
3    compile error
4    no valid output (with -e)
5    system error
```

## Options

### Input

`-n`, `--null-input`

Run the filter with `null` as input instead of reading JSON from stdin or files. Useful with `input` and `inputs` builtins to control input reading manually.

```
jq -n '[inputs]'
```

`-R`, `--raw-input`

Read each line of input as a raw string instead of parsing as JSON. Each line becomes a string value.

```
echo -e "hello\nworld" | jq -R .
# "hello"
# "world"
```

`-s`, `--slurp`

Read all inputs into a single array, then run the filter once on that array.

```
echo -e '1\n2\n3' | jq -s 'add'
# 6
```

When combined with `-R`: reads all lines into a single string (joined with newlines).

`--stream`

Parse input in streaming fashion, emitting `[path, value]` arrays for each leaf and `[path]` arrays for end-of-container markers. Useful for processing large JSON without loading it entirely into memory.

```
echo '{"a":1,"b":[2,3]}' | jq --stream .
# [[],{"a":1,"b":[2,3]}] (truncate_stream form varies)
```

`--stream-errors`

Like `--stream` but invalid JSON yields error arrays instead of aborting.

`--seq`

Use the `application/json-seq` MIME type scheme for input and output. Tolerates incomplete or invalid JSON between valid values.

### Output Format

`-c`, `--compact-output`

Output each JSON value on a single line without pretty-printing.

```
jq -c . <<< '{"a": 1, "b": 2}'
# {"a":1,"b":2}
```

`-r`, `--raw-output`

Output string values without JSON double-quotes. Non-string values are output as normal JSON.

```
echo '{"name":"alice"}' | jq -r .name
# alice
```

`--raw-output0`

Like `-r` but uses NUL (0x00) as the separator instead of newline. jq exits with a non-zero code if any output string contains NUL. Useful with `xargs -0`.

```
jq -rn --raw-output0 '"a", "b"' | xargs -0 -n1 echo
```

`-j`, `--join-output`

Like `-r` but does not append a newline after each output.

`-a`, `--ascii-output`

Force ASCII output. Non-ASCII characters are escaped as `\uXXXX` sequences.

`-S`, `--sort-keys`

Output object keys in sorted (alphabetical) order.

`-C`, `--color-output`

Force colored (ANSI) output even when output is not a terminal.

`-M`, `--monochrome-output`

Disable colored output.

`--tab`

Use tab characters for indentation instead of spaces.

`--indent N`

Use N spaces for indentation (0 to 7). Default is 2.

`--unbuffered`

Flush output after each JSON value. Useful for streaming output to another process.

### Filter Source

`-f FILE`, `--from-file FILE`

Read the jq filter from a file instead of the command line.

```
jq -f transform.jq input.json
```

### Arguments and Variables

`--arg NAME VALUE`

Define a string variable `$NAME` with the given value. Available in the filter as `$NAME` and in `$ARGS.named.NAME`.

```
jq --arg name "alice" '.user == $name'
```

`--argjson NAME JSON`

Define a variable `$NAME` with a parsed JSON value.

```
jq --argjson count 42 '.items[:$count]'
```

`--slurpfile NAME FILE`

Read the JSON file and bind its contents as an array to `$NAME`. If the file contains multiple JSON values, they become elements of the array.

```
jq --slurpfile config settings.json '$config[0].theme'
```

`--rawfile NAME FILE`

Read the entire file as a raw string and bind it to `$NAME`.

```
jq --rawfile template tmpl.txt '$template'
```

`--args`

All remaining arguments are treated as positional string arguments. Available as `$ARGS.positional` (array of strings).

```
jq -n '$ARGS.positional' --args foo bar baz
# ["foo","bar","baz"]
```

`--jsonargs`

All remaining arguments are parsed as JSON values. Available as `$ARGS.positional`.

```
jq -n '$ARGS.positional' --jsonargs '{"a":1}' '[2,3]'
# [{"a":1},[2,3]]
```

### Module Search Path

`-L DIRECTORY`

Prepend a directory to the module search path. Can be specified multiple times.

```
jq -L ./lib 'import "utils" as u; u::transform'
```

### Exit and Status

`-e`, `--exit-status`

Set exit code based on output values:

- 0: last output is truthy (not `false` or `null`)
- 1: last output is `false` or `null`
- 4: no valid output produced

Useful in shell scripts for conditional logic:

```
if jq -e '.enabled' config.json > /dev/null; then
  echo "enabled"
fi
```

### Miscellaneous

`-b`, `--binary`

Windows only. Prevents newline conversion (LF to CRLF).

`-V`, `--version`

Print jq version and exit.

`--build-configuration`

Print build configuration details and exit.

`-h`, `--help`

Print usage summary and exit.

`--`

Stop processing options. All subsequent arguments are treated as filter or file arguments.

`--run-tests [FILE]`

Run jq's internal test suite from a file or stdin.

## The $ARGS Variable

Available in all jq programs:

```
$ARGS.named         # object of --arg and --argjson values
$ARGS.positional    # array of --args or --jsonargs values
```

Example:

```
jq -n --arg user alice --argjson age 30 --args extra1 extra2 \
  '{named: $ARGS.named, positional: $ARGS.positional}'
# {"named":{"user":"alice","age":30},"positional":["extra1","extra2"]}
```

## The $ENV Variable

```
$ENV              # object of all environment variables
$ENV.HOME         # specific variable
env               # same as $ENV (builtin function)
env.PATH          # specific variable via function
```

## Common Usage Patterns

### Pretty-print JSON

```
jq . file.json
cat file.json | jq .
```

### Extract a field

```
jq '.name' file.json
jq -r '.name' file.json          # without quotes
```

### Filter array elements

```
jq '.[] | select(.active)' file.json
jq '[.[] | select(.age > 21)]' file.json
```

### Transform structure

```
jq '{name: .user, email: .contact.email}' file.json
jq '[.[] | {id, title}]' file.json
```

### Slurp multiple JSON values

```
cat *.json | jq -s '.'
```

### JSONL (JSON Lines) processing

```
# read JSONL (one JSON value per line) -- default behavior
jq '.field' input.jsonl

# produce JSONL output
jq -c '.[]' input.json
```

### Use with shell variables

```
jq --arg key "$KEY" '.[$key]' file.json
jq --argjson limit "$LIMIT" '.items[:$limit]' file.json
```

### Process raw text

```
# count lines
jq -R -s 'split("\n") | length' file.txt

# grep-like filtering
jq -R 'select(test("pattern"))' file.txt
```

### Merge JSON files

```
jq -s 'add' file1.json file2.json
jq -s '.[0] * .[1]' base.json overrides.json
```

### Build JSON from arguments

```
jq -n --arg name "$NAME" --arg email "$EMAIL" \
  '{name: $name, email: $email}'
```

### Stream large files

```
jq --stream 'select(length == 2)' huge.json
jq -cn --stream 'fromstream(1 | truncate_stream(inputs))' huge.json
```

### Shell integration

```
# use in if conditions
if jq -e '.enabled' config.json > /dev/null 2>&1; then
  echo "Feature is enabled"
fi

# assign to shell variable
value=$(jq -r '.key' file.json)

# iterate over array
jq -r '.items[]' file.json | while read -r item; do
  echo "Processing: $item"
done

# NUL-separated for items with newlines
jq -r --raw-output0 '.items[]' file.json | xargs -0 -n1 process
```
