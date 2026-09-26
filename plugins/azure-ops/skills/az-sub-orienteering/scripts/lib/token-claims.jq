# Input: a raw JWT string. Output: only the claims provenance needs, so no other
# claim (names, email addresses) ever reaches a variable or a file.
split(".")[1]
| gsub("-"; "+") | gsub("_"; "/")
| . + ("=" * ((4 - (length % 4)) % 4))
| @base64d
| fromjson
| {oid, idtyp, tid}
