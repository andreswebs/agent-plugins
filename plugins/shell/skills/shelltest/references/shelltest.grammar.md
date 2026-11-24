# Shelltest Grammar (ABNF)

Formal specification for shelltestrunner test file syntax.

## Format Overview

| Format   | Status     | Delimiters                       | Use Case                       |
| -------- | ---------- | -------------------------------- | ------------------------------ |
| Format 3 | Preferred  | `<` `$` `>` `>2` `>=`            | New tests                      |
| Format 2 | Verbose    | `<<<` `$$$` `>>>` `>>>2` `>>>=`  | When short delimiters conflict |
| Format 1 | Deprecated | (none) `<<<` `>>>` `>>>2` `>>>=` | Legacy only                    |

## Format 3 Grammar

```abnf
format3-file        = *blank-or-comment format3-test-group *format3-test-group

format3-test-group  = [ input-block-f3 ] 1*format3-test

input-block-f3      = [ "<" newline ] *input-line
                      ; First input block may omit the "<" delimiter

format3-test        = *blank-or-comment command-f3 [ stdout-block-f3 ] [ stderr-block-f3 ] [ exitcode-f3 ]

command-f3          = "$" [ SP ] command-text newline
                      ; Two spaces after "$" makes command fixed (immune to --with)

stdout-block-f3     = ( ">" SP regex-matcher newline ) /
                      ( [ ">" newline ] *output-line )

stderr-block-f3     = ">2" ( SP regex-matcher newline / newline *output-line )

exitcode-f3         = ">=" [ SP exit-matcher ] newline
```

## Matchers

```abnf
regex-matcher       = [ negation ] "/" regex-pattern "/"
                      ; Forward slashes in pattern escaped as "\/"

exit-matcher        = regex-matcher / numeric-matcher

numeric-matcher     = [ negation ] 1*DIGIT

negation            = "!"
```

## Format 3 Defaults

- **stdout**: Expects empty (if `>` omitted)
- **stderr**: Expects empty (if `>2` omitted)
- **exit code**: Expects 0 (if `>=` omitted)

## Format 2 Grammar

Uses longer delimiters (`<<<`, `$$$`, `>>>`, `>>>2`, `>>>=`) but otherwise identical semantics to Format 3.

## Format 1 Grammar (Deprecated)

- Command comes first (no delimiter)
- Exit code is **required** (not optional)
- Leading space makes command fixed

```abnf
format1-test        = command-f1 [ input-block-f1 ] [ stdout-block-f1 ]
                      [ stderr-block-f1 ] exitcode-f1

command-f1          = command-text newline
                      ; Leading space makes command fixed

exitcode-f1         = ">>>=" [ SP exit-matcher ] newline
                      ; Exit code is REQUIRED in format 1
```

## Common Elements

```abnf
command-text        = 1*( %x20-FF )
                      ; Any printable characters

input-line          = line newline
output-line         = line newline

blank-or-comment    = comment-line / blank-line
comment-line        = *WSP "#" *( %x20-FF ) newline
blank-line          = *WSP newline
```

## Macros

Defined via command-line `-D` option, replaced literally in test file:

```bash
shelltest -DEXE=./myprogram -DDATA=./testdata tests/
```

```txt
$ EXE --config DATA/config.yaml
expected output
```
