# Render an array of row arrays as a GitHub-flavoured markdown table.
# $header: column titles separated by "|".
# Cells are stringified; null becomes "-", pipes are escaped, newlines become <br>.

def cell:
    if . == null then "-"
    elif type == "string" then .
    elif type == "boolean" or type == "number" then tostring
    else tojson
    end
    | gsub("\\|"; "\\|")
    | gsub("\r?\n"; "<br>")
    | if . == "" then "-" else . end;

($header | split("|")) as $cols
| ("| " + ($cols | join(" | ")) + " |"),
  ("|" + ($cols | map(" --- |") | join(""))),
  (.[] | "| " + (map(cell) | join(" | ")) + " |")
