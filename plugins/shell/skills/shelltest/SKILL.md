---
name: shelltest
description: Write shell tests using shelltestrunner format. Use when creating .test files, testing CLI programs, writing command-line tests, or when the user mentions shelltest, shelltestrunner, or shell testing.
---

# Writing Shell Tests

Use **Format 3** (preferred) for all new tests. Files use `.test` extension.

## Basic Structure

```txt
# Comment describing the test
<
INPUT TO STDIN (optional)
$ command to run
EXPECTED STDOUT (optional)
>2
EXPECTED STDERR (optional)
>= EXIT_CODE (optional, defaults to 0)
```

## Delimiters

| Delimiter | Purpose         | Notes                                                                   |
| --------- | --------------- | ----------------------------------------------------------------------- |
| `<`       | stdin input     | Optional; shared across following tests until next `<`                  |
| `$`       | Command         | Required; use `$  cmd` (two spaces) to prevent `--with` replacement     |
| `>`       | Expected stdout | Omit = expect empty; `> /regex/` for pattern matching                   |
| `>2`      | Expected stderr | Omit = expect empty; `>2 /regex/` for pattern matching                  |
| `>=`      | Exit code       | Omit = expect 0; `>= !0` for any non-zero; `>=` alone ignores exit code |

## Matching Patterns

```txt
# Literal match
$ echo hello
hello

# Regex match (POSIX extended)
$ date
> /[0-9]{4}/

# Negative match (does NOT contain)
$ my-command
> !/error/

# Exit code patterns
>= 0       # expect 0
>= 1       # expect 1
>= !0      # expect any non-zero
>=         # ignore exit code (accept any)
```

## Common Patterns

| Goal                  | Syntax             |
| --------------------- | ------------------ |
| Expect empty stdout   | Omit `>` section   |
| Expect empty stderr   | Omit `>2` section  |
| Ignore stdout content | `> //`             |
| Ignore stderr content | `>2 //`            |
| Expect success        | Default, or `>= 0` |
| Expect failure        | `>= !0`            |
| Match partial output  | `> /pattern/`      |

## Complete Example

```txt
# Addition works correctly
<
2 + 3
$ my-calculator
5

# Division by zero shows error
<
10 / 0
$ my-calculator
>2 /division by zero|cannot divide/
>= 1

# Help flag shows usage
$ my-calculator --help
> /usage:/i

# Invalid flag fails
$ my-calculator --invalid
>2 /unknown option/
>= !0
```

## Shared Input

Multiple tests can share the same input block:

```txt
<
shared data
$ cat
shared data

$ wc -c
12
```

Use another `<` to start fresh input:

```txt
<
first input
$ cat
first input

<
second input
$ cat
second input
```

## Escaping

- Forward slashes in regex: `> /path\/to\/file/`
- When output ends with blank lines, add explicit `>=` to terminate

## Running Tests

```bash
shelltest tests/           # Run all tests in directory
shelltest file.test        # Run specific file
shelltest -j4 tests/       # Parallel execution
shelltest -w ./myprogram tests/  # Replace command under test
shelltest -DVAR=value tests/     # Define macro
```

## Best Practices

1. One behavior per test
2. Use `!0` instead of specific exit codes for portability
3. Prefer literal matching over regex when possible
4. Add comments explaining what each test verifies
5. Use macros (`-DEXE=./program`) for paths that may change

## Additional Resources

- Formal specification: [ABNF grammar](references/shelltest.grammar.md)
