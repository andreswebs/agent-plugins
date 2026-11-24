# jq Language Reference

Version: 1.8

## Overview

jq is a dynamically-typed functional programming language for transforming JSON data.

Core characteristics:

- Immutable data with copy-on-write semantics
- Generator semantics: every expression can produce zero, one, or more outputs
- Pervasive backtracking: expressions can backtrack to preceding generators
- Lazy evaluation: function arguments are thunks (closures) evaluated on demand
- Lexically scoped with strict scoping and shadowing
- Lisp-2: separate namespaces for functions and data

## Types

jq operates on JSON types:

- `null`
- `boolean`: `true`, `false`
- `number`: IEEE 754 64-bit double-precision floating point
- `string`: Unicode (UTF-8) text
- `array`: ordered, zero-indexed sequences
- `object`: key-value pairs with string keys

Truthiness: `false` and `null` are falsy. Everything else is truthy.

Type ordering for comparisons: `null < false < true < number < string < array < object`.

## Comments

```
# this is a comment (runs to end of line)
```

## Program Structure

```
import "module" as prefix;
include "module";
def function_name: body;
def function_name(arg1; arg2): body;

main_expression
```

A jq program is a single expression, optionally preceded by imports and function definitions.

## Identity and Input

`.` returns the current input unchanged (identity filter).

```
. => input unchanged
```

## Literals

```
42
3.14
1e10
"hello"
true
false
null
```

Special values:

- `nan` -- IEEE NaN (prints as `null` in JSON output)
- `infinite` -- IEEE positive infinity
- `empty` -- produces zero outputs (triggers backtracking)

## String Interpolation

```
"Hello, \(.name)!"
```

Expressions inside `\(...)` are evaluated and interpolated. Multiple outputs from the expression produce multiple strings.

Escape sequences: `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`.

## Object and Array Access

```
.foo              # object field "foo"
.["foo"]          # same, bracket notation
."literal key"    # same, quoted field name
.[0]              # first array element
.[-1]             # last array element
.[2:5]            # array slice (inclusive start, exclusive end)
.[]               # iterate all values
..                # recursive descent (all values at all depths)
```

Optional variants suppress errors:

```
.foo?
.["foo"]?
.[0]?
.[]?
```

Chaining:

```
.a.b.c
.a["b"].c[].d
```

## Array Construction

```
[expr]
[.a, .b, .c]
[.[] | . * 2]
```

Collects all outputs of the expression into an array.

## Object Construction

```
{key: value, "key2": value2}
{a, b}                         # shorthand for {a: .a, b: .b}
{(.key): .value}               # computed key (expression in parens)
{$var}                          # shorthand for {var: $var}
```

## Pipe

```
expr1 | expr2
```

Feeds each output of `expr1` as input to `expr2`.

## Comma

```
expr1, expr2
```

Concatenates output streams. Both expressions receive the same input.

## Operators

### Arithmetic

```
+    # add numbers, concatenate strings/arrays, merge objects
-    # subtract numbers, array difference
*    # multiply numbers, string repetition, recursive object merge
/    # divide numbers, string split
%    # modulo
```

### Comparison

```
==   !=   <   >   <=   >=
```

Equality is deep/structural. Types are ordered: `null < false < true < number < string < array < object`.

### Logical

```
and    # logical AND (returns boolean)
or     # logical OR (returns boolean)
not    # logical NOT (builtin filter, not an operator)
```

### Alternative

```
expr1 // expr2
```

Outputs `expr1` if truthy, otherwise outputs `expr2`. Right-associative.

### Operator Precedence (highest to lowest)

```
?//          destructuring alternative (nonassoc)
?            postfix error suppression
- (unary)    prefix negation
* / %        multiply, divide, modulo (left)
+ -          add, subtract (left)
== != < > <= >=   comparison (nonassoc)
and          logical AND (left)
or           logical OR (left)
= |= += -= *= /= %= //=   assignment/update (nonassoc)
//           alternative (right)
as           variable binding (right)
,            concatenation (left)
|            pipe (right)
(...)        grouping
```

## Variable Binding

```
expr as $name | body
```

Binds the output of `expr` to `$name` for use in `body`. Scope extends to the right of `|`.

### Destructuring

```
expr as [$a, $b] | body                 # array destructuring
expr as {key: $val} | body              # object destructuring
expr as {$key1, $key2} | body           # shorthand object destructuring
expr as {$a, b: [$c, $d]} | body        # nested destructuring
```

### Destructuring Alternative (`?//`)

```
expr as pattern1 ?// pattern2 | body
```

Tries patterns in order. If a pattern fails to match, tries the next. Variables not matched in the successful pattern are `null`.

## Conditionals

```
if condition then expr end
if condition then expr1 else expr2 end
if c1 then e1 elif c2 then e2 else e3 end
```

When `else` is omitted, it defaults to `.` (identity).

## Function Definitions

```
def name: body;
def name(arg): body;
def name(arg1; arg2): body;
def name($arg): body;                   # value-argument shorthand
```

Arguments are separated by `;` (not `,`). Arguments are filters (thunks/closures), not values. The `$arg` form is syntactic sugar for `arg as $arg | body`.

Functions are selected by name and arity (number of arguments). `foo/0`, `foo/1`, `foo/2` are distinct functions.

Recursion: a function can call itself by name.

Local functions: `def` can appear inside another `def`.

## Lexical Scoping

- Function symbols are visible to their own body (enabling recursion) and all subsequent expressions at the same level or nested scopes
- Data symbols (`$var`) are visible to all expressions to the right of the binding pipe
- Shadowing is allowed; no way to refer to a shadowed binding
- All functions are closures capturing their lexical environment
- Closures cannot be stored in data structures (no first-class function values)

## Generators and Backtracking

Every expression can produce zero, one, or more outputs. When an expression in a pipeline produces multiple outputs, the downstream expression runs once per output.

```
(1, 2) | (. * 10)    # outputs: 10, 20
```

Cartesian product:

```
(1, 2) | (3, 4)      # outputs: 3, 4, 3, 4
```

`empty` produces zero outputs and causes backtracking to the nearest preceding generator.

## Reduce

```
reduce stream as $var (init; update)
```

Folds a stream into a single value. Applies `update` to the accumulator for each value in `stream`.

```
reduce range(5) as $n (0; . + $n)    # result: 10
```

## Foreach

```
foreach stream as $var (init; update)
foreach stream as $var (init; update; extract)
```

Like `reduce` but can emit intermediate values. The `extract` expression (default `.`) determines what is output at each step. If `extract` produces no values for a step, nothing is emitted but the state still updates.

## Label-Break

```
label $name | expr | break $name
```

`break $name` causes the nearest enclosing `label $name` to produce `empty`, effectively breaking out of the expression. Lexically scoped.

## Try-Catch

```
try expr
try expr catch handler
```

Catches errors from `expr`. In the `catch` handler, `.` is the error message string.

## Error Suppression

```
expr?
```

Shorthand for `try expr`. Converts errors to `empty`.

## Error Generation

```
error
error("message")
```

Produces an error. Useful for validation and control flow.

## Assignment Operators

Assignment operators require a path expression on the left-hand side.

### Plain Assignment (`=`)

```
.a = value
```

Sets the path to the value. RHS receives the same input as LHS.

### Update Assignment (`|=`)

```
.a |= expr
```

Threads the current value at the path through `expr`. Only the first output is used. If `expr` produces no output, the path is deleted.

### Arithmetic Update

```
.a += 1
.a -= 1
.a *= 2
.a /= 2
.a %= 3
```

Shorthand for `.a |= . + 1`, etc.

### Alternative Update

```
.a //= "default"
```

Shorthand for `.a |= . // "default"`.

## Path Expressions

Path expressions are expressions that describe locations in data structures. They are used on the left-hand side of assignments and with the `path()` function.

Valid path expressions:

```
.
.foo
.["key"]
.[n]
.[m:n]
.[]
path_expr | path_expr
path_expr, path_expr
if cond then path_expr else path_expr end
function calls with path-expression bodies
variable bindings
empty, error, break
```

Not valid in path expressions: arithmetic operators, unary negation, literals, value references.

### Path Functions

```
path(path_expr)                # outputs path arrays
paths                          # all paths in input
paths(filter)                  # paths where filter is true
leaf_paths                     # paths to leaf (non-container) values
getpath(["a", "b"])            # get value at path
setpath(["a", "b"]; value)     # set value at path
delpaths([["a"], ["b", 0]])    # delete multiple paths
del(.a, .b[0])                 # delete at path expression
```

## Builtin Functions

### Type Functions

```
type                  # returns type name as string
```

Type selectors (pass through input if type matches, otherwise produce no output):

```
arrays
objects
iterables             # arrays or objects
booleans
numbers
strings
nulls
values                # non-null values
scalars               # non-iterable values (not array or object)
normals               # normal numbers (not nan, not infinite)
finites               # finite numbers
```

Type testing:

```
isinfinite
isnan
isfinite
isnormal
```

Type conversion:

```
tostring
tonumber
toboolean
tojson                # value to JSON string
fromjson              # JSON string to value
```

### Length and Keys

```
length                # string: codepoint count; array/object: element count; number: absolute value; null: 0
utf8bytelength        # string byte length in UTF-8
keys                  # sorted keys of object, or indices of array
keys_unsorted         # keys in original order
has("key")            # true if object has key
has(index)            # true if array has index
in(object)            # true if input key exists in object
in(array)             # true if input index exists in array
```

### Array Functions

```
add                   # sum elements (numbers), concatenate (strings/arrays), merge (objects)
add(generator)        # sum generator outputs
reverse               # reverse array or string
sort                  # sort array (stable)
sort_by(expr)         # sort by expression result
group_by(expr)        # group into sub-arrays by expression
unique                # unique elements (sorted)
unique_by(expr)       # unique by expression
max                   # maximum element
min                   # minimum element
max_by(expr)          # max by expression
min_by(expr)          # min by expression
flatten               # flatten nested arrays (recursive)
flatten(n)            # flatten n levels deep
transpose             # transpose matrix (array of arrays)
contains(value)       # deep containment test
inside(value)         # inverse of contains
index(value)          # first index of value
rindex(value)         # last index of value
indices(value)        # all indices of value
combinations          # all combinations of array elements
combinations(n)       # n-way combinations
first                 # first element (as array accessor)
last                  # last element
nth(n)                # nth element
```

### Object Functions

```
keys                  # sorted keys
keys_unsorted         # keys in insertion order
values                # all values
to_entries             # [{key: k, value: v}, ...]
from_entries           # inverse of to_entries (accepts key/name/value/Key/Name/Value)
with_entries(expr)     # to_entries | map(expr) | from_entries
pick(pathexprs)        # projection: extract only specified paths
```

### String Functions

```
ascii_downcase        # lowercase (ASCII only)
ascii_upcase          # uppercase (ASCII only)
startswith(str)       # true if starts with str
endswith(str)         # true if ends with str
ltrimstr(str)         # remove prefix
rtrimstr(str)         # remove suffix
trimstr(str)          # remove prefix and suffix
trim                  # remove leading/trailing whitespace
ltrim                 # remove leading whitespace
rtrim                 # remove trailing whitespace
split(str)            # split by string separator
join(str)             # join array elements with separator
explode               # string to array of codepoints
implode               # array of codepoints to string
contains(str)         # true if input contains str
index(str)            # first byte index of str
rindex(str)           # last byte index of str
indices(str)          # all byte indices of str
```

Note: `index`, `rindex`, and `indices` are byte-oriented for strings. Use `explode` for codepoint-oriented operations.

### Format Strings

```
@text                 # calls tostring
@json                 # serialize as JSON
@html                 # HTML entity escape (<>&'")
@uri                  # percent-encode
@urid                 # percent-decode
@csv                  # format array as CSV row
@tsv                  # format array as TSV row
@sh                   # POSIX shell escape
@base64               # base64 encode (RFC 4648)
@base64d              # base64 decode
```

Can be used with string interpolation: `@html "Link: \(.url)"`.

### Regular Expression Functions

jq uses the Oniguruma regex library in PCRE-compatible mode.

```
test(regex)                   # true if input matches regex
test(regex; flags)
match(regex)                  # match object for first match
match(regex; flags)
capture(regex)                # named captures as object
capture(regex; flags)
scan(regex)                   # stream of all matching substrings
scan(regex; flags)            # with captures: stream of arrays
split(regex; flags)           # split by regex
sub(regex; replacement)       # replace first match
sub(regex; replacement; flags)
gsub(regex; replacement)      # replace all matches
gsub(regex; replacement; flags)
```

Regex flags:

```
x    extended (ignore whitespace and comments)
i    case-insensitive
m    multiline (dot matches newline)
s    single-line (^ matches \A, $ matches \Z)
n    ignore empty matches
p    both s and m modes
l    find longest match
g    global (all matches)
```

Match object structure:

```
{
  offset: number,        # codepoint offset
  length: number,        # codepoint length
  string: string,        # matched text
  captures: [
    {
      offset: number,
      length: number,
      string: string,
      name: string|null   # named capture group name
    }
  ]
}
```

### Numeric Functions

Basic:

```
floor
ceil
round
trunc
abs                   # absolute value (works via length for numbers)
fabs                  # floating-point absolute value
sqrt
pow(base; exp)
log
log2
log10
exp
exp2
exp10
```

Trigonometric:

```
sin cos tan
asin acos atan
atan2(y; x)
sinh cosh tanh
asinh acosh atanh
```

Advanced math (C library bindings):

```
cbrt expm1 log1p logb
nearbyint rint significand
gamma tgamma lgamma
erf erfc
j0 j1 jn(n)
y0 y1 yn(n)
fma(x; y; z)
hypot(x; y)
copysign(x; y)
fdim(x; y)
fmax(x; y) fmin(x; y) fmod(x; y)
frexp(x; y) ldexp(x; y) modf(x; y)
remainder(x; y) scalb(x; y) scalbln(x; y)
nextafter(x; y) nexttoward(x; y)
drem(x; y)
```

### Selection and Filtering

```
select(condition)      # pass through if condition true, otherwise empty
map(expr)              # [.[] | expr]
map_values(expr)       # apply expr to each value (preserving structure)
empty                  # produce no output
```

### Generators and Limiting

```
range(n)               # 0, 1, ..., n-1
range(from; upto)      # from, from+1, ..., upto-1
range(from; upto; by)  # from, from+by, from+2*by, ... (while < upto)
limit(n; expr)         # first n outputs of expr
skip(n; expr)          # skip first n outputs of expr
first(expr)            # first output of expr
last(expr)             # last output of expr (must consume entire stream)
nth(n; expr)           # nth output of expr
repeat(expr)           # infinite stream: expr applied repeatedly
while(cond; update)    # repeat update while cond is true
until(cond; update)    # repeat update until cond is true
isempty(expr)          # true if expr produces no outputs
```

### Recursion

```
recurse               # recursive descent (same as recurse(.[]?))
recurse(f)             # apply f recursively
recurse(f; cond)       # apply f recursively while cond is true
walk(f)                # apply f to all values bottom-up (depth-first)
..                     # recursive descent operator (all values)
```

### Logic

```
any                    # true if any element in input array is truthy
any(condition)         # true if any element satisfies condition
any(generator; condition)
all                    # true if all elements in input array are truthy
all(condition)         # true if all elements satisfy condition
all(generator; condition)
not                    # logical negation
```

### Sorting and Searching

```
sort
sort_by(expr)
group_by(expr)
unique
unique_by(expr)
bsearch(value)         # binary search in sorted array; returns index or (-1 - insertion_point)
```

### Date and Time

```
now                    # current Unix timestamp (float)
gmtime                 # timestamp to UTC broken-down time [year,month(0-11),day,hour,min,sec,weekday,yearday]
localtime              # timestamp to local broken-down time
mktime                 # broken-down time to timestamp
strftime(fmt)          # format UTC time as string
strflocaltime(fmt)     # format local time as string
strptime(fmt)          # parse time string to broken-down time
todate                 # timestamp to ISO 8601 string
todateiso8601          # same as todate
fromdate               # ISO 8601 string to timestamp
fromdateiso8601        # same as fromdate
```

### I/O

```
input                  # read next JSON input
inputs                 # stream of all remaining JSON inputs
debug                  # print input to stderr as ["DEBUG:", value], pass through
debug(msgs)            # print custom messages to stderr, pass through
stderr                 # print input to stderr, pass through
input_filename         # name of current input file (or null)
input_line_number      # current line number in input
```

### SQL-Style Operators

```
INDEX(stream; idx_expr)              # build index object from stream
IN(stream)                           # true if input appears in stream
IN(source; stream)                   # true if any source value appears in stream
JOIN($idx; stream; idx_expr; join_expr)   # join stream to index
JOIN($idx; stream; idx_expr)         # join with identity join_expr
JOIN($idx; idx_expr)                 # join input to index
```

### Streaming

```
tostream               # convert input to stream of [path, value] pairs
fromstream(expr)       # reconstruct value from stream
truncate_stream(expr)  # remove leading path elements from stream
```

### Program Control

```
halt                   # stop with exit code 0
halt_error             # stop with exit code 5, print input to stderr
halt_error(code)       # stop with custom exit code, print input to stderr
error                  # raise error with input as message
error(msg)             # raise error with custom message
```

### Introspection

```
builtins               # array of all builtin names with arity (e.g., "map/1")
$__loc__               # object with "file" and "line" of current location
$ENV                   # object of environment variables
env                    # same as $ENV
$ARGS.named            # object of named arguments (from --arg, --argjson)
$ARGS.positional       # array of positional arguments (from --args, --jsonargs)
```

### Other

```
modulemeta             # module metadata
have_decnum            # true if built with decimal number support
have_literal_numbers   # true if literal number preservation is enabled
```

## Module System

### Import

```
import "path" as prefix;
```

Imports a module with a namespace prefix. Access functions as `prefix::function_name`.

### Include

```
include "path";
```

Includes a module inline; all its definitions become available without prefix.

### Import Data

```
import "path" as $var;
```

Imports a JSON file and binds its contents to `$var`.

### Module Metadata

```
module { version: 1, description: "my module" };
```

Declares metadata for the module. Query with `modulemeta`.

### Search Paths

Default search order:

1. `~/.jq`
2. `$ORIGIN/../lib/jq`
3. `$ORIGIN/../lib`

`-L` flag prepends directories to the search path.

Module resolution: `foo/bar` resolves to `foo/bar.jq` or `foo/bar/bar.jq`.

## Oniguruma Regex Reference

jq uses the Oniguruma regex library. This section covers the regex syntax available in `test`, `match`, `capture`, `scan`, `sub`, `gsub`, and `split`.

### Character Escapes

```
\t    horizontal tab (0x09)
\n    newline (0x0A)
\r    carriage return (0x0D)
\f    form feed (0x0C)
\a    bell (0x07)
\e    escape (0x1B)
\v    vertical tab (0x0B)
\b    backspace (0x08, only in character classes)
\nnn  octal character
\xHH  hex character
\x{7HHHHHHH}   wide hex character (codepoint)
\cx   control character
```

### Character Types

```
.     any character except newline
\w    word character (alphanumeric, _, multibyte; Unicode: Letter|Mark|Number|Connector_Punctuation)
\W    non-word character
\s    whitespace
\S    non-whitespace
\d    decimal digit [0-9]
\D    non-digit
\h    hexadecimal digit [0-9a-fA-F]
\H    non-hex-digit
```

### Unicode Properties

```
\p{PropertyName}    match characters with property
\P{PropertyName}    match characters without property
\p{^PropertyName}   same as \P{PropertyName}
```

Categories: `C`, `L`, `M`, `N`, `P`, `S`, `Z` and their subcategories (`Cc`, `Cf`, `Ll`, `Lu`, `Nd`, etc.).

Scripts: `Latin`, `Greek`, `Cyrillic`, `Arabic`, `Han`, `Hiragana`, `Katakana`, etc.

POSIX-style: `Alnum`, `Alpha`, `Blank`, `Cntrl`, `Digit`, `Graph`, `Lower`, `Print`, `Punct`, `Space`, `Upper`, `XDigit`, `Word`, `ASCII`.

### Quantifiers

Greedy:

```
?       0 or 1
*       0 or more
+       1 or more
{n}     exactly n
{n,m}   n to m
{n,}    n or more
{,n}    0 to n
```

Non-greedy (reluctant):

```
??  *?  +?  {n,m}?  {n,}?  {,n}?
```

Possessive (no backtracking):

```
?+  *+  ++
```

### Anchors

```
^     beginning of line
$     end of line
\b    word boundary
\B    non-word boundary
\A    beginning of string
\Z    end of string or before trailing newline
\z    end of string
\G    match start position
```

### Character Classes

```
[abc]         character set
[^abc]        negated set
[a-z]         range
[a-z&&[^m-p]] intersection
```

POSIX bracket expressions:

```
[:alnum:]  [:alpha:]  [:ascii:]  [:blank:]  [:cntrl:]
[:digit:]  [:graph:]  [:lower:]  [:print:]  [:punct:]
[:space:]  [:upper:]  [:xdigit:] [:word:]
[:^class:] negated form
```

### Groups

```
(expr)              captured group
(?:expr)            non-capturing group
(?<name>expr)       named captured group
(?'name'expr)       named captured group (alt syntax)
(?>expr)            atomic group (no backtracking)
(?#comment)         comment
```

### Lookahead and Lookbehind

```
(?=expr)            positive lookahead
(?!expr)            negative lookahead
(?<=expr)           positive lookbehind (fixed-length only)
(?<!expr)           negative lookbehind (fixed-length only)
```

### Inline Options

```
(?imx-imx)          set/unset options globally
(?imx-imx:expr)     set/unset options for subexpression
```

Options: `i` (case-insensitive), `m` (multiline: dot matches newline), `x` (extended: ignore whitespace/comments).

### Back References

```
\1 \2 ...           by group number
\k<name>            by group name
\k<n>               by group number
\k<-n>              by relative group number
\k<name+level>      with nest level
```

### Subexp Calls

```
\g<name>            call named group
\g<n>               call by group number
\g<-n>              call by relative number
```

## Pitfalls

### Comma vs Semicolon

`,` joins output streams (both expressions get the same input). `;` separates function arguments.

```
foo(1, 2)           # calls foo/1 with generator (1, 2) producing two outputs
foo(1; 2)           # calls foo/2 with two separate arguments
```

### Number Precision

IEEE 754 64-bit doubles. Maximum reliable integer: 2^53 (9007199254740992). Larger integers may lose precision.

### String Index Functions

`index`, `rindex`, and `indices` are byte-oriented for strings. For codepoint-oriented indexing, use `explode`.

```
"aéb" | index("b")               # returns 3 (byte offset)
"aéb" | explode | index(98)      # returns 2 (codepoint offset)
```

### Empty in Reduce

Avoid `empty` in reduce update expressions. Behavior may be inconsistent.

### Assignment with Empty

```
.a = empty           # produces empty stream (no output)
.a |= empty          # deletes path (different behavior)
```

### NaN and Infinity

`nan` prints as `null` in JSON output. `infinite` prints as `1.7976931348623157e+308`. Use `isnan` and `isinfinite` to test.

### Keywords

Reserved words cannot be used as variable names: `and`, `as`, `break`, `catch`, `def`, `elif`, `else`, `end`, `foreach`, `if`, `import`, `include`, `label`, `module`, `or`, `reduce`, `then`, `try`.

## Advanced Topics

### Tail-Call Optimization

Available for zero-argument recursive functions. Use accumulator pattern:

```
def factorial:
  def _go:
    if .[0] <= 1 then .[1]
    else [.[0] - 1, .[0] * .[1]] | _go
    end;
  [., 1] | _go;
```

### Streaming

For processing large JSON without loading entirely into memory:

```
# command line
jq --stream ...

# in-program
tostream                            # convert to [path, value] pairs
fromstream(expr)                    # reconstruct from stream
truncate_stream(expr)               # trim path prefixes
```

### Parsing Expression Grammars

jq can implement PEG parsers using its backtracking semantics:

```
def star(E): (E | star(E)) // .;
def plus(E): E | (plus(E) // .);
def optional(E): E // .;
def amp(E): . as $in | E | $in;
def neg(E): select([E] == []);
def eos: select((.remainder | length) == 0);
def consume($re):
  (.remainder | match("^" + $re)) as $m
  | .remainder |= .[$m.length:]
  | .match = $m.string;
```

### Finite State Machines

Use `foreach` with state objects:

```
def fsm(stream; init; transition; extract):
  foreach stream as $item (init;
    .item = $item | transition;
    extract);
```

State transitions use chained `select` with `//`:

```
(select(.state == "start") | handle_start)
// (select(.state == "running") | handle_running)
// (select(.state == "done") | handle_done)
```
