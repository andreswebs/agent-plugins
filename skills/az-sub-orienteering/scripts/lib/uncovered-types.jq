# Input: inventory (az resource list). $covered: newline-separated lower-case
# resource types some module claims. Output rows: [type, count] for the rest.

($covered | split("\n") | map(select(length > 0))) as $known
| group_by(.type | ascii_downcase)
| map({type: .[0].type, count: length})
| map(select((.type | ascii_downcase) as $t | ($known | index($t)) == null))
| sort_by(-.count)
| map([.type, .count])
