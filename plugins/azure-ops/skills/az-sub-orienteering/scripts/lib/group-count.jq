# Count elements by the value at a dotted path, descending.
# $path: "type" or "sku.name" etc. Missing values group under "-".

def get_path($p):
    (try getpath($p | split(".")) catch null) // "-";

(if type == "array" then . else (.value // .data // []) end)
| group_by(get_path($path))
| map([ (.[0] | get_path($path)), length ])
| sort_by(-.[1])
