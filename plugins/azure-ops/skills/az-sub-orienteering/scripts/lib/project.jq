# Project dotted paths from each element of a list into row arrays.
# $columns: "name|resourceGroup|sku.name|properties.publicNetworkAccess"
# Arrays and objects at a path are rendered compactly; missing paths yield null.

def get_path($p):
    try getpath($p | split(".")) catch null;

def compact:
    if type == "array" then (map(if type == "object" then tojson else tostring end) | join(","))
    elif type == "object" then tojson
    else .
    end;

($columns | split("|")) as $paths
| (if type == "array" then . else (.value // .data // []) end)
| map(. as $row | [ $paths[] as $p | ($row | get_path($p) | compact) ])
