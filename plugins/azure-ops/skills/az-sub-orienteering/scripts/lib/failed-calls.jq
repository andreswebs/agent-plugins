# Input: raw text, one "module<TAB>cause<TAB>call" line per failed call.
# Output: rows grouped by module and cause, with a count and up to three calls.
split("\n")
| map(select(length > 0) | split("\t") | {module: .[0], cause: .[1], call: .[2]})
| group_by([.module, .cause])
| map([.[0].module, .[0].cause, length, (map(.call) | .[:3] | join(", ")) + (if length > 3 then ", ..." else "" end)])
